package runtime_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
	core "github.com/hupao-creator/Chief/internal/core/runtime"
	"github.com/hupao-creator/Chief/internal/core/store"
	"github.com/hupao-creator/Chief/internal/platform/transport"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

// PBT-MOKU-CONVERSATION: internal/core/runtime/README.md#chief-conversation
func TestMokuConversationProperties(t *testing.T) {
	rapidcheck.Check(t, func(t *rapid.T) {
		ctx := context.Background()
		check := func(err error) {
			t.Helper()
			if err != nil {
				t.Fatal(err)
			}
		}
		dir, err := os.MkdirTemp("", "chief-dialogue-")
		check(err)
		defer os.RemoveAll(dir)
		peer := &injectedToolPeer{}
		harnesses := map[string]plugin.Harness{"fixture": peer}
		open := func(profile string) (*core.Runtime, func()) {
			db, err := store.Open(filepath.Join(dir, profile, "state.sqlite"))
			check(err)
			r, err := core.New(ctx, core.Config{Store: db, Harnesses: harnesses, DataDir: dir, DefaultCwd: dir})
			check(err)
			return r, func() { check(r.Close(ctx)); check(db.Close()) }
		}
		r, closeRuntime := open("first")
		defer func() { closeRuntime() }()
		old, err := r.EnsureMokuThread(ctx, "fixture", nil, dir)
		check(err)
		// Historical wire shapes, including equal times, repeated words and a
		// user who attaches a file without typing. Only dialogue belongs here.
		type visible struct {
			Role, Text  string
			Attachments []string
		}
		var want []visible
		var history []json.RawMessage
		count := rapid.IntRange(1, 90).Draw(t, "old-messages")
		for i := 0; i < count; i++ {
			row := map[string]any{"id": fmt.Sprint(i), "createdAt": i/3 + 1}
			entry := visible{}
			if rapid.Bool().Draw(t, "historical-talk") {
				entry.Role, entry.Text = "chief", "留意第二节"
				row["type"], row["name"], row["executionId"] = "tool-operation", "talk", "previous-run"
				row["completedAt"], row["result"] = i/3+1, map[string]bool{"ok": true}
				row["arguments"] = map[string]string{"text": entry.Text}
			} else {
				entry.Role = "user"
				entry.Text = rapid.SampledFrom([]string{"same words", "看一下\n这个", "", strings.Repeat("界", 642)}).Draw(t, "text")
				row["type"], row["role"], row["status"], row["content"] = "message", "user", "complete", entry.Text
				if entry.Text == "" {
					row["attachments"] = []any{map[string]any{"name": "brief.pdf", "path": "PRIVATE-PATH"}}
					entry.Attachments = []string{"brief.pdf"}
				}
			}
			history = append(history, raw(row))
			want = append(want, entry)
		}
		check(r.UpdateThread(ctx, old.ID, func(record *model.ThreadRecord) error {
			record.Transcript = append(record.Transcript, history...)
			for _, extra := range []map[string]any{
				{"type": "message", "role": "assistant", "content": "PRIVATE-REASONING"},
				{"type": "message", "role": "user", "systemEvent": true, "content": "PRIVATE-EVENT"},
				{"type": "message", "role": "user", "presentation": "internal", "content": "PRIVATE-DELIVERY"},
				{"type": "message", "role": "user", "presentation": "unknown", "content": "PRIVATE-UNKNOWN"},
				{"type": "tool-operation", "name": "talk", "arguments": map[string]string{"text": "PRIVATE-PENDING"}},
				{"type": "tool-operation", "name": "create_thread", "arguments": map[string]string{"text": "PRIVATE-TOOL"}},
			} {
				extra["createdAt"], extra["id"], extra["status"] = count+1, fmt.Sprint(len(record.Transcript)), "complete"
				record.Transcript = append(record.Transcript, raw(extra))
			}
			return nil
		}))
		chief, err := r.ReplaceConfiguredMokuThread(ctx, old.ID, core.MokuConfiguration{HarnessID: "fixture", Cwd: dir, Unapplied: true, PreserveHistory: true})
		check(err)
		reminderText := "PRIVATE-REMINDER-" + rapid.StringMatching("[a-z]{1,12}").Draw(t, "historical-reminder-text")
		reminder := raw(map[string]any{"type": "tool-operation", "id": "retired-timer", "name": "timer",
			"executionId": "previous-run", "createdAt": 1, "completedAt": 2, "result": map[string]bool{"ok": true},
			"arguments": map[string]string{"text": reminderText}})
		check(r.UpdateThread(ctx, chief.ID, func(record *model.ThreadRecord) error {
			record.Transcript = append(record.Transcript, reminder)
			return nil
		}))
		archive, err := r.Thread(old.ID)
		check(err)
		scope := transport.ContentScope{Kind: "moku-conversation"}
		if _, err := r.ReadThreadContent(ctx, archive.ID, scope, &archive.Revision); err == nil {
			t.Fatal("archived owner accepted a live conversation subscription")
		}
		prompt := "Check the draft " + rapid.StringMatching("[a-z]{1,12}").Draw(t, "request")
		input := model.AgentInput{Parts: []model.AgentInputPart{{Kind: "text", Text: prompt}}}
		commandID := "1788000000000_" + rapid.StringMatching("[a-zA-Z0-9_-]{16,80}").Draw(t, "command-id")
		coordinator, talk := openChiefTool(t, model.WithFollowUpCommand(ctx, commandID), r, dir, harnesses, peer, input, "talk")
		for _, binding := range peer.tools.Bindings {
			if binding.Name == "timer" {
				t.Fatal("retired reminder tool is still registered")
			}
		}
		want = append(want, visible{Role: "user", Text: prompt})
		for i := 0; i < 2; i++ {
			_, err := talk.Execute(ctx, plugin.ToolCall{CallID: fmt.Sprint(i), Arguments: raw(map[string]string{"text": "Same reply."})})
			check(err)
			want = append(want, visible{Role: "chief", Text: "Same reply."})
		}
		_, err = talk.Execute(ctx, plugin.ToolCall{Arguments: raw(map[string]string{"text": strings.Repeat("PRIVATE-REJECTED", 32)})})
		if err == nil {
			t.Fatal("invalid Talk unexpectedly succeeded")
		}
		check(coordinator.Stop(ctx))

		verify := func(r *core.Runtime, id string, expected []visible) {
			t.Helper()
			scope := transport.ContentScope{Kind: "moku-conversation"}
			seen := map[string]bool{}
			end := len(expected)
			for {
				result, err := r.ReadThreadContent(ctx, id, scope, nil)
				check(err)
				var page struct {
					CommandRowIDs bool `json:"commandRowIds"`
					Messages      []struct {
						visible
						ID        string
						CreatedAt int64
					}
					Before string
				}
				check(json.Unmarshal(result.Value, &page))
				if !page.CommandRowIDs || strings.Contains(string(result.Value), "PRIVATE-") || len(page.Messages) > end {
					t.Fatal("conversation exposed unrelated content")
				}
				start := end - len(page.Messages)
				for i, m := range page.Messages {
					want := expected[start+i]
					if start+i == count && m.ID != chief.ID+"/steer:"+commandID {
						t.Fatalf("admitted user message lost its command identity: %s", m.ID)
					}
					if seen[m.ID] || m.ID == "" || m.CreatedAt <= 0 || m.Text != want.Text || m.Role != want.Role || !slices.Equal(m.Attachments, want.Attachments) {
						t.Fatalf("conversation differs at %d: %+v, want %+v", start+i, m, want)
					}
					seen[m.ID] = true
				}
				if page.Before == "" {
					if start != 0 {
						t.Fatal("missing earlier messages")
					}
					break
				}
				if start == end {
					t.Fatal("empty page did not advance")
				}
				scope.Key, end = page.Before, start
			}
		}
		verify(r, chief.ID, want)
		snapshot, err := r.Snapshot()
		check(err)
		owner := slices.IndexFunc(snapshot.Threads, func(record model.ThreadRecord) bool { return record.ID == chief.ID })
		if owner < 0 || len(snapshot.Threads[owner].Transcript) == 0 {
			t.Fatal("catalog lost the current Chief audit preview")
		}
		for _, row := range snapshot.Threads[owner].Transcript {
			if bytes.Contains(row, []byte(`"id":"retired-timer"`)) {
				t.Fatal("catalog replayed the reminder from another execution")
			}
		}
		closeRuntime()
		r, closeRuntime = open("first")
		verify(r, chief.ID, want)
		restored, err := r.Thread(chief.ID)
		check(err)
		if !slices.ContainsFunc(restored.Transcript, func(row json.RawMessage) bool { return bytes.Equal(row, reminder) }) {
			t.Fatal("SQLite reopen lost the historical reminder audit row")
		}
		other, closeOther := open("other")
		defer closeOther()
		fresh, err := other.EnsureMokuThread(ctx, "fixture", nil, dir)
		check(err)
		verify(other, fresh.ID, nil)
		reset, err := r.ReplaceConfiguredMokuThread(ctx, chief.ID, core.MokuConfiguration{HarnessID: "fixture", Cwd: dir, Unapplied: true})
		check(err)
		verify(r, reset.ID, nil)
	})
}
