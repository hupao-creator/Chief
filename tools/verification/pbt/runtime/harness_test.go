package runtime_test

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
	core "github.com/hupao-creator/Chief/internal/core/runtime"
	"github.com/hupao-creator/Chief/internal/services/moku"
	"pgregory.net/rapid"
)

// Extracted from the historical runtime-concurrency fixture. This peer only
// commits native observations and acknowledgements; Runtime owns reservations,
// retries, cancellation and lifecycle events.
func raw(v any) json.RawMessage {
	b, err := json.Marshal(v)
	if err != nil {
		panic(err)
	}
	return b
}

type harness struct{}

func (*harness) Descriptor() plugin.HarnessDescriptor { return plugin.HarnessDescriptor{ID: "fixture"} }
func (*harness) DefaultSettings() json.RawMessage     { return raw(map[string]any{}) }
func (*harness) Detect(context.Context, string) (plugin.Installation, error) {
	return plugin.Installation{Status: "installed"}, nil
}
func (*harness) Settings() plugin.HarnessSettings         { return settings{} }
func (*harness) Metadata() plugin.ThreadMetadataAdapter   { return metadata{} }
func (*harness) SessionState() plugin.SessionStateAdapter { return stateAdapter{} }
func (*harness) Open(context.Context, plugin.OpenContext) (plugin.Handle, error) {
	panic("propertyHarness owns Open")
}

type settings struct{ plugin.HarnessSettings }

func (settings) DefaultThread(value json.RawMessage) (json.RawMessage, error) {
	return model.CloneRaw(value), nil
}
func (settings) SnapshotExecution(context.Context, plugin.SettingsRequest, bool) (json.RawMessage, error) {
	return raw(map[string]any{}), nil
}
func (settings) Presentation(ctx context.Context, _ plugin.SettingsPresentationRequest) (json.RawMessage, error) {
	return raw(map[string]any{}), ctx.Err()
}
func (settings) Normalize(value json.RawMessage) (json.RawMessage, error) { return value, nil }
func (settings) ResolveThread(context.Context, plugin.ResolveSettingsRequest) (json.RawMessage, error) {
	return raw(map[string]any{}), nil
}
func (settings) HasThreadContent(value json.RawMessage) bool { return !model.IsNull(value) }
func (settings) ApplyThreadUpdate(_ context.Context, request plugin.UpdateSettingsRequest) (json.RawMessage, error) {
	return request.Update, nil
}

type metadata struct{}

func (metadata) Initialize(string, model.AgentInput, json.RawMessage) (json.RawMessage, error) {
	return raw(map[string]string{"title": "Fixture task"}), nil
}
func (metadata) Project(value json.RawMessage) (string, error) {
	var item map[string]string
	err := json.Unmarshal(value, &item)
	return item["title"], err
}
func (metadata) Fork(value json.RawMessage, _ string) (json.RawMessage, error) { return value, nil }

type state struct {
	Observation model.PublicObservation `json:"observation"`
	Messages    []string                `json:"messages"`
}
type stateAdapter struct{}

func (stateAdapter) Project(value json.RawMessage) (model.PublicObservation, error) {
	var s state
	if model.IsNull(value) {
		return s.Observation, nil
	}
	err := json.Unmarshal(value, &s)
	return s.Observation, err
}
func (stateAdapter) ProjectRenderer(value json.RawMessage, _ model.RendererScope) (json.RawMessage, error) {
	if model.IsNull(value) {
		return raw(map[string]any{}), nil
	}
	return value, nil
}
func (stateAdapter) ReadContext(value json.RawMessage) (json.RawMessage, error) { return value, nil }
func (stateAdapter) ResolveExecution(value json.RawMessage, id string) (*model.PublicExecution, error) {
	o, err := (stateAdapter{}).Project(value)
	if err != nil {
		return nil, err
	}
	if o.LatestExecution != nil && o.LatestExecution.ExecutionID == id {
		return o.LatestExecution, nil
	}
	return nil, nil
}
func (stateAdapter) Settle(request plugin.SettleRequest) (json.RawMessage, error) {
	var s state
	if err := json.Unmarshal(request.SessionState, &s); err != nil {
		return nil, err
	}
	s.Observation.LatestExecution.Status = request.Outcome
	s.Observation.LatestExecution.FinishedAt = &request.FinishedAt
	return raw(s), nil
}

type handle struct {
	open plugin.OpenContext
	ctx  context.Context
}

