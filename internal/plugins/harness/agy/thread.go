package agy

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
)

type permission struct {
	rpcID   json.RawMessage
	options map[string]string
}
type execution struct {
	cancel         context.CancelCauseFunc
	done           chan struct{}
	client         *client
	prompting      bool
	stopping       bool
	requests       map[string]permission
	sequence       int64
	lastTextCommit time.Time
	lastProgress   time.Time
	idle           *time.Timer
}
type handle struct {
	host   plugin.HostContext
	open   plugin.OpenContext
	mu     sync.Mutex
	state  state
	active *execution
	peer   *client
	native catalog
	closed bool
}

func (a *Adapter) Open(ctx context.Context, in plugin.OpenContext) (plugin.Handle, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if i := in.Injection; i != nil && (i.Tools != nil || len(i.Seed)+len(i.Instructions)+len(i.ContextEntries) > 0) {
		return nil, errors.New("Antigravity does not support coordinator injection")
	}
	s, err := decodeState(in.SessionState.Read())
	if err != nil {
		return nil, err
	}
	h := &handle{state: s, host: a.host, open: in}
	// A fresh handle cannot answer requests belonging to a dead stdio peer.
	if n := len(s.Turns); n > 0 && !s.Turns[n-1].Terminal() {
		s.Turns[n-1].finish("interrupted", time.Now().UnixMilli())
		if err = h.commit(ctx); err != nil {
			return nil, err
		}
	}
	return h, nil
}
func (h *handle) commit(ctx context.Context) error {
	raw, err := json.Marshal(h.state)
	if err != nil {
		return err
	}
	return h.open.SessionState.Commit(ctx, raw)
}
func preparePrompt(req plugin.SendRequest) ([]object, string, error) {
	var prompt []object
	var visible []string
	for _, entry := range req.ContextEntries {
		prompt = append(prompt, object{"type": "text", "text": entry.Content})
	}
	if len(req.Input.Annotations) > 0 && string(req.Input.Annotations) != "null" {
		prompt = append(prompt, object{"type": "text", "text": string(req.Input.Annotations)})
	}
	for _, p := range req.Input.Parts {
		var text string
		switch p.Kind {
		case "text":
			text = p.Text
		case "mention", "skill":
			text = p.Name + " (" + p.Path + ")"
		case "local-file":
			if p.File == nil || p.File.Path == "" {
				return nil, "", errors.New("Antigravity requires a resolved attachment")
			}
			text = p.File.Path
		default:
			return nil, "", fmt.Errorf("Antigravity does not support %s input", p.Kind)
		}
		visible = append(visible, text)
		prompt = append(prompt, object{"type": "text", "text": text})
	}
	return prompt, strings.Join(visible, "\n"), nil
}
func (h *handle) Send(ctx context.Context, req plugin.SendRequest) (err error) {
	if req.FollowUpOnly {
		return plugin.ErrFollowUpUnavailable
	}
	prompt, text, err := preparePrompt(req)
	if err != nil {
		return err
	}
	record := h.open.ReadThread()
	s, err := parseSettings(record.Settings)
	if err != nil {
		return err
	}
	cwd := record.Cwd
	if record.Worktree != nil {
		cwd = record.Worktree.Cwd
	}
	h.mu.Lock()
	if h.closed {
		h.mu.Unlock()
		return errors.New("Antigravity thread is closed")
	}
	if h.active != nil {
		h.mu.Unlock()
		return errors.New("wait for the active Antigravity turn to finish before sending")
	}
	if t := h.state.find(req.ExecutionID); t != nil {
		ended := t.Terminal()
		h.mu.Unlock()
		if ended {
			return plugin.ErrExecutionEnded
		}
		return errors.New("Antigravity execution is already present")
	}
	runCtx, cancel := context.WithCancelCause(context.WithoutCancel(ctx))
	run := &execution{cancel: cancel, done: make(chan struct{}), requests: map[string]permission{}}
	h.active = run
	h.state.Turns = append(h.state.Turns, turn{PublicExecution: model.PublicExecution{ExecutionID: req.ExecutionID, Status: "running", StartedAt: time.Now().UnixMilli()}, Prompt: text, UserRowID: req.FollowUpRowID})
	sessionID := h.state.Session
	if err = h.commit(ctx); err != nil {
		h.state.Turns = h.state.Turns[:len(h.state.Turns)-1]
		h.active = nil
		h.mu.Unlock()
		cancel(nil)
		return err
	}
	h.mu.Unlock()
	// Core cancels the send context before calling Interrupt. Deliver the native
	// cancellation first and kill only this run if the peer stops responding.
	stopCaller := context.AfterFunc(ctx, func() { h.requestStop(run) })
	defer stopCaller()
	defer func() {
		h.mu.Lock()
		defer h.mu.Unlock()
		t := h.state.find(req.ExecutionID)
		status := "completed"
		if cause := context.Cause(runCtx); cause != nil {
			err = cause
		}
		if run.stopping || errors.Is(err, context.Canceled) {
			status = "interrupted"
		} else if err != nil {
			status = "failed"
			msg := excerpt(err.Error())
			t.Error = &msg
		}
		t.finish(status, time.Now().UnixMilli())
		err = errors.Join(err, h.commit(context.WithoutCancel(ctx)))
		h.active = nil
		cancel(nil)
		close(run.done)
	}()
	if req.Admitted != nil {
		if err = req.Admitted(); err != nil {
			return err
		}
	}
	// Send owns the native connection until its terminal commit. Close waits on
	// that commit before taking an idle peer.
	c := h.peer
	if c != nil {
		select {
		case <-c.done:
			h.peer = nil
			if err = c.close(); err != nil {
				return err
			}
			c = nil
		default:
		}
	}
	if c == nil {
		c, err = start(runCtx, h.host, cwd)
		if err != nil {
			return err
		}
		h.peer = c
		h.native = catalog{}
	}
	abort := context.AfterFunc(runCtx, c.abort)
	defer func() {
		stopped := abort()
		h.mu.Lock()
		retire := run.stopping
		h.mu.Unlock()
		// A delayed cancellation write must never reach a successor prompt.
		if retire || err != nil || !stopped || runCtx.Err() != nil {
			h.peer = nil
			err = errors.Join(err, c.close())
		}
	}()
	timer := time.AfterFunc(30*time.Second, func() { cancel(context.DeadlineExceeded) })
	defer timer.Stop()
	if h.native.ID == "" {
		info, initErr := c.initialize()
		if initErr != nil {
			return initErr
		}
		h.native, err = c.session(info, cwd, sessionID)
		if err != nil {
			return err
		}
	}
	cat := &h.native
	if cat.Modes.Current != "default" {
		if err = c.call("session/set_mode", object{"sessionId": cat.ID, "modeId": "default"}, nil); err != nil {
			return err
		}
	}
	cat.Modes.Current = "default"
	if s.Model != "" && s.Model != cat.Models.Current {
		if !slices.ContainsFunc(cat.Models.Available, func(m nativeModel) bool { return m.ID == s.Model }) {
			return errors.New("selected Antigravity model is unavailable")
		}
		if err = c.call("session/set_model", object{"sessionId": cat.ID, "modelId": s.Model}, nil); err != nil {
			return err
		}
		cat.Models.Current = s.Model
	}
	timer.Stop()
	h.mu.Lock()
	h.state.Session = cat.ID
	h.state.find(req.ExecutionID).Model = cat.Models.Current
	run.client = c
	err = h.commit(runCtx)
	h.mu.Unlock()
	if err != nil {
		return err
	}
	watch := watchTrajectory(c.geminiDir, cat.ID)
	var result struct {
		Reason string `json:"stopReason"`
	}
	rpc, err := c.send("session/prompt", object{"sessionId": cat.ID, "prompt": prompt}, func(f frame) error { return h.event(runCtx, run, req.ExecutionID, cat.ID, f) })
	if err != nil {
		return err
	}
	h.mu.Lock()
	run.prompting = true
	run.lastProgress = time.Now()
	h.mu.Unlock()
	h.watchPrompt(run)
	err = c.response(rpc, &result)
	h.mu.Lock()
	run.prompting = false
	if run.idle != nil {
		run.idle.Stop()
	}
	h.mu.Unlock()
	if err != nil {
		return err
	}
	switch result.Reason {
	case "end_turn":
		if watch.failed() {
			return errors.New("Antigravity recorded a provider error")
		}
	case "cancelled":
		h.mu.Lock()
		run.stopping = true
		h.mu.Unlock()
	default:
		return fmt.Errorf("Antigravity stopped (%s)", excerpt(result.Reason))
	}
	return nil
}

