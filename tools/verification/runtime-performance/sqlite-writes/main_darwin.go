// Run without arguments. All database and native-peer state belongs to a fresh temporary directory.
package main

import "C"

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
	core "github.com/hupao-creator/Chief/internal/core/runtime"
	"github.com/hupao-creator/Chief/internal/core/store"
	"github.com/hupao-creator/Chief/internal/hosts/applicationhost"
	"github.com/hupao-creator/Chief/internal/platform/sqlite"
	gitapp "github.com/hupao-creator/Chief/internal/plugins/applications/git"
	"github.com/hupao-creator/Chief/internal/plugins/harness/codex"
)

const (
	historyTurns = 16
	packets      = 40
	epoch        = 1700000000000
)

type peer struct {
	*codex.Adapter
	open map[string]plugin.OpenContext
}

func (p *peer) Open(_ context.Context, o plugin.OpenContext) (plugin.Handle, error) {
	p.open[o.ThreadID] = o
	return handle{}, nil
}

type handle struct{ plugin.Handle }

func (handle) Read(context.Context, string) (string, error) { return "ready", nil }
func (handle) Close() error                                 { return nil }

// Supply observations in place of the Git polling process. The registered
// git.sync command still runs the host planner, reducer, receipt and event writes.
type gitPeer struct {
	*gitapp.Service
	domain plugin.DomainClient
}

func (p *gitPeer) Register(r plugin.Registry) error {
	return p.Service.Register(gitRegistry{r, p})
}

type gitRegistry struct {
	plugin.Registry
	peer *gitPeer
}

func (r gitRegistry) BackgroundAgent(d plugin.BackgroundAgentDefinition) error {
	d.Create = func(c plugin.BackgroundAgentContext) (plugin.RuntimeParticipant, error) {
		r.peer.domain = c.Domain
		return r.peer, nil
	}
	return r.Registry.BackgroundAgent(d)
}
func (*gitPeer) Start(context.Context, plugin.RuntimeStartContext) error { return nil }
func (*gitPeer) Stop(context.Context) error                              { return nil }

func must(err error) {
	if err != nil {
		panic(err)
	}
}

func encode(value any) json.RawMessage {
	b, err := json.Marshal(value)
	must(err)
	return b
}

func input(s string) codex.Map {
	return codex.Map{"parts": []any{codex.Map{"kind": "text", "text": s}}}
}

func history() codex.Map {
	state := codex.EmptyState(epoch)
	for i := range historyTurns {
		id := fmt.Sprintf("past-%02d", i)
		at := int64(epoch + 4*i + 1)
		state = codex.StageExecution(state, id, input("Review "+id), at, nil)
		message := strings.Repeat("Review "+id+" and confirm the saved result. ", 256)
		state = codex.ReduceEvent(state, id, codex.Map{"type": "text-final", "itemId": id, "at": at + 1, "text": message})
		state = codex.ReduceEvent(state, id, codex.Map{"type": "done", "outcome": "completed", "at": at + 2})
	}
	return state
}

type change struct {
	Count        int
	Bytes        int64
	SQLBlobBytes int64
}

var meterMu sync.Mutex
var blobBytesByKind = map[string]int64{}

//export recordBlobBytes
func recordBlobBytes(key *C.char, size C.int) {
	kind, _, _ := strings.Cut(C.GoString(key), ":")
	meterMu.Lock()
	blobBytesByKind[kind] += int64(size)
	meterMu.Unlock()
}

func takeBlobBytes() map[string]int64 {
	meterMu.Lock()
	defer meterMu.Unlock()
	previous := blobBytesByKind
	blobBytesByKind = map[string]int64{}
	return previous
}

type sample struct {
	Operation                                                string
	InputBytes                                               int
	Transactions, BlobBytes, WALFrames, ProcessBytes, Micros int64
	DBWriteBytes, WALWriteBytes, CommitMicros                int64
	Records                                                  map[string]change
}

// Seed both binaries with the same inline Alpha records. The first change to
// each historical session is timed, including any representation conversion.
func seedInline(path string, record model.SessionRecord, owner plugin.BackgroundAgentRef) string {
	empty, err := store.Open(path)
	must(err)
	must(empty.Close())
	conn, err := sqlite.Open(path, false)
	must(err)
	version, err := conn.Query("PRAGMA user_version")
	must(err)
	if version[0]["user_version"] != int64(1) {
		panic("fixture requires the Alpha v1 schema")
	}
	thread := model.ThreadRecord{SessionRecord: record, Title: "Fixture", Tags: []string{}, TagEmojis: map[string]string{}}
	private := plugin.PrivateSessionSnapshot{Ref: plugin.PrivateSessionRef{Owner: owner, SessionKey: "fixture", SessionID: "private"}, Record: record}
	private.Record.ID = "private"
	const key = "private-session:writer:fixture"
	must(conn.Exec("BEGIN IMMEDIATE"))
	for _, row := range []struct {
		key   string
		value any
	}{{"thread:public", thread}, {key, private}, {"private-session-index:private", key}} {
		must(conn.Exec("INSERT INTO records VALUES(?,?)", row.key, []byte(encode(row.value))))
	}
	must(conn.Exec("INSERT INTO entity_order VALUES('threads',0,'public'); UPDATE store_meta SET revision=1; COMMIT"))
	must(conn.Close())
	data, err := os.ReadFile(path)
	must(err)
	return fmt.Sprintf("%x", sha256.Sum256(data))
}

