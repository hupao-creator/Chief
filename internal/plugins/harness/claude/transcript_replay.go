//go:build chief_transcript_replay

package claude

import (
	"encoding/json"
	"time"

	"github.com/hupao-creator/Chief/internal/core/model"
)

// NewTranscriptReplay drives the same stream-json parser and turn settlement
// used by a Handle, with a synthetic admitted execution.
func NewTranscriptReplay() func(map[string]any) (json.RawMessage, error) {
	state, parser := NewState(), newParser()
	input := func(text string) model.AgentInput {
		return model.AgentInput{Parts: []model.AgentInputPart{{Kind: "text", Text: text}}}
	}
	turn := state.NewTurn("run", input("Initial instruction"), Settings{})
	return func(frame map[string]any) (json.RawMessage, error) {
		if text, ok := frame["steer"].(string); ok {
			turn.addPrompt(input(text), "steer:fixture")
		} else if frame != nil {
			parser.apply(state, turn, frame, nil)
			if frame["type"] == "result" {
				outcome := "completed"
				if claudeResultFailed(frame) {
					outcome = "failed"
					turn.fail(str(frame["result"]))
				}
				turn.settle(outcome, time.Now().UnixMilli(), state.background())
			}
		}
		return state.Encode()
	}
}
