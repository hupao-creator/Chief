package store_test

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/hupao-creator/Chief/internal/core/store"
	"github.com/hupao-creator/Chief/internal/platform/sqlite"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

// Released v0.1.0-alpha.2 schema. Construct it independently of the current
// initializer so an accidental format or upgrade change cannot update the oracle.
const alphaSchema = `
PRAGMA page_size=8192;
PRAGMA journal_mode=WAL;
CREATE TABLE records (key TEXT PRIMARY KEY, body BLOB NOT NULL CHECK(length(body)<=52428800)) STRICT;
CREATE TABLE entity_order (kind TEXT NOT NULL, position INTEGER NOT NULL CHECK(position>=0), id TEXT NOT NULL, PRIMARY KEY(kind,position), UNIQUE(kind,id)) STRICT;
CREATE TABLE store_meta (id INTEGER PRIMARY KEY CHECK(id=1), revision INTEGER NOT NULL CHECK(revision>=0)) STRICT;
INSERT INTO store_meta VALUES(1,7);
INSERT INTO entity_order VALUES('threads',0,'fixture');
PRAGMA application_id=0x4d4f4b53;
PRAGMA user_version=1;`

const streamKey = "thread:fixture"

func legacyStream(path string, body []byte) error {
	db, err := sqlite.Open(path, false)
	if err != nil {
		return err
	}
	defer db.Close()
	if err := db.Exec(alphaSchema); err != nil {
		return err
	}
	if err := db.Exec("INSERT INTO records VALUES('untouched',?)", body); err != nil {
		return err
	}
	return db.Exec("INSERT INTO records VALUES(?,?)", streamKey, body)
}

func checkVersion(t *rapid.T, conn *sqlite.DB, want int64) {
	rows, err := conn.Query("PRAGMA user_version")
	if err != nil || len(rows) != 1 || rows[0]["user_version"] != want {
		t.Fatalf("on-disk format: %v, %v, want %d", rows, err, want)
	}
}

func rawText(text string) []byte {
	// Keep even insignificant whitespace in the byte-for-byte Raw contract.
	b, err := json.Marshal(text)
	if err != nil {
		panic(err)
	}
	return append(append([]byte(" \n"), b...), '\t')
}

func verifyStream(t *rapid.T, s store.Snapshot, want []byte, revision uint64) {
	got, ok := s.Raw(streamKey)
	if !ok || !bytes.Equal(got, want) || s.Revision() != revision || strings.Join(s.Order("threads"), ",") != "fixture" {
		t.Fatalf("stream, revision or order differs: bytes=%d/%d rev=%d/%d", len(got), len(want), s.Revision(), revision)
	}
}

// Child exits after an acknowledged write, before SQLite close/checkpoint.
// The parent alone retains the independent oracle and opens the resulting WAL.
const crashChildEnv = "CHIEF_PBT_STREAM_CRASH_CHILD"

// The child wrote one transaction to a fresh WAL. Reopen a copy ending
// before its first complete commit frame, with at least one staged page.
func verifyUncommittedPrefix(t *rapid.T, path string, want []byte, revision uint64) {
	wal, err := os.ReadFile(path + "-wal")
	if err != nil || len(wal) < 32 {
		t.Fatalf("missing child WAL: %v", err)
	}
	frame := 24 + int(binary.BigEndian.Uint32(wal[8:12]))
	for off := 32; off+frame <= len(wal); off += frame {
		if binary.BigEndian.Uint32(wal[off+4:off+8]) == 0 {
			continue
		}
		if off == 32 {
			t.Fatal("child transaction has no staged page before COMMIT")
		}
		cut := rapid.IntRange(32+frame, off+frame-1).Draw(t, "wal-prefix-bytes")
		main, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		copyPath := path + ".interrupted"
		if err := os.WriteFile(copyPath, main, 0600); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(copyPath+"-wal", wal[:cut], 0600); err != nil {
			t.Fatal(err)
		}
		db, err := store.Open(copyPath)
		if err != nil {
			t.Fatal(err)
		}
		defer db.Close()
		verifyStream(t, db.Snapshot(), want, revision)
		if db.Snapshot().Has("receipt:fixture") {
			t.Fatal("receipt published from incomplete WAL")
		}
		return
	}
	t.Fatal("missing child COMMIT frame")
}