func (h *handle) Send(ctx context.Context, q plugin.SendRequest) error {
	var s state
	if b := h.open.SessionState.Read(); !model.IsNull(b) {
		if err := json.Unmarshal(b, &s); err != nil {
			return err
		}
	}
	s.Messages = append(s.Messages, q.Input.Parts[0].Text)
	if e := s.Observation.LatestExecution; e == nil || e.ExecutionID != q.ExecutionID {
		s.Observation.LatestExecution = &model.PublicExecution{ExecutionID: q.ExecutionID, Status: "running", StartedAt: time.Now().UnixMilli()}
	}
	if err := h.open.SessionState.Commit(ctx, raw(s)); err != nil {
		return err
	}
	return q.Admitted()
}
func (h *handle) Interrupt(ctx context.Context) error {
	var s state
	if b := h.open.SessionState.Read(); !model.IsNull(b) {
		if err := json.Unmarshal(b, &s); err != nil {
			return err
		}
	}
	if s.Observation.LatestExecution != nil && !s.Observation.LatestExecution.Terminal() {
		at := time.Now().UnixMilli()
		s.Observation.LatestExecution.Status = "interrupted"
		s.Observation.LatestExecution.FinishedAt = &at
		return h.open.SessionState.Commit(ctx, raw(s))
	}
	return nil
}
func (*handle) Respond(context.Context, model.RespondRequest) error { return nil }
func (*handle) Read(context.Context, string) (string, error)        { return "fixture", nil }

// Closing joins the synchronous peer without settling its durable execution.
func (*handle) Close() error { return nil }
func create(r *core.Runtime) (core.CreatedThread, error) {
	return r.CreateThread(context.Background(), core.CreateThreadRequest{HarnessID: "fixture", Input: model.AgentInput{Parts: []model.AgentInputPart{{Kind: "text", Text: "hello"}}}})
}

// The peer captures the tools actually
// injected at Open. Tool selection, authorization, and persistence run in production code.
type injectedToolPeer struct {
	harness
	tools *plugin.ToolInjection
}

func (h *injectedToolPeer) Open(ctx context.Context, o plugin.OpenContext) (plugin.Handle, error) {
	if o.Injection != nil {
		h.tools = o.Injection.Tools
	}
	return &handle{open: o, ctx: ctx}, nil
}

func openChiefTool(t *rapid.T, ctx context.Context, r *core.Runtime, chiefCwd string, harnesses map[string]plugin.Harness, peer *injectedToolPeer, input model.AgentInput, toolName string) (*moku.Coordinator, plugin.ToolBinding) {
	t.Helper()
	coordinator, err := moku.New(moku.Configuration{
		DispatchOptions: r.DispatchOptions,
		CreateThread: func(ctx context.Context, req moku.CreateThreadRequest) (moku.CreatedThread, error) {
			v, err := r.CreateThread(ctx, core.CreateThreadRequest{HarnessID: req.HarnessID, Input: req.Input, Cwd: req.Cwd, Worktree: req.Worktree, ResolveSettings: req.ResolveSettings})
			return moku.CreatedThread{Record: v.Record, Execution: v.Execution, Acknowledgement: v.Acknowledgement}, err
		},
		Workspace: chiefCwd, Harnesses: harnesses, Settings: r.Settings, Threads: r.Threads, Thread: r.Thread, UpdateThread: r.UpdateThread,
		ConfigureSession: func(ctx context.Context, id string, revision int64, c moku.SessionConfiguration) error {
			return r.ConfigureMokuThread(ctx, id, revision, c.HarnessID, c.Settings, c.AppliedSettings, c.SettingsRevision, c.Cwd)
		},
		OpenSession: r.OpenMokuThread, CloseSession: r.CloseMokuThread, SendSession: r.SendMokuThread, SubscribeCommitted: r.OnThreadCommitted,
		RemoveWorktree: r.RemoveWorktree, SendThread: r.SendThread, PendingDeliveries: r.ReadyMokuDeliveries, SendDelivery: r.SendMokuDelivery,
		EnsureSession: func(ctx context.Context, c moku.SessionConfiguration) (model.ThreadRecord, error) {
			return r.EnsureMokuThread(ctx, c.HarnessID, c.Settings, c.Cwd)
		},
		ReplaceSession: func(context.Context, string, moku.SessionConfiguration) (model.ThreadRecord, error) {
			return model.ThreadRecord{}, errors.New("unexpected replacement")
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := coordinator.Start(ctx, plugin.RuntimeStartContext{}); err != nil {
		t.Fatal(err)
	}

	if err := coordinator.Submit(ctx, moku.SubmitRequest{Input: input}); err != nil {
		t.Fatal(err)
	}
	var tool plugin.ToolBinding
	if peer.tools == nil || peer.tools.Mode != "exclusive" {
		t.Fatal("missing Chief injection")
	}
	for _, binding := range peer.tools.Bindings {
		if binding.Name == toolName {
			tool = binding
		}
	}
	if tool.Execute == nil {
		t.Fatalf("%s missing from Chief injection", toolName)
	}
	return coordinator, tool
}
