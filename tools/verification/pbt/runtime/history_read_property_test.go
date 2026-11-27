package runtime_test

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"testing"
	"testing/synctest"
	"time"

	"github.com/hupao-creator/Chief/internal/core/plugin"
	core "github.com/hupao-creator/Chief/internal/core/runtime"
	"github.com/hupao-creator/Chief/internal/core/store"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

type historyPeer struct {
	harness
}

func (*historyPeer) Open(ctx context.Context, open plugin.OpenContext) (plugin.Handle, error) {
	return &historyHandle{&handle{ctx: ctx, open: open}}, nil
}

type historyHandle struct{ *handle }

func (h *historyHandle) Read(ctx context.Context, question string) (string, error) {
	if question == "silent" {
		if _, bounded := ctx.Deadline(); !bounded {
			return "", errors.New("silent read has no deadline")
		}
		<-ctx.Done()
		// A late answer racing retirement must not become a successful read.
		return "late answer", nil
	}
	return question, nil
}

// PBT-RUNTIME-HISTORY-READ exercises the public admission path with a silent
// Harness. Virtual time lets shorter callers expire while the owner still runs.
func TestHistoryReadDeadlineProperties(t *testing.T) {
	rapidcheck.Check(t, func(rt *rapid.T) {
		budgets := rapid.SliceOfN(rapid.IntRange(1, 89), 1, 10).Draw(rt, "waiter-seconds")
		root := t.TempDir()
		var err error
		synctest.Test(t, func(*testing.T) { err = checkHistoryReads(root, budgets) })
		if err != nil {
			rt.Fatal(err)
		}
	})
}

func checkHistoryReads(root string, budgets []int) error {
	db, err := store.Open(filepath.Join(root, "state.sqlite"))
	if err != nil {
		return err
	}
	defer db.Close()
	ctx := context.Background()
	r, err := core.New(ctx, core.Config{Store: db, DataDir: root, DefaultCwd: root, Harnesses: map[string]plugin.Harness{"fixture": &historyPeer{}}})
	if err != nil {
		return err
	}
	defer r.Close(ctx)
	source, err := create(r)
	if err != nil {
		return err
	}
	id := source.Record.ID
	start := time.Now()
	results := make(chan error, len(budgets)+1)
	read := func(ctx context.Context, question string, budget time.Duration) {
		answer, err := r.ReadThread(ctx, id, question)
		if answer != "" || !errors.Is(err, context.DeadlineExceeded) || time.Since(start) != budget {
			results <- fmt.Errorf("%s read with budget %s returned %q, %v after %s", question, budget, answer, err, time.Since(start))
			return
		}
		results <- nil
	}
	go read(ctx, "silent", 90*time.Second)
	synctest.Wait()
	for _, seconds := range budgets {
		go func() {
			budget := time.Duration(seconds) * time.Second
			short, cancel := context.WithTimeout(ctx, budget)
			defer cancel()
			read(short, "queued", budget)
		}()
	}
	for range len(budgets) + 1 {
		err = errors.Join(err, <-results)
	}
	if answer, nextErr := r.ReadThread(ctx, id, "next"); nextErr != nil || answer != "next" {
		return errors.Join(err, fmt.Errorf("next read could not reuse the source: %q, %v", answer, nextErr))
	}
	return err
}
