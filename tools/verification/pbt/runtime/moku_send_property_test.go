package runtime_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
	core "github.com/hupao-creator/Chief/internal/core/runtime"
	"github.com/hupao-creator/Chief/internal/core/store"
	"github.com/hupao-creator/Chief/internal/services/moku"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

type sendToolPeer struct {
	injectedToolPeer
	ordinary map[string]*handle
}

func (h *sendToolPeer) Open(ctx context.Context, open plugin.OpenContext) (plugin.Handle, error) {
	if open.Injection != nil {
		return h.injectedToolPeer.Open(ctx, open)
	}
	native := &handle{open: open, ctx: ctx}
	h.ordinary[open.ThreadID] = native
	return native, nil
}

// PBT-MOKU-SEND: internal/services/moku/README.md#follow-ups-to-ordinary-threads
func TestMokuSendProperties(t *testing.T) {
	rapidcheck.Check(t, func(t *rapid.T) {
		ctx := context.Background()
		check := func(err error) {
			t.Helper()
			if err != nil {
				t.Fatal(err)
			}
		}
		root, err := os.MkdirTemp("", "chief-moku-send-")
		check(err)
		defer os.RemoveAll(root)
		db, err := store.Open(filepath.Join(root, "state.sqlite"))
		check(err)
		defer db.Close()
		peer := &sendToolPeer{ordinary: map[string]*handle{}}
		harnesses := map[string]plugin.Harness{"fixture": peer}
		r, err := core.New(ctx, core.Config{Store: db, Harnesses: harnesses, DataDir: root, DefaultCwd: root})
		check(err)
		defer r.Close(ctx)

		history, err := r.EnsureMokuThread(ctx, "fixture", nil, root)
		check(err)
		chief, err := r.ReplaceConfiguredMokuThread(ctx, history.ID, core.MokuConfiguration{
			HarnessID: "fixture", Cwd: root, Unapplied: true, PreserveHistory: true,
		})
		check(err)
		running, err := create(r)
		check(err)
		terminal, err := create(r)
		check(err)
		waiting, err := create(r)
		check(err)
		terminalStatus := rapid.SampledFrom([]string{"completed", "failed", "interrupted"}).Draw(t, "terminal-status")
		for _, fixture := range []struct{ id, status string }{{terminal.Record.ID, terminalStatus}, {waiting.Record.ID, "waiting-for-user"}} {
			native := peer.ordinary[fixture.id].open.SessionState
			var saved state
			check(json.Unmarshal(native.Read(), &saved))
			execution := saved.Observation.LatestExecution
			execution.Status = fixture.status
			if execution.Terminal() {
				execution.FinishedAt = &execution.StartedAt
			} else {
				execution.Interactions = []model.PublicInteraction{{
					ID: "permission", Kind: "permission", Title: "Allow fixture action?",
					Actions:   []model.PublicInteractionAction{{ID: "allow", Intent: "allow", Label: "Allow"}},
					Questions: []model.PublicInteractionQuestion{},
				}}
			}
			check(native.Commit(ctx, raw(saved)))
		}
		coordinator, tool := openChiefTool(t, ctx, r, root, harnesses, &peer.injectedToolPeer,
			model.AgentInput{Parts: []model.AgentInputPart{{Kind: "text", Text: "Chief fixture"}}}, "send_to_thread")
		defer coordinator.Stop(ctx)

		call := func(args map[string]any) (json.RawMessage, error) {
			return tool.Execute(ctx, plugin.ToolCall{Arguments: raw(args)})
		}
		runningID, terminalID, waitingID := running.Record.ID, terminal.Record.ID, waiting.Record.ID
		prompt := "检查导航 " + rapid.StringMatching("[a-z]{1,16}").Draw(t, "prompt")
		ids := rapid.Permutation([]string{runningID, terminalID, waitingID, "missing-thread", chief.ID, history.ID}).Draw(t, "target-order")
		targets := []string{}
		wantAdmitted := []string{}
		for index, id := range ids {
			targets = append(targets, id)
			targets = append(targets, rapid.SliceOfN(rapid.SampledFrom(ids[:index+1]), 0, 3).Draw(t, "repeats")...)
			if id == runningID || id == terminalID {
				wantAdmitted = append(wantAdmitted, id)
			}
		}
		type outcome struct {
			ThreadID            string `json:"threadId"`
			OK                  bool   `json:"ok"`
			ExecutionID         string `json:"executionId"`
			StartedNewExecution *bool  `json:"startedNewExecution"`
			Hint                string `json:"hint"`
			Error               string `json:"error"`
		}
		result, err := call(map[string]any{"target": targets, "prompt": "  " + prompt + "\n"})
		check(err)
		var batch struct {
			OK      *bool     `json:"ok"`
			Results []outcome `json:"results"`
		}
		check(json.Unmarshal(result, &batch))
		if batch.OK == nil || *batch.OK || len(batch.Results) != len(ids) {
			t.Fatal("partial batch lost its status or distinct results")
		}
		for index, got := range batch.Results {
			id := ids[index]
			if got.ThreadID != id {
				t.Fatal("results reordered distinct targets")
			}
			switch id {
			case runningID, terminalID:
				after, err := r.Thread(id)
				check(err)
				current := after.Observation.LatestExecution
				if !got.OK || got.Error != "" || got.StartedNewExecution == nil || *got.StartedNewExecution != (id == terminalID) ||
					got.ExecutionID != current.ExecutionID || got.Hint != moku.ThreadNotificationHint || current.Status != "running" {
					t.Fatal("acknowledgement disagrees with durable execution")
				}
				if id == runningID && got.ExecutionID != running.Execution.ExecutionID ||
					id == terminalID && got.ExecutionID == terminal.Execution.ExecutionID {
					t.Fatal("follow-up used the wrong execution")
				}
			default:
				if got.OK || got.Error == "" || got.ExecutionID != "" || got.StartedNewExecution != nil || got.Hint != "" {
					t.Fatal("failed target lost its error or claimed admission")
				}
			}
		}
		record, err := r.Thread(chief.ID)
		check(err)
		var saved struct {
			Name    string          `json:"name"`
			IsError bool            `json:"isError"`
			Result  json.RawMessage `json:"result"`
		}
		check(json.Unmarshal(record.Transcript[len(record.Transcript)-1], &saved))
		if saved.Name != "send_to_thread" || saved.IsError || !bytes.Equal(saved.Result, result) {
			t.Fatal("Chief transcript lost the partial batch acknowledgement")
		}

		singleBatch, err := call(map[string]any{"target": []string{runningID, runningID}, "prompt": "batch " + prompt})
		check(err)
		check(json.Unmarshal(singleBatch, &batch))
		if batch.OK == nil || !*batch.OK || len(batch.Results) != 1 || !batch.Results[0].OK ||
			batch.Results[0].ExecutionID != running.Execution.ExecutionID {
			t.Fatal("all-success batch lost its single distinct acknowledgement")
		}
		legacy, err := call(map[string]any{"threadId": runningID, "prompt": "legacy " + prompt})
		check(err)
		if !bytes.Equal(legacy, raw(map[string]any{"ok": true, "threadId": runningID,
			"executionId": running.Execution.ExecutionID, "startedNewExecution": false, "hint": moku.ThreadNotificationHint})) {
			t.Fatal("legacy success lost its original flat response")
		}
		if _, err := call(map[string]any{"threadId": waitingID, "prompt": prompt}); err == nil || !strings.Contains(err.Error(), "pending interaction") {
			t.Fatal("legacy send failure did not return a tool error")
		}

		for _, malformed := range []map[string]any{
			{"prompt": prompt},
			{"threadId": runningID, "target": targets, "prompt": prompt},
			{"target": []string{}, "prompt": prompt},
			{"target": nil, "prompt": prompt},
			{"target": slices.Repeat([]string{runningID}, 101), "prompt": prompt},
			{"target": runningID, "prompt": prompt},
			{"target": []any{runningID, 17}, "prompt": prompt},
			{"target": []string{runningID, strings.Repeat("𐀀", 65)}, "prompt": prompt},
			{"target": []string{runningID, "bad\x00id"}, "prompt": prompt},
			{"target": targets},
			{"target": targets, "prompt": " \t\n"},
			{"target": targets, "prompt": "bad\x00prompt"},
			{"target": targets, "prompt": prompt, "extra": true},
		} {
			_, err := call(malformed)
			var caller *plugin.ToolCallError
			if !errors.As(err, &caller) {
				t.Fatal("malformed send did not return a caller error")
			}
		}

		// Compare ordered durable admissions independently of the tool output.
		events, err := db.Snapshot().Events()
		check(err)
		type admission struct{ id, prompt string }
		wantEvents := []admission{{runningID, "hello"}, {terminalID, "hello"}, {waitingID, "hello"}}
		for _, id := range wantAdmitted {
			wantEvents = append(wantEvents, admission{id, prompt})
		}
		wantEvents = append(wantEvents, admission{runningID, "batch " + prompt}, admission{runningID, "legacy " + prompt})
		var admitted []admission
		for _, event := range events {
			if event.Type != "thread.input-accepted" {
				continue
			}
			var input model.AgentInput
			check(json.Unmarshal(event.Data, &input))
			if event.Source != "application" || len(input.Parts) != 1 || input.Parts[0].Kind != "text" {
				t.Fatal("tool send changed Runtime admission provenance or input")
			}
			admitted = append(admitted, admission{event.Subject.ID, input.Parts[0].Text})
		}
		if !slices.Equal(admitted, wantEvents) {
			t.Fatal("durable admissions differ from ordered successful sends")
		}
	})
}
