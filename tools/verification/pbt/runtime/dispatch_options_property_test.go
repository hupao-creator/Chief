package runtime_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/hupao-creator/Chief/internal/core/model"
	core "github.com/hupao-creator/Chief/internal/core/runtime"
	"github.com/hupao-creator/Chief/internal/core/store"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/hupao-creator/Chief/internal/core/plugin"
	"github.com/hupao-creator/Chief/internal/plugins/harness/agy"
	"github.com/hupao-creator/Chief/internal/plugins/harness/claude"
	"github.com/hupao-creator/Chief/internal/plugins/harness/codex"
	"github.com/hupao-creator/Chief/internal/plugins/harness/opencode"
	"github.com/hupao-creator/Chief/internal/plugins/harness/pi"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

// PBT-DISPATCH-OPTIONS: internal/services/dispatchconfig/README.md
func TestDispatchOptionsProperties(t *testing.T) {
	rapidcheck.Check(t, func(t *rapid.T) {
		calls := 0
		host := plugin.HostContext{Environment: func(context.Context) (map[string]string, error) {
			calls++
			return nil, errors.New("provider discovery offline")
		}, ResolveExecutable: func(context.Context, string, string, string) (string, error) {
			calls++
			return "", errors.New("provider unavailable")
		}}
		for _, h := range []plugin.Harness{codex.New(host), claude.New(host), opencode.New(host), pi.New(host), agy.New(host)} {
			id := h.Descriptor().ID
			if closer, ok := h.(interface{ Close() error }); ok {
				defer closer.Close()
			}
			name := fmt.Sprintf("unpublished-%d", rapid.Uint32().Draw(t, "model"))
			choice := rapid.SampledFrom([]string{"fixed", "effort"}).Draw(t, "thinking")
			thinking := map[string]string{"mode": choice}
			if choice == "effort" {
				thinking["effort"] = "high"
			}
			request := map[string]any{"model": name}
			if id != "agy" { // Antigravity encodes effort in its native model ID.
				request["thinking"] = thinking
			}
			if id == "codex" {
				request["serviceTier"] = "default"
			}
			if id == "opencode" || id == "pi" {
				request["provider"] = "unlisted"
			}
			if choice == "effort" && id == "opencode" {
				request["variant"] = "custom-high"
			}
			if choice == "effort" && id == "pi" {
				request["thinkingLevel"] = "high"
			}
			settings := h.Settings()
			defaults, err := settings.DefaultThread(h.DefaultSettings())
			if err != nil {
				t.Fatal(err)
			}
			result, err := settings.ResolveThread(context.Background(), plugin.ResolveSettingsRequest{Dispatch: true, Merged: defaults, Requested: raw(request), Cwd: "/offline"})
			if err != nil {
				t.Fatalf("%s rejected unpublished model: %v", id, err)
			}
			var applied map[string]any
			if json.Unmarshal(result, &applied) != nil || applied["model"] != name {
				t.Fatalf("%s lost model selection", id)
			}
			if calls != 0 {
				t.Fatalf("%s initiated native discovery", id)
			}
			for _, key := range []string{"provider", "serviceTier", "variant", "thinkingLevel"} {
				if v, ok := request[key]; ok && applied[key] != v {
					t.Fatalf("%s lost %s", id, key)
				}
			}
			overrides := map[string]string{"executablePath": "/unexpected"}
			if id == "agy" {
				overrides["authMethod"] = "oauth-personal"
				overrides["permissionMode"] = "accept-edits"
			}
			for key, override := range overrides {
				request[key] = override
				if _, err := settings.ResolveThread(context.Background(), plugin.ResolveSettingsRequest{Dispatch: true, Merged: defaults, Requested: raw(request)}); err == nil {
					t.Fatalf("%s accepted a %s override", id, key)
				}
				delete(request, key)
			}
		}
	})
}

// The target keeps the production OpenCode settings adapter. Only native Send
// is replaced, so each generated acceptance/rejection has an observable receipt.
type dispatchChiefPeer struct{ injectedToolPeer }

func (*dispatchChiefPeer) Descriptor() plugin.HarnessDescriptor {
	return plugin.HarnessDescriptor{ID: "fixture", Roles: plugin.StandardHarnessRoles(), ThreadCapabilities: plugin.ThreadCapabilities{Instructions: true, ThreadContext: true, SendContext: true, ToolModes: []string{"exclusive"}}}
}

type dispatchTargetPeer struct {
	harness
	adapter  plugin.Harness
	reject   bool
	sends    int
	settings json.RawMessage
}

