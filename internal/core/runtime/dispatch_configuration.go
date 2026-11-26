package runtime

import (
	"context"
	"encoding/json"
	"errors"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
	"github.com/hupao-creator/Chief/internal/core/store"
)

// RequestDispatchUpdate is also the adapter's invalidation capability. Callers
// name the provider; only its ordinary settings scope can publish target data.
func (r *Runtime) RequestDispatchUpdate(ctx context.Context, id string, refresh bool) (json.RawMessage, error) {
	if err := r.begin(); err != nil {
		return nil, err
	}
	defer r.operations.Done()
	ctx, cancel := r.operationContext(ctx)
	defer cancel()
	h := r.config.Harnesses[id]
	if h == nil || r.config.DisabledHarnesses[id] != "" {
		return nil, errors.New("unknown or disabled dispatch provider")
	}
	saved, _, err := r.Settings()
	if err != nil {
		return nil, err
	}
	settings := saved.Harnesses[id]
	if len(settings) == 0 {
		settings = h.DefaultSettings()
	}
	return r.dispatch.Update(ctx, id, string(settings), func(ctx context.Context) (json.RawMessage, json.RawMessage, error) {
		var references json.RawMessage
		value, err := h.Settings().Presentation(ctx, plugin.SettingsPresentationRequest{Settings: settings, Cwd: r.config.DefaultCwd, Refresh: refresh, ModelReferences: func(raw json.RawMessage) { references = raw }})
		return value, references, err
	}, func(tx *store.Tx) bool {
		var current model.Settings
		if ok, err := tx.Get("settings", &current); err != nil || !ok {
			return false
		}
		latest := current.Harnesses[id]
		if len(latest) == 0 {
			latest = h.DefaultSettings()
		}
		return sameExecutionProfile(latest, settings)
	})
}
func (r *Runtime) DispatchConfigurationChanged(ctx context.Context, id string) {
	if r.dispatch.AfterCurrent(ctx, id) == nil {
		_, _ = r.RequestDispatchUpdate(ctx, id, false)
	}
}
func (r *Runtime) DispatchOptions(ids []string) json.RawMessage { return r.dispatch.Options(ids) }
func (r *Runtime) DispatchBenchmarks(id string) json.RawMessage {
	if v := r.dispatch.Read(id).Benchmarks; len(v) > 0 {
		return v
	}
	return json.RawMessage(`{"models":[]}`)
}
func (r *Runtime) SubscribeDispatchOptions() (<-chan struct{}, func()) { return r.dispatch.Subscribe() }

func (r *Runtime) SteerDispatchOptions(ctx context.Context, id, execution string, injection *plugin.Injection, entry plugin.ContextEntry) error {
	ctx = context.WithValue(ctx, mokuLazyAdmissionKey{}, true)
	ctx = context.WithValue(ctx, expectedUserExecutionKey{}, execution)
	input := model.AgentInput{Presentation: "internal", Parts: []model.AgentInputPart{{Kind: "text", Text: "The published dispatch options have changed."}}}
	_, err := r.SendMokuThread(ctx, id, input, injection, []plugin.ContextEntry{entry}, nil)
	return err
}
