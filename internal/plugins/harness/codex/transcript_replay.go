//go:build chief_transcript_replay

package codex

import "encoding/json"

// NewTranscriptReplay feeds app-server notifications into the production reducer
// without starting a CLI. It is linked only by the offline reader replay.
func NewTranscriptReplay() func(Map) (json.RawMessage, error) {
	const execution = "run"
	input := func(text string) Map { return Map{"parts": []any{Map{"kind": "text", "text": text}}} }
	state := StageExecution(EmptyState(1), execution, input("Initial instruction"), 2, nil)
	session := &NativeSession{id: "primary", executionID: execution, seenUsage: map[string]bool{},
		pending: map[string]*nativePending{}, finals: map[string]string{}, reasoning: map[nativeReasoningPart]string{}, outputs: map[string]string{},
		emit: func(e Map) { state = ReduceEvent(state, execution, e) }}
	session.confirmTurnStart(execution)
	return func(frame Map) (json.RawMessage, error) {
		if text, ok := frame["steer"].(string); ok {
			state = AppendFollowUp(state, execution, input(text), now(), "follow", "steer:fixture")
		} else if frame != nil {
			params := obj(frame["params"])
			params["threadId"], params["turnId"] = "primary", execution
			if id := frame["id"]; id != nil {
				session.request(str(frame["method"]), params, id)
			} else {
				session.notification(str(frame["method"]), params, nil)
			}
		}
		return json.Marshal(state)
	}
}