func (h *dispatchTargetPeer) Descriptor() plugin.HarnessDescriptor {
	return plugin.HarnessDescriptor{ID: "opencode", Roles: []string{plugin.AgentThreadRole}}
}
func (h *dispatchTargetPeer) Settings() plugin.HarnessSettings { return h.adapter.Settings() }
func (h *dispatchTargetPeer) DefaultSettings() json.RawMessage { return h.adapter.DefaultSettings() }
func (h *dispatchTargetPeer) Open(ctx context.Context, o plugin.OpenContext) (plugin.Handle, error) {
	h.settings = o.ReadThread().Settings
	return &dispatchHandle{handle: &handle{ctx: ctx, open: o}, peer: h}, nil
}

type dispatchHandle struct {
	*handle
	peer *dispatchTargetPeer
}

func (h *dispatchHandle) Send(ctx context.Context, req plugin.SendRequest) error {
	h.peer.sends++
	if h.peer.reject {
		return errors.New("native rejected requested model")
	}
	return h.handle.Send(ctx, req)
}

func TestDispatchAdmissionProperties(t *testing.T) {
	rapidcheck.Check(t, func(t *rapid.T) {
		ctx := context.Background()
		root, err := os.MkdirTemp("", "chief-dispatch-admission-")
		if err != nil {
			t.Fatal(err)
		}
		defer os.RemoveAll(root)
		db, err := store.Open(filepath.Join(root, "state.sqlite"))
		if err != nil {
			t.Fatal(err)
		}
		defer db.Close()
		unavailable := errors.New("OpenCode account identity schema is unavailable")
		native := opencode.New(plugin.HostContext{Environment: func(context.Context) (map[string]string, error) { return nil, unavailable }})
		defer native.Close()
		peer := &dispatchChiefPeer{}
		target := &dispatchTargetPeer{adapter: native, reject: rapid.Bool().Draw(t, "native-rejection")}
		harnesses := map[string]plugin.Harness{"fixture": peer, "opencode": target}
		r, err := core.New(ctx, core.Config{Store: db, Harnesses: harnesses, DefaultCwd: root, DataDir: root})
		if err != nil {
			t.Fatal(err)
		}
		defer r.Close(ctx)
		_, err = db.Update(ctx, func(tx *store.Tx) error {
			var s model.Settings
			_, e := tx.Get("settings", &s)
			if e != nil {
				return e
			}
			s.Moku.HostHarnessPreference = "fixture"
			s.Moku.TargetHarnessIDs = []string{"opencode"}
			return tx.Put("settings", s)
		})
		if err != nil {
			t.Fatal(err)
		}
		// Reproduce a cold, indefinitely unreadable target source before using Chief.
		if _, availability, e := native.DiscoverMokuTarget(ctx, plugin.SettingsRequest{Settings: native.DefaultSettings(), Cwd: root}); e == nil && availability.Available {
			t.Fatal("fault fixture unexpectedly discovered a catalog")
		}
		c, tool := openChiefTool(t, ctx, r, root, harnesses, &peer.injectedToolPeer, model.AgentInput{Parts: []model.AgentInputPart{{Kind: "text", Text: "delegate"}}}, "create_thread")
		defer c.Stop(ctx)
		name := fmt.Sprintf("unpublished-%d", rapid.Uint32().Draw(t, "model"))
		result, err := tool.Execute(ctx, plugin.ToolCall{Arguments: raw(map[string]any{"prompt": "work", "worktree": false, "cwd": root, "target": map[string]any{"opencode": map[string]any{"provider": "private", "model": name, "thinking": map[string]string{"mode": "fixed"}}}})})
		if target.sends != 1 {
			t.Fatalf("native sends=%d: %v", target.sends, err)
		}
		var settings map[string]any
		if json.Unmarshal(target.settings, &settings) != nil || settings["model"] != name {
			t.Fatal("native received different settings")
		}
		records, readErr := r.Threads()
		if readErr != nil {
			t.Fatal(readErr)
		}
		id := ""
		for _, record := range records {
			if !record.Moku && record.HarnessID == "opencode" {
				if id != "" {
					t.Fatal("duplicate Thread")
				}
				id = record.ID
			}
		}
		if id == "" {
			t.Fatal("missing created Thread")
		}
		if target.reject {
			var caller *plugin.ToolCallError
			if !errors.As(err, &caller) || !strings.Contains(err.Error(), id) || !strings.Contains(err.Error(), "native rejected") {
				t.Fatalf("lost failure identity: %v", err)
			}
		} else if err != nil || !strings.Contains(string(result), id) {
			t.Fatalf("missing acknowledgement: %s %v", result, err)
		}
	})
}
