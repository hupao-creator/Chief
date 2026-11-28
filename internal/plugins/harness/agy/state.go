package agy

import (
	"encoding/json"
	"errors"
	"strings"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
)

// Antigravity task titles come from the submitted input. No independent
// metadata-generation job is pending when the Runtime saves this record.
type metadata struct {
	Title string `json:"title"`
}

func (metadata) Initialize(_ string, input model.AgentInput, _ json.RawMessage) (json.RawMessage, error) {
	return json.Marshal(metadata{Title: plugin.PlaceholderThreadTitle(input)})
}

func (metadata) Project(raw json.RawMessage) (string, error) {
	var value metadata
	err := model.Unmarshal(raw, &value)
	return value.Title, err
}

func (metadata) Fork(json.RawMessage, string) (json.RawMessage, error) {
	return nil, errors.New("Antigravity does not support thread forks")
}

type block struct {
	Detail string `json:"detail,omitempty"`
	Kind   string `json:"kind"`
	Text   string `json:"text,omitempty"`
	CallID string `json:"callId,omitempty"`
	Status string `json:"status,omitempty"`
}
type turn struct {
	model.PublicExecution
	Model     string  `json:"model,omitempty"`
	UserRowID string  `json:"userRowId,omitempty"`
	Prompt    string  `json:"prompt"`
	Blocks    []block `json:"blocks,omitempty"`
}
type state struct {
	Version int    `json:"version"`
	Session string `json:"sessionId,omitempty"`
	Turns   []turn `json:"turns"`
}

func decodeState(raw json.RawMessage) (state, error) {
	s := state{Version: 1, Turns: []turn{}}
	if !model.IsNull(raw) {
		if err := model.Unmarshal(raw, &s); err != nil {
			return s, err
		}
	}
	if s.Version != 1 || s.Turns == nil {
		return s, errors.New("invalid Antigravity session state")
	}
	return s, nil
}
func (s *state) find(id string) *turn {
	for i := range s.Turns {
		if s.Turns[i].ExecutionID == id {
			return &s.Turns[i]
		}
	}
	return nil
}
func (t *turn) finish(status string, at int64) {
	t.Status = status
	t.Interactions = nil
	at = max(t.StartedAt, at)
	t.FinishedAt = &at
}
func excerpt(s string) string {
	// The compact projection and public summary have a fixed display budget.
	var out strings.Builder
	for _, r := range s {
		if out.Len() >= 600 {
			break
		}
		if r != 0 {
			out.WriteRune(r)
		}
	}
	return out.String()
}

type projection struct{}

func (projection) Project(raw json.RawMessage) (model.PublicObservation, error) {
	s, err := decodeState(raw)
	var o model.PublicObservation
	if len(s.Turns) > 0 {
		o.LatestExecution = &s.Turns[len(s.Turns)-1].PublicExecution
	}
	return o, err
}
func (projection) ResolveExecution(raw json.RawMessage, id string) (*model.PublicExecution, error) {
	s, err := decodeState(raw)
	if err != nil {
		return nil, err
	}
	if t := s.find(id); t != nil {
		return &t.PublicExecution, nil
	}
	return nil, nil
}
func (projection) Settle(req plugin.SettleRequest) (json.RawMessage, error) {
	s, err := decodeState(req.SessionState)
	if err != nil {
		return nil, err
	}
	if t := s.find(req.ExecutionID); t != nil && !t.Terminal() {
		t.finish(req.Outcome, req.FinishedAt)
	}
	return json.Marshal(s)
}
func (projection) ReadContext(raw json.RawMessage) (json.RawMessage, error) {
	s, err := decodeState(raw)
	if err != nil {
		return nil, err
	}
	return json.Marshal(s.Turns)
}
func (projection) ProjectRenderer(raw json.RawMessage, scope model.RendererScope) (json.RawMessage, error) {
	s, err := decodeState(raw)
	if err != nil {
		return nil, err
	}
	switch scope.Kind {
	case "overview":
		if n := len(s.Turns); n > 0 {
			s.Turns = s.Turns[n-1:]
		}
		fallthrough
	case "thread":
		for i := range s.Turns {
			s.Turns[i].Prompt = excerpt(s.Turns[i].Prompt)
			s.Turns[i].Blocks = nil
		}
	case "turn", "execution":
		if t := s.find(scope.Key); t != nil {
			s.Turns = []turn{*t}
		} else {
			s.Turns = []turn{}
		}
	default:
		return nil, errors.New("unknown Antigravity content scope")
	}
	s.Session = ""
	return json.Marshal(s)
}