// A silent native peer can keep its pipes open forever. An outstanding
// permission belongs to the user and has no inactivity deadline.
func (h *handle) watchPrompt(run *execution) {
	const timeout = 15 * time.Minute
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.active != run || !run.prompting || run.stopping {
		return
	}
	delay := time.Until(run.lastProgress.Add(timeout))
	if len(run.requests) > 0 {
		delay = timeout
	}
	if delay <= 0 {
		run.cancel(errors.New("Antigravity sent no prompt progress for 15 minutes"))
		return
	}
	run.idle = time.AfterFunc(delay, func() { h.watchPrompt(run) })
}

func (h *handle) requestStop(run *execution) {
	h.mu.Lock()
	if h.active != run || run.stopping {
		h.mu.Unlock()
		return
	}
	run.stopping = true
	if !run.prompting {
		run.cancel(context.Canceled)
		h.mu.Unlock()
		return
	}
	c, session := run.client, h.state.Session
	h.mu.Unlock()
	// Scope both the notification and the fallback to this one stdio process.
	timer := time.AfterFunc(time.Second, func() { run.cancel(context.Canceled) })
	defer timer.Stop()
	if err := c.write(object{"method": "session/cancel", "params": object{"sessionId": session}}); err != nil {
		run.cancel(context.Canceled)
	}
	<-run.done
}
func (h *handle) stop(ctx context.Context, closing bool) error {
	h.mu.Lock()
	if closing {
		h.closed = true
	}
	run := h.active
	h.mu.Unlock()
	if run == nil {
		return nil
	}
	go h.requestStop(run)
	select {
	case <-run.done:
		return nil
	case <-ctx.Done():
		run.cancel(ctx.Err())
		return ctx.Err()
	}
}
func (h *handle) Interrupt(ctx context.Context) error { return h.stop(ctx, false) }
func (h *handle) Close() error {
	if err := h.stop(context.Background(), true); err != nil {
		return err
	}
	h.mu.Lock()
	c := h.peer
	h.peer = nil
	id := h.native.ID
	h.mu.Unlock()
	if c == nil {
		return nil
	}
	if c.canClose && id != "" {
		timeout := time.AfterFunc(2*time.Second, c.abort)
		_ = c.call("session/close", object{"sessionId": id}, nil)
		timeout.Stop()
	}
	return c.close()
}
func (h *handle) Read(context.Context, string) (string, error) {
	return "", errors.New("Antigravity does not provide independent history questions; open the saved thread to read its transcript")
}
