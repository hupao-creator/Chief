package agy

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
)

type content struct {
	Type string `json:"type"`
	Text string `json:"text"`
}
type toolCall struct {
	ID      string `json:"toolCallId"`
	Title   string `json:"title"`
	Status  string `json:"status"`
	Content []struct {
		Type    string  `json:"type"`
		Content content `json:"content"`
		Path    string  `json:"path"`
	} `json:"content"`
	RawInput json.RawMessage `json:"rawInput"`
}

// Text chunks carry a content object. Tool calls use an array under the same
// key, and partial tool_call_update frames can omit the original title.
func (h *handle) event(ctx context.Context, run *execution, execID, sessionID string, f frame) error {
	var envelope struct {
		Session string          `json:"sessionId"`
		Update  json.RawMessage `json:"update"`
		Call    toolCall        `json:"toolCall"`
		Options []struct {
			ID   string `json:"optionId"`
			Name string `json:"name"`
			Kind string `json:"kind"`
			Meta struct {
				Warning struct {
					Title   string `json:"title"`
					Message string `json:"message"`
				} `json:"agy.security.warning"`
			} `json:"_meta"`
		} `json:"options"`
	}
	if f.Method != "session/update" && f.Method != "session/request_permission" {
		if f.ID != nil {
			return run.client.unsupported(f)
		}
		return nil
	}
	if err := json.Unmarshal(f.Params, &envelope); err != nil {
		return err
	}
	if envelope.Session != sessionID {
		if f.ID != nil {
			return run.client.unsupported(f)
		}
		return nil
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	run.lastProgress = time.Now()
	t := h.state.find(execID)
	if f.Method == "session/request_permission" {
		if f.ID == nil {
			return errors.New("Antigravity permission request has no ID")
		}
		// Native question choices share this method but are not tool approvals.
		if run.stopping || strings.HasPrefix(envelope.Call.ID, "interaction_") {
			return run.client.unsupported(f)
		}
		run.sequence++
		id := fmt.Sprintf("agy-%s-%d", execID, run.sequence)
		title := excerpt(envelope.Call.Title)
		if strings.TrimSpace(title) == "" {
			title = "Antigravity tool request"
		}
		p := model.PublicInteraction{ID: id, Kind: "permission", Title: title, Questions: []model.PublicInteractionQuestion{}}
		var args struct {
			Command string `json:"CommandLine"`
			Path    string `json:"TargetFile"`
		}
		_ = json.Unmarshal(envelope.Call.RawInput, &args)
		detail := args.Command
		if detail == "" {
			detail = args.Path
		}
		options := map[string]string{}
		for i, o := range envelope.Options {
			intent := ""
			switch o.Kind {
			case "allow_once", "allow_always":
				intent = "allow"
			case "reject_once", "reject_always":
				intent = "deny"
			default:
				continue
			}
			if o.ID == "" || strings.TrimSpace(o.Name) == "" {
				continue
			}
			warning := strings.TrimSpace(o.Meta.Warning.Message)
			if warning == "" {
				warning = strings.TrimSpace(o.Meta.Warning.Title)
			}
			if warning != "" {
				detail = strings.TrimSpace(detail + "\n" + o.Name + ": " + warning)
			}
			action := fmt.Sprintf("option-%d", i)
			p.Actions = append(p.Actions, model.PublicInteractionAction{ID: action, Intent: intent, Label: excerpt(o.Name)})
			options[action] = o.ID
		}
		if detail != "" {
			if model.UTF16Length(detail) > 20000 || strings.ContainsRune(detail, 0) {
				return run.client.unsupported(f)
			}
			p.Description = &detail
		}
		if len(options) == 0 {
			return run.client.unsupported(f)
		}
		run.requests[id] = permission{f.ID, options}
		t.Interactions = append(t.Interactions, p)
		t.Status = "waiting-for-user"
		return h.commit(ctx)
	}
	var header struct {
		Kind string `json:"sessionUpdate"`
	}
	if err := json.Unmarshal(envelope.Update, &header); err != nil {
		return err
	}
	activity := model.HarnessActivity{ExecutionID: execID}
	switch header.Kind {
	case "agent_message_chunk", "agent_thought_chunk":
		var msg struct {
			Content content `json:"content"`
		}
		if err := json.Unmarshal(envelope.Update, &msg); err != nil {
			return err
		}
		if msg.Content.Type != "text" || msg.Content.Text == "" {
			return nil
		}
		kind := "assistant"
		if header.Kind == "agent_thought_chunk" {
			kind = "reasoning"
		}
		if len(t.Blocks) == 0 || t.Blocks[len(t.Blocks)-1].Kind != kind {
			t.Blocks = append(t.Blocks, block{Kind: kind})
		}
		b := &t.Blocks[len(t.Blocks)-1]
		b.Text += msg.Content.Text
		// Publish the first chunk promptly, coalesce text bursts, and flush the
		// remaining tail at the next tool, permission or terminal commit.
		if kind == "assistant" {
			summary := excerpt(b.Text)
			t.Summary = &summary
		}
		now := time.Now()
		if now.Sub(run.lastTextCommit) < 80*time.Millisecond {
			return nil
		}
		run.lastTextCommit = now
		if kind == "assistant" {
			activity.Kind = "assistant-text"
		} else {
			activity.Kind = "reasoning"
			activity.Text = excerpt(msg.Content.Text)
		}
	case "tool_call", "tool_call_update":
		var call toolCall
		if err := json.Unmarshal(envelope.Update, &call); err != nil {
			return err
		}
		if call.ID == "" {
			return errors.New("Antigravity tool update has no call ID")
		}
		index := slices.IndexFunc(t.Blocks, func(b block) bool { return b.Kind == "tool" && b.CallID == call.ID })
		if index < 0 {
			index = len(t.Blocks)
			t.Blocks = append(t.Blocks, block{Kind: "tool", CallID: call.ID})
		}
		b := &t.Blocks[index]
		if call.Title != "" {
			b.Text = call.Title
		}
		if call.Content != nil {
			var details []string
			for _, part := range call.Content {
				switch part.Type {
				case "content":
					if part.Content.Type == "text" {
						details = append(details, part.Content.Text)
					}
				case "diff":
					details = append(details, part.Path)
				}
			}
			b.Detail = strings.Join(details, "\n")
		}
		if call.Status != "" {
			b.Status = call.Status
		}
		if b.Text != "" && len(call.ID) <= 1024 && !strings.ContainsRune(call.ID, 0) {
			activity.Kind = "tool-call"
			activity.CallID = call.ID
			name := []rune(excerpt(b.Text))
			activity.ToolName = string(name[:min(64, len(name))])
		}
	default:
		return nil
	}
	if activity.Kind != "" && h.open.PublishActivity != nil {
		run.sequence++
		activity.Sequence = run.sequence
		h.open.PublishActivity(activity)
	}
	return h.commit(ctx)
}
func (h *handle) Respond(ctx context.Context, req model.RespondRequest) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	stale := &plugin.InteractionResponseNotSentError{Cause: errors.New("Antigravity permission or option is no longer pending")}
	run := h.active
	if ctx.Err() != nil {
		return &plugin.InteractionResponseNotSentError{Cause: ctx.Err()}
	}
	if run == nil || run.stopping {
		return stale
	}
	p, ok := run.requests[req.InteractionID]
	if !ok {
		return stale
	}
	choice, ok := p.options[req.ActionID]
	if !ok {
		return stale
	}
	t := &h.state.Turns[len(h.state.Turns)-1]
	if req.ExecutionID != "" && req.ExecutionID != t.ExecutionID {
		return stale
	}
	delete(run.requests, req.InteractionID)
	run.lastProgress = time.Now()
	if err := run.client.write(object{"id": p.rpcID, "result": object{"outcome": object{"outcome": "selected", "optionId": choice}}}); err != nil {
		run.cancel(err)
		return err
	}
	t.Interactions = slices.DeleteFunc(t.Interactions, func(i model.PublicInteraction) bool { return i.ID == req.InteractionID })
	if len(t.Interactions) == 0 {
		t.Status = "running"
	}
	if err := h.commit(context.WithoutCancel(ctx)); err != nil {
		run.cancel(err)
		return err
	}
	return nil
}