func main() {
	ctx := context.Background()
	root, err := os.MkdirTemp("", "chief-sqlite-writes-")
	must(err)
	defer os.RemoveAll(root)
	path := filepath.Join(root, "state.sqlite")
	p := &peer{Adapter: codex.New(plugin.HostContext{}), open: map[string]plugin.OpenContext{}}
	initial := history()
	record := model.SessionRecord{ID: "public", HarnessID: "codex", SessionState: encode(initial), Settings: encode(codex.Map{}), CreatedAt: epoch, UpdatedAt: epoch, Cwd: "/fixture"}
	record.Observation, err = p.SessionState().Project(record.SessionState)
	must(err)
	owner := plugin.BackgroundAgentRef{PluginID: "fixture", AgentID: "writer", Binding: plugin.ScopeBinding{Kind: plugin.GlobalScope}}
	seedSHA := seedInline(path, record, owner)
	installCounters()
	db, err := store.Open(path)
	must(err)
	host, err := core.New(ctx, core.Config{DataDir: root, DefaultCwd: root, Store: db, Harnesses: map[string]plugin.Harness{"codex": p}})
	must(err)
	git := &gitPeer{Service: gitapp.New()}
	apps, err := applicationhost.New(ctx, applicationhost.Config{Store: db, Applications: []plugin.Application{git}, BackgroundCapabilities: host.BackgroundCapabilities})
	must(err)
	must(apps.Start(ctx, plugin.RuntimeStartContext{}))
	_, err = host.ReadThread(ctx, "public", "open fixture")
	must(err)
	sessions, err := plugin.Require[plugin.BackgroundSessionsCapability](host.BackgroundCapabilities(owner, ""), plugin.BackgroundSessionsCapabilityKey)
	must(err)
	_, err = sessions.Open(ctx, plugin.OpenSessionRequest{SessionKey: "fixture"})
	must(err)
	initialBytes := db.Snapshot().RecordBytes("thread:public")
	settings := writerPragmas()
	pageSize := settings["page_size"]
	drainWAL()
	initialFile, err := os.Stat(path)
	must(err)
	var samples []sample
	takeBlobBytes()
	measure := func(op string, inputBytes int, run func() error) {
		previous := db.Snapshot()
		a := readCounters()
		start := time.Now()
		err := run()
		elapsed := time.Since(start)
		must(err)
		b := readCounters()
		next := db.Snapshot()
		s := sample{Operation: op, InputBytes: inputBytes, Transactions: b.tx - a.tx, BlobBytes: b.blob - a.blob,
			WALFrames: b.frames - a.frames, ProcessBytes: b.process - a.process, Micros: elapsed.Microseconds(),
			DBWriteBytes: b.db - a.db, WALWriteBytes: b.wal - a.wal, CommitMicros: (b.commitNS - a.commitNS) / 1000, Records: map[string]change{}}
		if s.Transactions != int64(next.Revision()-previous.Revision()) {
			panic("commit count differs from published revisions")
		}
		if s.WALWriteBytes < s.WALFrames*int64(pageSize) {
			panic("VFS writes do not account for the observed WAL pages")
		}
		for _, key := range next.ChangedKeys(previous, "") {
			kind, _, _ := strings.Cut(key, ":")
			c := s.Records[kind]
			c.Count++
			c.Bytes += next.RecordBytes(key)
			s.Records[kind] = c
		}
		var accounted int64
		for kind, n := range takeBlobBytes() {
			c := s.Records[kind]
			c.SQLBlobBytes = n
			accounted += n
			s.Records[kind] = c
		}
		if accounted != s.BlobBytes {
			panic("unattributed SQLite BLOB bytes")
		}
		samples = append(samples, s)
	}
	for range 8 {
		measure("idle", 0, func() error {
			time.Sleep(125 * time.Millisecond)
			_, err := host.Thread("public")
			if err != nil {
				return err
			}
			return db.Flush(ctx)
		})
	}
	for i := range 4 {
		at := epoch + int64(i)
		obs := gitapp.Observation{Root: "/fixture", Directories: []string{"/fixture"}, AttemptedAt: at, Snapshot: &gitapp.Snapshot{Root: "/fixture", Changed: i}}
		value := encode(gitapp.SyncInput{AttemptedAt: at, Observations: []gitapp.Observation{obs}})
		syncGit := func() error {
			_, err := git.domain.Execute(ctx, "git.sync", value, plugin.DomainCommandOptions{RequestID: fmt.Sprintf("sync-%d", i)})
			return err
		}
		measure("git", len(value), syncGit)
		measure("git-retry", len(value), syncGit)
		usage := encode(map[string]any{"generationId": i, "inputTokens": 256, "outputTokens": 64})
		measure("telemetry", len(usage), func() error { return p.open["public"].TelemetryLedger.Record(ctx, usage) })
	}
	for _, session := range []string{"public", "private"} {
		o := p.open[session]
		state := initial
		var id string
		const prompt = "Check the saved result."
		measure(session+"-admit", len(prompt), func() error {
			var err error
			id, err = o.ExecutionAdmission.Accept(ctx, func(id string) (json.RawMessage, error) {
				state = codex.StageExecution(state, id, input(prompt), epoch+100, nil)
				return encode(state), nil
			})
			return err
		})
		reader, err := sqlite.Open(path, true)
		must(err)
		rev, err := reader.Query("SELECT revision FROM store_meta")
		must(err)
		must(reader.Close())
		execution := o.ReadThread().Observation.LatestExecution
		if rev[0]["revision"] != int64(db.Snapshot().Revision()) || execution == nil || execution.ExecutionID != id || execution.Status != "running" {
			panic("native admission returned before its running revision was committed")
		}
		var answer strings.Builder
		for i := range packets {
			delta := fmt.Sprintf("%03d %s", i, strings.Repeat("saved text. ", 8))
			answer.WriteString(delta)
			state = codex.ReduceEvent(state, id, codex.Map{"type": "text-delta", "delta": delta, "itemId": "reply", "at": int64(epoch + 101 + i)})
			if codex.LatestTurn(state)["answer"] != answer.String() {
				panic("stream reducer lost an input fragment")
			}
			raw := encode(state)
			measure(session+"-stream", len(delta), func() error { return o.SessionState.Commit(ctx, raw) })
			if !bytes.Equal(o.SessionState.Read(), raw) {
				panic("intermediate committed session differs from the reducer")
			}
		}
		const followUp = "Keep the intermediate answer."
		state = codex.AppendFollowUp(state, id, input(followUp), epoch+200, "follow-up", "")
		measure(session+"-follow-up", len(followUp), func() error { return o.SessionState.Commit(ctx, encode(state)) })
		if !bytes.Contains(o.SessionState.Read(), []byte(followUp)) {
			panic("acknowledged follow-up missing from session history")
		}
		state = codex.ReduceEvent(state, id, codex.Map{"type": "done", "outcome": "completed", "at": int64(epoch + 201)})
		measure(session+"-terminal", 0, func() error { return o.SessionState.Commit(ctx, encode(state)) })
	}
	want := db.Snapshot()
	beforeDrain := readCounters()
	drainWAL()
	afterDrain := readCounters()
	finalFile, err := os.Stat(path)
	must(err)
	must(apps.Stop(ctx))
	must(host.Close(ctx))
	must(db.Close())
	db, err = store.Open(path)
	must(err)
	if got := db.Snapshot(); got.Revision() != want.Revision() || len(got.ChangedKeys(want, "")) != 0 {
		panic("reopened SQLite differs from acknowledged records")
	}
	must(db.Close())
	exe, err := os.Executable()
	must(err)
	binary, err := os.ReadFile(exe)
	must(err)
	must(json.NewEncoder(os.Stdout).Encode(map[string]any{
		"binarySHA256": fmt.Sprintf("%x", sha256.Sum256(binary)), "sqliteSource": sqliteVersion(),
		"go": runtime.Version(), "platform": runtime.GOOS + "/" + runtime.GOARCH,
		"fixtureSHA256": seedSHA, "historyTurns": historyTurns, "initialThreadBytes": initialBytes, "pageBytes": pageSize, "writerPragmas": settings,
		"initialDBBytes": initialFile.Size(), "finalDBBytes": finalFile.Size(),
		"packetsPerSession": packets, "drainProcessBytes": afterDrain.process - beforeDrain.process,
		"drainDBWriteBytes": afterDrain.db - beforeDrain.db, "drainWALWriteBytes": afterDrain.wal - beforeDrain.wal, "samples": samples,
	}))
}
