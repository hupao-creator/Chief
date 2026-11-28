package opencode

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"slices"
	"testing"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

type reviewSessionStore struct{ state json.RawMessage }

func (s *reviewSessionStore) Read() json.RawMessage { return slices.Clone(s.state) }
func (s *reviewSessionStore) Commit(_ context.Context, raw json.RawMessage) error {
	s.state = slices.Clone(raw)
	return nil
}

func TestPermissionReviewProperties(t *testing.T) {
	rapidcheck.Check(t, func(rt *rapid.T) {
		mode := rapid.SampledFrom([]string{"auto", "", "default"}).Draw(rt, "mode")
		outcome := rapid.SampledFrom([]string{"routine", "ask", "error", "length", "invalid", "manual deny", "stopped", "changed mode"}).Draw(rt, "review")
		session := rapid.SampledFrom([]string{"root", "child"}).Draw(rt, "session")
		repeats := rapid.IntRange(1, 4).Draw(rt, "deliveries")
		state, err := DecodeState(nil)
		if err != nil {
			rt.Fatal(err)
		}
		state.NativeSessionID = "root"
		if err := state.Begin("execution", 1); err != nil {
			rt.Fatal(err)
		}
		ctx := t.Context()
		var replies []string
		runtime := &Runtime{ctx: ctx, URL: "http://native", bridge: &Bridge{current: map[string]*registration{session: {}}}, client: &http.Client{Transport: quotaTransport(func(r *http.Request) (*http.Response, error) {
			var body struct{ Decision string }
			if r.Method != "POST" || r.URL.Path != sessionPath(session, "/permission/per_test/reply") {
				return nil, fmt.Errorf("unexpected request %v", r.URL)
			}
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
				return nil, err
			}
			replies = append(replies, body.Decision)
			return &http.Response{StatusCode: 204, Body: http.NoBody}, nil
		})}}
		gate := make(chan struct{})
		reviews := 0
		thread := &Thread{state: state, native: runtime, life: ctx, observed: map[string]bool{session: true}, open: plugin.OpenContext{SessionState: &reviewSessionStore{}, ReadThread: func() model.SessionRecord {
			raw, _ := json.Marshal(Settings{Provider: "local", Model: "model", PermissionMode: mode})
			return model.SessionRecord{Cwd: "/project", Settings: raw}
		}}, reviewer: func(ctx context.Context, request plugin.PromptRequest) (plugin.PromptResult, error) {
			<-gate
			reviews++
			result := plugin.PromptResult{FinishReason: "stop", Output: plugin.PromptOutput{Type: "json", Value: json.RawMessage(`{"decision":"routine"}`)}}
			switch outcome {
			case "ask":
				result.Output.Value = json.RawMessage(`{"decision":"ask"}`)
			case "error":
				return result, errors.New("review unavailable")
			case "length":
				result.FinishReason = "length"
			case "invalid":
				result.Output.Value = json.RawMessage(`{}`)
			}
			return result, nil
		}}
		event := Event{Type: "permission.asked", Data: Object{"id": "per_test", "sessionID": session, "action": "read", "resources": []string{"README.md"}}}
		evidence := rapid.SampledFrom([]string{"direct", "bound tool", "unbound tool", "partial tool", "empty resources"}).Draw(rt, "evidence")
		switch evidence {
		case "bound tool", "unbound tool", "partial tool":
			event.Data["source"] = Object{"type": "tool", "id": "call", "messageID": "message"}
			if evidence != "unbound tool" {
				var input any = Object{"file": "README.md"}
				if evidence == "partial tool" {
					input = `{"file":`
				}
				state.Messages = append(state.Messages, &Message{ID: "tool", Role: "tool", NativeSessionID: session, NativeMessageID: "message", ToolCallID: "call", ToolName: "read", Arguments: input})
			}
		case "empty resources":
			event.Data["resources"] = []string{}
		}
		shouldReview := mode != "default" && (evidence == "direct" || evidence == "bound tool")
		for range repeats {
			if err := thread.acceptEvent(ctx, event, false, runtime); err != nil {
				rt.Fatal(err)
			}
		}
		var expected []string
		switch outcome {
		case "manual deny":
			if err := thread.Respond(ctx, model.RespondRequest{InteractionID: interactionID(state.Interactions[0]), ActionID: "deny"}); err != nil {
				rt.Fatal(err)
			}
			expected = []string{"reject"}
		case "stopped":
			thread.mu.Lock()
			thread.stopping = true
			thread.mu.Unlock()
		case "changed mode":
			thread.mu.Lock()
			mode = "default"
			thread.mu.Unlock()
		case "routine":
			if shouldReview {
				expected = []string{"once"}
			}
		}
		close(gate)
		thread.async.Wait()
		if !slices.Equal(replies, expected) || (!shouldReview && reviews != 0) || (shouldReview && reviews != 1) {
			rt.Fatalf("reviews=%d replies=%v, expected replies=%v", reviews, replies, expected)
		}
		if len(expected) == 0 && state.Interactions[0].Status != "pending" {
			rt.Fatal("held request unavailable")
		}
	})
}
