// Reproduce directory discovery on the SQL audit's long-history Codex fixture.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"time"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
	core "github.com/hupao-creator/Chief/internal/core/runtime"
	"github.com/hupao-creator/Chief/internal/core/store"
	"github.com/hupao-creator/Chief/internal/plugins/harness/codex"
)

type offline struct{ plugin.Harness }

func must(err error) {
	if err != nil {
		panic(err)
	}
}

func main() {
	const epoch = 1700000000000
	ctx := context.Background()
	root, err := os.MkdirTemp("", "chief-known-directories-")
	must(err)
	defer os.RemoveAll(root)
	cwd := filepath.Join(root, "project")
	must(os.Mkdir(cwd, 0700))
	db, err := store.Open(filepath.Join(root, "state.sqlite"))
	must(err)
	defer func() { must(db.Close()) }()

	state := codex.EmptyState(epoch)
	for i := range 16 {
		id := fmt.Sprintf("past-%02d", i)
		at := int64(epoch + 4*i + 1)
		input := codex.Map{"parts": []any{codex.Map{"kind": "text", "text": "Review " + id}}}
		state = codex.StageExecution(state, id, input, at, nil)
		reply := strings.Repeat("Review "+id+" and confirm the saved result. ", 256)
		state = codex.ReduceEvent(state, id, codex.Map{"type": "text-final", "itemId": id, "at": at + 1, "text": reply})
		state = codex.ReduceEvent(state, id, codex.Map{"type": "done", "outcome": "completed", "at": at + 2})
	}
	encoded, err := json.Marshal(state)
	must(err)
	harness := codex.New(plugin.HostContext{})
	observation, err := harness.SessionState().Project(encoded)
	must(err)
	ids := make([]string, 256)
	_, err = db.Update(ctx, func(tx *store.Tx) error {
		for i := range ids {
			id := fmt.Sprintf("t-%04d", i)
			ids[i] = id
			thread := model.ThreadRecord{Title: "Fixture", Tags: []string{}, TagEmojis: map[string]string{},
				SessionRecord: model.SessionRecord{ID: id, HarnessID: "codex", SessionState: encoded,
					Observation: observation, CreatedAt: epoch, UpdatedAt: epoch, Cwd: cwd, Settings: json.RawMessage("{}")}}
			if err := tx.Put("thread:"+id, thread); err != nil {
				return err
			}
		}
		return tx.SetOrder("threads", ids)
	})
	must(err)
	rt, err := core.New(ctx, core.Config{Store: db, DataDir: filepath.Join(root, "profile"), DefaultCwd: cwd,
		Harnesses: map[string]plugin.Harness{"codex": offline{harness}}})
	must(err)
	defer func() { must(rt.Close(ctx)) }()
	expected := []model.KnownDirectory{{Name: "project", Path: cwd}}
	sample := func(stage string) {
		runtime.GC()
		var before, after runtime.MemStats
		runtime.ReadMemStats(&before)
		start := time.Now()
		dirs, err := rt.KnownDirectories(ctx)
		elapsed := time.Since(start)
		runtime.ReadMemStats(&after)
		must(err)
		if !slices.Equal(dirs, expected) {
			panic(fmt.Sprintf("unexpected directories: %v", dirs))
		}
		must(json.NewEncoder(os.Stdout).Encode(map[string]any{"stage": stage, "directories": len(dirs),
			"ns": elapsed.Nanoseconds(), "allocatedBytes": after.TotalAlloc - before.TotalAlloc,
			"recordBytes": db.Snapshot().RecordBytes("thread:" + ids[0])}))
	}
	sample("first")
	for range 5 {
		sample("repeat")
	}
	// No order entry for the new record. A pending publisher must not hide its cwd.
	newPath := filepath.Join(root, "unlisted")
	_, err = db.Update(ctx, func(tx *store.Tx) error {
		return tx.Put("thread:unlisted", model.ThreadRecord{SessionRecord: model.SessionRecord{
			ID: "unlisted", Cwd: newPath, HarnessID: "codex", SessionState: encoded}})
	})
	must(err)
	expected = append(expected, model.KnownDirectory{Name: "unlisted", Path: newPath})
	sample("insert")
	_, err = db.Update(ctx, func(tx *store.Tx) error { return tx.Delete("thread:unlisted") })
	must(err)
	expected = expected[:1]
	sample("delete")
	// Refresh the same identity, including a broken record followed by repair.
	// Reusing its previous cwd would hide both the move and the decode error.
	key := "thread:" + ids[0]
	var original model.ThreadRecord
	_, err = db.Snapshot().Get(key, &original)
	must(err)
	replace := func(record any) {
		_, err := db.Update(ctx, func(tx *store.Tx) error { return tx.Put(key, record) })
		must(err)
	}
	moved := original
	moved.Cwd = newPath
	replace(moved)
	expected = append(expected, model.KnownDirectory{Name: "unlisted", Path: newPath})
	sample("move")
	replace("invalid Thread record")
	if _, err := rt.KnownDirectories(ctx); err == nil {
		panic("directory lookup accepted a malformed replacement")
	}
	replace(original)
	expected = expected[:1]
	sample("repair")
	cancelled, cancel := context.WithCancel(ctx)
	cancel()
	if _, err := rt.KnownDirectories(cancelled); err != context.Canceled {
		panic("cancelled discovery returned without cancellation")
	}
}
