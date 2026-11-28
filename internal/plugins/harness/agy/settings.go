package agy

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
	"strings"
	"time"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
)

type Adapter struct {
	host plugin.HostContext
}

var _ plugin.Harness = (*Adapter)(nil)

func New(host plugin.HostContext) *Adapter { return &Adapter{host: host} }
func (*Adapter) Descriptor() plugin.HarnessDescriptor {
	return plugin.HarnessDescriptor{ID: "agy", DisplayName: "Antigravity", Roles: []string{plugin.AgentThreadRole}, ThreadCapabilities: plugin.ThreadCapabilities{SendContext: true, ToolModes: []string{}}}
}
func (*Adapter) DefaultSettings() json.RawMessage         { return json.RawMessage(`{}`) }
func (a *Adapter) Settings() plugin.HarnessSettings       { return a }
func (*Adapter) SessionState() plugin.SessionStateAdapter { return projection{} }
func (*Adapter) Metadata() plugin.ThreadMetadataAdapter   { return metadata{} }
func (a *Adapter) Detect(ctx context.Context, cwd string) (plugin.Installation, error) {
	var installed plugin.Installation
	err := a.probe(ctx, cwd, func(c *client, info initialization) error {
		installed = plugin.Installation{Status: "installed", ExecutablePath: c.path, Message: "Antigravity " + info.Agent.Version}
		return nil
	})
	if err != nil {
		var missing *model.Error
		if errors.As(err, &missing) && missing.Code == "HARNESS_EXECUTABLE_NOT_FOUND" {
			return plugin.Installation{Status: "missing"}, nil
		}
		return plugin.Installation{}, err
	}
	return installed, nil
}

type settings struct {
	AuthMethod string `json:"authMethod,omitempty"`
	Model      string `json:"model,omitempty"`
}

func validModelID(id string) bool {
	return id != "" && strings.TrimSpace(id) == id && !strings.ContainsRune(id, 0) && model.UTF16Length(id) <= 512
}

func parseSettings(raw json.RawMessage) (settings, error) {
	var s settings
	if !model.IsNull(raw) {
		if err := model.Unmarshal(raw, &s); err != nil {
			return s, err
		}
	}
	switch s.AuthMethod {
	case "", "oauth-personal", "oauth-business", "gemini-api-key", "agent-platform":
	default:
		return s, errors.New("unknown Antigravity authentication method")
	}
	if s.Model != "" && !validModelID(s.Model) {
		return s, errors.New("invalid Antigravity model ID")
	}
	return s, nil
}
func (*Adapter) Normalize(raw json.RawMessage) (json.RawMessage, error) {
	s, err := parseSettings(raw)
	if err != nil {
		return nil, err
	}
	return json.Marshal(s)
}
func (a *Adapter) DefaultThread(raw json.RawMessage) (json.RawMessage, error) {
	return a.Normalize(raw)
}
func (a *Adapter) SnapshotExecution(ctx context.Context, req plugin.SettingsRequest, _ bool) (json.RawMessage, error) {
	return a.Normalize(req.Settings)
}
func (a *Adapter) ResolveThread(ctx context.Context, req plugin.ResolveSettingsRequest) (json.RawMessage, error) {
	s, err := parseSettings(req.Merged)
	if err != nil {
		return nil, err
	}
	if !model.IsNull(req.Existing) {
		s, err = parseSettings(req.Existing)
		if err != nil {
			return nil, err
		}
	}
	if req.Dispatch || !model.IsNull(req.Requested) {
		// Model-controlled creation arguments must never choose a program to run.
		var choice struct {
			Model string `json:"model"`
		}
		if err = model.Unmarshal(req.Requested, &choice); err != nil {
			return nil, err
		}
		if !validModelID(choice.Model) {
			return nil, errors.New("an explicit Antigravity model is required")
		}
		s.Model = choice.Model
	}
	return json.Marshal(s)
}
func (*Adapter) HasThreadContent(raw json.RawMessage) bool {
	s, err := decodeState(raw)
	return err != nil || len(s.Turns) > 0
}
func (a *Adapter) ApplyThreadUpdate(ctx context.Context, req plugin.UpdateSettingsRequest) (json.RawMessage, error) {
	resolved, err := a.ResolveThread(ctx, plugin.ResolveSettingsRequest{Existing: req.Current, Requested: req.Update, Cwd: req.Cwd})
	if err != nil {
		return nil, err
	}
	cat, _, err := a.catalog(ctx, resolved, req.Cwd)
	if err != nil {
		return nil, err
	}
	choice, err := parseSettings(resolved)
	if err != nil {
		return nil, err
	}
	if !slices.ContainsFunc(cat.Models.Available, func(m nativeModel) bool { return m.ID == choice.Model }) {
		return nil, errors.New("selected Antigravity model is unavailable")
	}
	return resolved, nil
}
func (a *Adapter) PromptSettings(harness, thread json.RawMessage) (json.RawMessage, error) {
	if !model.IsNull(thread) {
		return a.Normalize(thread)
	}
	return a.DefaultThread(harness)
}

