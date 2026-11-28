package moku

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
	"github.com/hupao-creator/Chief/internal/platform/diagnostics"
)

// A call owns media and the right to submit to one Chief. Only destination
// admission can bind an execution to a handoff. All fields use Coordinator.mu.
type voiceCall struct {
	id, owner string
	ctx       context.Context
	cancel    context.CancelCauseFunc
	failures  chan plugin.VoiceFailure
	binding   *voiceBinding
}
type voiceBinding struct {
	call               *voiceCall
	handoff, execution string
	ctx                context.Context
	cancel             context.CancelFunc
	failureReported    bool
}

// RunGlobalVoice joins the call on disconnect, including in-flight admission.
// Runtime owns any execution already accepted by the selected Harness.
func (c *Coordinator) RunGlobalVoice(ctx context.Context, offer string, answer func(string) error) (returned error) {
	ctx = diagnostics.EnsureTrace(ctx)
	diagnostics.Event(ctx, "moku.voice", "binding_destination")
	defer func() { diagnostics.End(ctx, "moku.voice", returned) }()
	ctx, finish, err := c.begin(ctx)
	if err != nil {
		return err
	}
	defer finish()
	if c.config.RunVoice == nil {
		return errors.New("Codex Voice Mode is unavailable")
	}
	ctx, cancel := context.WithCancelCause(ctx)
	call := &voiceCall{id: newID(), ctx: ctx, cancel: cancel, failures: make(chan plugin.VoiceFailure, 1)}
	c.mu.Lock()
	if c.voice != nil {
		c.mu.Unlock()
		cancel(nil)
		return errors.New("another global Voice Mode call is open")
	}
	c.voice = call
	c.mu.Unlock()
	defer func() {
		cancel(nil)
		c.mu.Lock()
		c.voice = nil
		c.mu.Unlock()
	}()
	var executable string
	if err = c.queue.Lock(ctx); err != nil {
		return err
	}
	err = c.admitSettings(ctx, func(ctx context.Context) error {
		record, err := c.ensure(ctx)
		if err != nil {
			return err
		}
		settings, _, err := c.config.Settings()
		if err != nil {
			return err
		}
		var launch struct{ ExecutablePath string }
		if raw := settings.Harnesses["codex"]; len(raw) > 0 {
			if err := json.Unmarshal(raw, &launch); err != nil {
				return err
			}
		}
		executable = launch.ExecutablePath
		c.mu.Lock()
		call.owner = record.ID
		c.mu.Unlock()
		return nil
	})
	c.queue.Unlock()
	if err != nil {
		return err
	}
	err = c.config.RunVoice(ctx, executable, plugin.GlobalVoice{ID: call.id, Offer: offer, Answer: answer, Failures: call.failures,
		Submit: func(ctx context.Context, id, text string) error {
			if err := context.Cause(call.ctx); err != nil {
				return err
			}
			bindingCtx, retire := context.WithCancel(call.ctx)
			binding := &voiceBinding{call: call, handoff: id, ctx: bindingCtx, cancel: retire}
			err := c.submit(ctx, SubmitRequest{Input: model.AgentInput{Parts: []model.AgentInputPart{{Kind: "text", Text: text}}}}, binding, nil)
			if err != nil {
				retire()
				return err
			}
			// A fast terminal commit can precede the admission callback's
			// execution binding. Check the durable observation across that gap.
			record, err := c.config.Thread(call.owner)
			if err == nil {
				c.mu.Lock()
				c.voiceFailure(record)
				c.mu.Unlock()
			}
			return err
		},
	})
	if cause := context.Cause(ctx); cause != nil {
		return errors.Join(cause, err)
	}
	return err
}

// Called under the serialized user-input admission, before native Send. A
// typed input also retires the previous voice binding.
func (c *Coordinator) startVoiceInput(binding *voiceBinding, owner string) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	call := c.voice
	if binding != nil && (call != binding.call || call.owner != owner || call.ctx.Err() != nil) {
		return errors.New("the voice input belongs to a retired Chief")
	}
	if call != nil {
		if call.binding != nil && call.binding != binding {
			call.binding.cancel()
		}
		call.binding = binding
	}
	return nil
}

// Called with Coordinator.mu. Only the current binding can report failure.
func (c *Coordinator) voiceFailure(record model.ThreadRecord) {
	execution := record.Observation.LatestExecution
	call := c.voice
	if call == nil || call.owner != record.ID || record.Revision < c.scopeRevision ||
		execution == nil || execution.Status != "failed" {
		return
	}
	b := call.binding
	if b == nil || b.execution != execution.ExecutionID || b.ctx.Err() != nil || b.failureReported {
		return
	}
	b.failureReported = true
	message := "execution failed"
	if execution.Error != nil && *execution.Error != "" {
		message = *execution.Error
	}
	// A pending failure can only belong to a superseded binding. Keep the
	// current failure available without blocking the observation publisher.
	select {
	case <-call.failures:
	default:
	}
	call.failures <- plugin.VoiceFailure{
		Context: b.ctx, HandoffID: b.handoff,
		Err: fmt.Errorf("Chief (%s): %s", record.HarnessID, message),
	}
}
