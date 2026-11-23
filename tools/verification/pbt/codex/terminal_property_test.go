package codex_test

import (
	"fmt"
	"reflect"
	"strings"
	"testing"

	"github.com/hupao-creator/Chief/internal/plugins/harness/codex"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

// PBT-CODEX-TERMINAL: internal/plugins/harness/codex/README.md
func TestCodexTerminalProperties(t *testing.T) {
	rapidcheck.Check(t, func(t *rapid.T) {
		state := codex.EmptyState(1)
		terminals := map[string]codex.Map{}
		ids := []string{}
		at := int64(2)
		message := rapid.StringOfN(rapid.SampledFrom([]rune{'a', '中', '🙂', '\n'}), 0, 32, 128)
		t.Repeat(map[string]func(*rapid.T){
			"start": func(t *rapid.T) {
				last := codex.LatestTurn(state)
				if last != nil && (last["status"] == "running" || last["status"] == "waiting-input") {
					t.Skip("current execution is active")
				}
				if len(ids) >= 100 {
					t.Skip("bounded retained history")
				}
				id := fmt.Sprintf("execution-%d", len(ids))
				var err error
				state, err = codex.StageExecutionChecked(state, id, codex.Map{"parts": []any{codex.Map{"kind": "text", "text": message.Draw(t, "input")}}}, at, nil)
				if err != nil {
					t.Fatal(err)
				}
				ids = append(ids, id)
				at++
			},
			"event": func(t *rapid.T) {
				if len(ids) == 0 {
					t.Skip("no execution")
				}
				id := rapid.SampledFrom(ids).Draw(t, "execution")
				kind := rapid.SampledFrom([]string{"text-delta", "text-final", "status", "done", "error"}).Draw(t, "event")
				event := codex.Map{"type": kind, "at": at, "itemId": "answer", "delta": message.Draw(t, "delta"), "text": message.Draw(t, "text"), "label": "working", "message": "native error", "outcome": rapid.SampledFrom([]string{"completed", "failed", "interrupted"}).Draw(t, "outcome")}
				state = codex.ReduceEvent(state, id, event)
				at++
			},
			"command-completion": func(t *rapid.T) {
				turn := codex.LatestTurn(state)
				if turn == nil || turn["status"] != "running" {
					t.Skip("no running execution")
				}
				parts := rapid.SliceOfN(message, 2, 5).Draw(t, "output parts")
				exitCode := rapid.IntRange(0, 1).Draw(t, "exit code")
				event := codex.CompletedActivity(codex.Map{
					"type": "commandExecution", "id": fmt.Sprintf("command-%d", at), "command": "fixture",
					"aggregatedOutput": strings.Join(parts, "\x00"), "exitCode": exitCode,
				})
				event["at"] = at
				state = codex.ReduceEvent(state, turn["executionId"].(string), event)
				at++
				activities := codex.LatestTurn(state)["activities"].([]any)
				activity := activities[len(activities)-1].(codex.Map)
				wantStatus := "completed"
				if exitCode != 0 {
					wantStatus = "failed"
				}
				if activity["id"] != event["activityId"] || activity["status"] != wantStatus || activity["detail"] != strings.Join(parts, "␀") {
					t.Fatal("command completion lost its identity, exit status or printable output")
				}
			},
			"follow-up": func(t *rapid.T) {
				if len(ids) == 0 {
					t.Skip("no execution")
				}
				id := rapid.SampledFrom(ids).Draw(t, "execution")
				state = codex.AppendFollowUp(state, id, codex.Map{"parts": []any{codex.Map{"kind": "text", "text": message.Draw(t, "follow-up")}}}, at, fmt.Sprintf("input-%d", at), fmt.Sprintf("steer:command-%d", at))
				at++
			},
			"rejection": func(t *rapid.T) {
				if len(ids) == 0 {
					t.Skip("no execution")
				}
				id := rapid.SampledFrom(ids).Draw(t, "execution")
				noticeCount := func() int {
					for _, value := range state["turns"].([]any) {
						turn := value.(codex.Map)
						if turn["executionId"] == id {
							return len(turn["notices"].([]any))
						}
					}
					return 0
				}
				before := noticeCount()
				state = codex.RejectFollowUp(state, id, message.Draw(t, "rejection"), at, fmt.Sprintf("notice-%d", at))
				at++
				if noticeCount() != before+1 {
					t.Fatal("rejected follow-up lost its audit notice")
				}
			},
			"settle": func(t *rapid.T) {
				if len(ids) == 0 {
					t.Skip("no execution")
				}
				id := rapid.SampledFrom(ids).Draw(t, "execution")
				state = codex.SettleExecution(state, id, rapid.SampledFrom([]string{"completed", "failed", "interrupted"}).Draw(t, "outcome"), at, "")
				at++
			},
			"": func(t *rapid.T) {
				if _, err := codex.DecodeState(state); err != nil {
					t.Fatalf("generated event order produced invalid durable state: %v", err)
				}
				for _, id := range ids {
					execution := codex.ResolveExecution(state, id)
					if canonical := terminals[id]; canonical != nil {
						if !reflect.DeepEqual(canonical, execution) {
							t.Logf("terminal %s: before=%v after=%v", id, canonical, execution)
							t.Fatal("terminal execution changed")
						}
					} else if execution["status"] == "completed" || execution["status"] == "failed" || execution["status"] == "interrupted" {
						terminals[id] = execution
					}
				}
			},
		})
	})
}