// Each discovery owns a short-lived peer. Installation needs only initialize,
// so a signed-out user can still select the target and configure authentication.
func (a *Adapter) probe(ctx context.Context, cwd string, inspect func(*client, initialization) error) (err error) {
	ctx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()
	c, err := start(ctx, a.host, cwd)
	if err != nil {
		return err
	}
	stop := context.AfterFunc(ctx, c.abort)
	defer func() {
		stop()
		err = errors.Join(err, ctx.Err(), c.close())
	}()
	info, err := c.initialize()
	if err != nil {
		return err
	}
	return inspect(c, info)
}

func (a *Adapter) catalog(ctx context.Context, raw json.RawMessage, cwd string) (cat catalog, cli object, err error) {
	s, err := parseSettings(raw)
	if err != nil {
		return cat, nil, err
	}
	err = a.probe(ctx, cwd, func(c *client, info initialization) error {
		var err error
		cat, err = c.session(info, cwd, "", s.AuthMethod)
		if err != nil {
			return err
		}
		if c.canClose {
			if err := c.call("session/close", object{"sessionId": cat.ID}, nil); err != nil {
				return err
			}
		}
		cli = object{"available": true, "executablePath": c.path, "version": info.Agent.Version}
		return nil
	})
	return cat, cli, err
}

// The exact model (including its effort suffix) is the only setting the
// coordinator may choose. Validate availability against the execution session.
func modelSchema() object {
	return object{"type": "object", "additionalProperties": false, "required": []string{"model"},
		"properties": object{"model": object{"type": "string", "minLength": 1, "maxLength": 512,
			"description": "Exact Antigravity model ID, including its native effort suffix."}}}
}
func (*Adapter) DispatchSchema() json.RawMessage {
	raw, _ := json.Marshal(modelSchema())
	return raw
}

func (a *Adapter) Describe(ctx context.Context, req plugin.SettingsRequest) (json.RawMessage, error) {
	cat, cli, err := a.catalog(ctx, req.Settings, req.Cwd)
	if err != nil {
		return nil, err
	}
	models := make([]plugin.ModelCatalogEntry, 0, len(cat.Models.Available))
	for _, m := range cat.Models.Available {
		models = append(models, plugin.ModelCatalogEntry{ID: m.ID, Name: m.Name})
	}
	identity, err := json.Marshal([]any{cli, req.Settings, models})
	if err != nil {
		return nil, err
	}
	return plugin.ModelCatalogSchema(modelSchema(), models, string(identity), plugin.CatalogSourceEvidence{Basis: "Antigravity ACP session models"})
}

func (a *Adapter) Presentation(ctx context.Context, req plugin.SettingsPresentationRequest) (json.RawMessage, error) {
	raw := req.Settings
	if !model.IsNull(req.ThreadSettings) {
		raw = req.ThreadSettings
	}
	cat, cli, err := a.catalog(ctx, raw, req.Cwd)
	if err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return json.Marshal(object{"issue": err.Error()})
	}
	models := make([]object, 0, len(cat.Models.Available))
	for _, m := range cat.Models.Available {
		models = append(models, object{"id": m.ID, "name": m.Name})
	}
	return json.Marshal(object{"cli": cli, "models": models, "effectiveModel": object{"model": cat.Models.Current}})
}