func TestStreamStorageProperties(t *testing.T) {
	if os.Getenv(crashChildEnv) == "1" {
		var body []byte
		if err := json.NewDecoder(os.Stdin).Decode(&body); err != nil {
			t.Fatal(err)
		}
		db, err := store.Open("state.sqlite")
		if err != nil {
			t.Fatal(err)
		}
		if _, err = db.Update(context.Background(), func(tx *store.Tx) error {
			if err := tx.PutRaw(streamKey, body); err != nil {
				return err
			}
			return tx.Put("receipt:fixture", tx.Revision()+1)
		}); err != nil {
			t.Fatal(err)
		}
		os.Exit(0)
	}
	rapidcheck.Check(t, func(t *rapid.T) {
		ctx := context.Background()
		root, err := os.MkdirTemp("", "chief-stream-property-")
		if err != nil {
			t.Fatal(err)
		}
		defer os.RemoveAll(root)
		path := filepath.Join(root, "state.sqlite")
		size := rapid.SampledFrom([]int{32, 65535, 65536, 65537, 73728, 131072}).Draw(t, "initial-bytes")
		suffix := rapid.SampledFrom([]string{"界", "📚", "\"\n"}).Draw(t, "suffix")
		text := strings.Repeat("h", size-len(rawText(suffix))) + suffix
		want := rawText(text)
		if err := legacyStream(path, want); err != nil {
			t.Fatal(err)
		}
		open := func() *store.Store {
			db, err := store.Open(path)
			if err != nil {
				t.Fatal(err)
			}
			return db
		}
		db := open()
		defer func() {
			if db != nil {
				_ = db.Close()
			}
		}()
		revision := uint64(7)
		legacy := db.Snapshot()
		original := want
		verifyStream(t, legacy, want, revision)
		// Force a real SQL failure after record writes, then retry the same body.
		// The first large write may also have staged the on-disk format change.
		fault, err := sqlite.Open(path, false)
		if err != nil {
			t.Fatal(err)
		}
		defer fault.Close()
		checkVersion(t, fault, 1)
		if err := fault.Exec("CREATE TRIGGER fail_stream BEFORE UPDATE ON store_meta BEGIN SELECT RAISE(ABORT,'injected revision failure'); END"); err != nil {
			t.Fatal(err)
		}
		next := rawText(text + strings.Repeat("a", 65536))
		put := func(body []byte) (store.Snapshot, error) {
			return db.Update(ctx, func(tx *store.Tx) error { return tx.PutRaw(streamKey, body) })
		}
		if _, err = put(next); err == nil || !strings.Contains(err.Error(), "injected revision failure") {
			t.Fatalf("missing SQL failure: %v", err)
		}
		verifyStream(t, db.Snapshot(), want, revision)
		checkVersion(t, fault, 1)
		if err := fault.Exec("DROP TRIGGER fail_stream"); err != nil {
			t.Fatal(err)
		}
		if err := fault.Close(); err != nil {
			t.Fatal(err)
		}
		if err := db.Close(); err != nil {
			t.Fatal(err)
		}
		db = open()
		verifyStream(t, db.Snapshot(), want, revision)
		s, err := put(next)
		if err != nil {
			t.Fatal(err)
		}
		want = next
		revision++
		verifyStream(t, s, want, revision)
		// Concurrent producers append at the FIFO update boundary. Acknowledge and
		// sort by revision to check every intermediate snapshot, including retries.
		type completed struct {
			suffix string
			s      store.Snapshot
			err    error
		}
		n := rapid.IntRange(2, 7).Draw(t, "writers")
		done := make(chan completed, n)
		for i := range n {
			suffix := fmt.Sprintf("%d/%s", i, rapid.SampledFrom([]string{"正文", "\t", "🐕", "a"}).Draw(t, "fragment"))
			go func() {
				s, err := db.Update(ctx, func(tx *store.Tx) error {
					var body string
					found, err := tx.Get(streamKey, &body)
					if err != nil {
						return err
					}
					if !found {
						return errors.New("missing stream")
					}
					return tx.PutRaw(streamKey, rawText(body+suffix))
				})
				done <- completed{suffix, s, err}
			}()
		}
		var updates []completed
		for range n {
			updates = append(updates, <-done)
		}
		sort.Slice(updates, func(i, j int) bool { return updates[i].s.Revision() < updates[j].s.Revision() })
		text += strings.Repeat("a", 65536)
		for _, update := range updates {
			if update.err != nil {
				t.Fatal(update.err)
			}
			text += update.suffix
			revision++
			want = rawText(text)
			verifyStream(t, update.s, want, revision)
		}
		s, err = put(want)
		if err != nil {
			t.Fatal(err)
		}
		verifyStream(t, s, want, revision)
		// Vary edits and representation crossings; keep the previous snapshot
		// across delete/recreate and check each accepted version after reopen.
		for edit := range rapid.IntRange(2, 8).Draw(t, "edits") {
			if edit == 0 {
				// Exercise the empty terminal part on every trace.
				target := rapid.IntRange(9, 20).Draw(t, "whole-parts") * 7680
				text = strings.Repeat("z", target-len(rawText("終"))) + "終"
			} else {
				keep := rapid.IntRange(0, len(text)).Draw(t, "keep-prefix")
				prefix := strings.ToValidUTF8(text[:keep], "")
				text = prefix + strings.Repeat("z", rapid.SampledFrom([]int{0, 1, 7680, 65536}).Draw(t, "insert")) + "終"
			}
			next = rawText(text)
			before := db.Snapshot()
			if rapid.Bool().Draw(t, "delete") {
				if _, err := db.Update(ctx, func(tx *store.Tx) error { return tx.Delete(streamKey) }); err != nil {
					t.Fatal(err)
				}
				revision++
				if db.Snapshot().Has(streamKey) {
					t.Fatal("deleted stream visible")
				}
				verifyStream(t, before, want, revision-1)
				want = nil
			}
			if _, err := put(next); err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(next, want) {
				revision++
			}
			want = next
			if err := db.Close(); err != nil {
				t.Fatal(err)
			}
			db = open()
			verifyStream(t, db.Snapshot(), want, revision)
		}
		verifyStream(t, legacy, original, 7)
		if err := db.Close(); err != nil {
			t.Fatal(err)
		}
		db = nil
		next = rawText(text + " acknowledged " + strings.Repeat("d", 65536))
		payload, err := json.Marshal(next)
		if err != nil {
			t.Fatal(err)
		}
		cmd := exec.Command(os.Args[0], "-test.run=^TestStreamStorageProperties$")
		cmd.Dir = root
		cmd.Env = append(os.Environ(), crashChildEnv+"=1", "GORACE=atexit_sleep_ms=0")
		cmd.Stdin = bytes.NewReader(payload)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("child commit: %v %s", err, out)
		}
		verifyUncommittedPrefix(t, path, want, revision)
		db = open()
		revision++
		verifyStream(t, db.Snapshot(), next, revision)
		if sibling, ok := db.Snapshot().Raw("untouched"); !ok || !bytes.Equal(sibling, original) {
			t.Fatal("untouched Alpha record changed")
		}
		var receipt uint64
		if ok, err := db.Snapshot().Get("receipt:fixture", &receipt); !ok || err != nil || receipt != revision {
			t.Fatal("acknowledged stream and receipt did not recover together")
		}
		if err := db.Close(); err != nil {
			t.Fatal(err)
		}
		db = nil
		damaged, err := sqlite.Open(path, false)
		if err != nil {
			t.Fatal(err)
		}
		checkVersion(t, damaged, 2)
		statement := rapid.SampledFrom([]string{
			"DELETE FROM record_chunks WHERE key=? AND part=1",
			"DELETE FROM record_chunks WHERE key=? AND part=(SELECT max(part) FROM record_chunks WHERE key='thread:fixture')",
			"UPDATE record_chunks SET body=x'ff' WHERE key=? AND part=1",
			"INSERT INTO records(key,body) VALUES(?,x'6e756c6c')",
		}).Draw(t, "corruption")
		if err := damaged.Exec(statement, streamKey); err != nil {
			t.Fatal(err)
		}
		if err := damaged.Close(); err != nil {
			t.Fatal(err)
		}
		if db, err = store.Open(path); !errors.Is(err, store.ErrInvalidState) {
			t.Fatalf("malformed chunked state admitted: %v", err)
		}
	})
}
