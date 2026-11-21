//go:build chief_transcript_replay

package pi

import (
	"context"
	"encoding/json"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
)

type replayStore struct{ raw json.RawMessage }

func (s *replayStore) Read() json.RawMessage                               { return s.raw }
func (s *replayStore) Commit(_ context.Context, raw json.RawMessage) error { s.raw = raw; return nil }

// NewTranscriptReplay feeds individual RPC frames through session accumulation,
// model-call completion and the durable Thread reducer.
func NewTranscriptReplay() func(map[string]any) (json.RawMessage, error) {
	id := "run"
	store := &replayStore{}
	h := &threadHandle{ctx: context.Background(), interactions: map[string]pendingInteraction{}, open: plugin.OpenContext{SessionState: store},
		state: State{Version: 1, LatestExecutionID: &id, Executions: []model.PublicExecution{{ExecutionID: id, Status: "running", StartedAt: 1}},
			Messages: []MessageState{{ID: "initial", ExecutionID: id, Role: "user", Presentation: "ordinary", Text: "Initial instruction"}}}}
	decoder, run := eventDecoder{}, nativeRun{}
	return func(frame map[string]any) (json.RawMessage, error) {
		h.mu.Lock()
		defer h.mu.Unlock()
		if text, ok := frame["steer"].(string); ok {
			h.state.Messages = append(h.state.Messages, MessageState{ID: "follow", ExecutionID: id, Role: "user", Presentation: "ordinary", FollowUp: true, CreatedAt: 2, Text: text})
			h.echoes = append(h.echoes, &userEcho{ID: "follow", ExecutionID: id, Text: text})
		} else if frame != nil {
			event, err := decoder.decode(frame)
			if err != nil {
				return nil, err
			}
			if event != nil {
				if err := h.reduceLocked(run.accept(*event)); err != nil {
					return nil, err
				}
			}
		}
		if err := h.commitLocked(); err != nil {
			return nil, err
		}
		return store.Read(), nil
	}
}
