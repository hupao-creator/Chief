package runtime_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
	core "github.com/hupao-creator/Chief/internal/core/runtime"
	"github.com/hupao-creator/Chief/internal/core/store"
	"github.com/hupao-creator/Chief/internal/plugins/applications/background"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

// Each native call announces arrival and waits for its caller's release or
// cancellation. The production runtime owns the configuration gate and CAS.
type settingsCall chan chan struct{}

func (calls settingsCall) await(ctx context.Context) error {
	release := make(chan struct{})
	select {
	case calls <- release:
	case <-ctx.Done():
		return ctx.Err()
	}
	select {
	case <-release:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

type delayedSettings struct {
	settings
	reads settingsCall
}

func (s delayedSettings) SnapshotExecution(_ context.Context, r plugin.SettingsRequest, _ bool) (json.RawMessage, error) {
	return r.Settings, nil
}

func (s delayedSettings) Presentation(ctx context.Context, r plugin.SettingsPresentationRequest) (json.RawMessage, error) {
	return r.Settings, s.reads.await(ctx)
}

type settingsHarness struct {
	harness
	native delayedSettings
}

func (h settingsHarness) Settings() plugin.HarnessSettings { return h.native }
func (settingsHarness) Descriptor() plugin.HarnessDescriptor {
	return plugin.HarnessDescriptor{ID: "fixture", ThreadCapabilities: plugin.ThreadCapabilities{
		Instructions: true, ThreadContext: true, SendContext: true, ToolModes: []string{"exclusive"},
	}}
}

func TestSettingsPresentationProperties(t *testing.T) {
	rapidcheck.Check(t, func(t *rapid.T) {
		root, err := os.MkdirTemp("", "chief-settings-pbt-")
		if err != nil {
			t.Fatal(err)
		}
		defer os.RemoveAll(root)
		db, err := store.Open(filepath.Join(root, "state.sqlite"))
		if err != nil {
			t.Fatal(err)
		}
		defer db.Close()
		native := delayedSettings{reads: make(settingsCall)}
		r, err := core.New(context.Background(), core.Config{Store: db, DataDir: root, DefaultCwd: root,
			Harnesses: map[string]plugin.Harness{"fixture": &settingsHarness{native: native}}})
		if err != nil {
			t.Fatal(err)
		}
		defer r.Close(context.Background())
		ctx, stop := context.WithTimeout(context.Background(), 5*time.Second)
		defer stop()
		first, err := r.EnsureExecutionSettings(ctx, "fixture", "")
		if err != nil || first.Moku.HostHarnessPreference != "fixture" || first.Moku.ExecutionHarnesses["fixture"] == nil {
			t.Fatalf("missing profile or automatic preference was not initialized: %v", err)
		}
		arrival := func(calls settingsCall) chan struct{} {
			select {
			case release := <-calls:
				return release
			case <-ctx.Done():
				t.Fatalf("native call could not progress: %v", ctx.Err())
				return nil
			}
		}
		rounds := rapid.IntRange(1, 6).Draw(t, "rounds")
		for i := range rounds {
			execution := rapid.Bool().Draw(t, "execution")
			order := rapid.SampledFrom([]string{"before-save", "after-save", "cancel"}).Draw(t, "read-completion")
			next, revision, err := r.Settings()
			if err != nil {
				t.Fatal(err)
			}
			request := map[string]string{"scope": "global", "harnessId": "fixture"}
			want := next.Harnesses["fixture"]
			if execution {
				request["executionOwner"] = "moku"
				want = next.Moku.ExecutionHarnesses["fixture"]
			}
			next.Moku.ExecutionHarnesses["fixture"] = raw(map[string]int{"version": i + 1})
			save := func() {
				result, err := r.UpdateSettings(ctx, revision, next)
				if err != nil || result.Status != "saved" {
					t.Fatalf("save conflicted with read: %v (%s)", err, result.Status)
				}
			}
			readCtx, cancel := context.WithCancel(ctx)
			read := make(chan error, 1)
			go func() {
				value, err := r.Invoke(readCtx, "harness:settings-presentation", []json.RawMessage{raw(request)})
				if err == nil && string(value.(map[string]any)["value"].(json.RawMessage)) != string(want) {
					err = errors.New("presentation returned another source")
				}
				read <- err
			}()
			reply := arrival(native.reads)
			if order == "after-save" {
				save()
			}
			if order == "cancel" {
				cancel()
			} else {
				close(reply)
			}
			err = <-read
			cancel()
			switch {
			case order == "cancel":
				if !errors.Is(err, context.Canceled) {
					t.Fatalf("cancelled read: %v", err)
				}
			case order == "after-save" && execution:
				if err == nil || err.Error() != "settings source changed during presentation" {
					t.Fatalf("stale source: %v", err)
				}
			default:
				if err != nil {
					t.Fatalf("valid read: %v", err)
				}
			}
			if order != "after-save" {
				save()
			}
			current, rev, err := r.Settings()
			if err != nil || rev != revision+1 || string(current.Moku.ExecutionHarnesses["fixture"]) != string(next.Moku.ExecutionHarnesses["fixture"]) {
				t.Fatalf("read changed saved settings/revision: %v", err)
			}
		}
	})
}

type roleSettingsHarness struct {
	harness
	id     string
	native roleSettingsNative
}

func (h roleSettingsHarness) Descriptor() plugin.HarnessDescriptor {
	descriptor := (settingsHarness{}).Descriptor()
	descriptor.ID = h.id
	return descriptor
}
func (h roleSettingsHarness) Settings() plugin.HarnessSettings { return h.native }

type roleSettingsNative struct {
	settings
	snapshots *atomic.Int32
}

func (s roleSettingsNative) SnapshotExecution(_ context.Context, _ plugin.SettingsRequest, initial bool) (json.RawMessage, error) {
	s.snapshots.Add(1)
	if !initial {
		return nil, errors.New("native snapshot unavailable")
	}
	return raw(map[string]int{"captured": 1}), nil
}
func (roleSettingsNative) Presentation(_ context.Context, request plugin.SettingsPresentationRequest) (json.RawMessage, error) {
	return raw(map[string]any{"cwd": request.Cwd, "source": request.Settings, "executionProfile": request.ExecutionProfile}), nil
}

type roleSettingsApplications struct{ core.Applications }

func (roleSettingsApplications) Catalog(context.Context) ([]model.ApplicationThread, error) {
	return nil, nil
}
func (roleSettingsApplications) ValidateSettings(_ context.Context, settings model.Settings) (model.Settings, error) {
	contract := background.SettingsContract()
	for i, entry := range settings.PluginSettings {
		value, err := contract.Validate(entry.Value)
		if err != nil {
			return settings, err
		}
		settings.PluginSettings[i].Value = value
	}
	return settings, nil
}
func (roleSettingsApplications) BackgroundSettingsWorkspace(id string) (string, string, bool) {
	switch id {
	case "tag.settings":
		return "tag", "tag.agent", true
	case "report.settings":
		return "report", "report.agent", true
	default:
		return "", "", false
	}
}

func TestBackgroundSettingsSaveProperties(t *testing.T) {
	rapidcheck.Check(t, func(t *rapid.T) {
		root, err := os.MkdirTemp("", "chief-role-settings-pbt-")
		if err != nil {
			t.Fatal(err)
		}
		defer os.RemoveAll(root)
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		db, err := store.Open(filepath.Join(root, "state.sqlite"))
		if err != nil {
			t.Fatal(err)
		}
		defer db.Close()

		var snapshots atomic.Int32
		count := rapid.IntRange(1, 4).Draw(t, "copied-harnesses")
		selected := rapid.IntRange(0, count-1).Draw(t, "selected")
		cold := rapid.Bool().Draw(t, "missing-selected-profile")
		retained := rapid.Bool().Draw(t, "retained-independent")
		harnesses := make(map[string]plugin.Harness)
		profiles := make(map[string]json.RawMessage)
		for i := range count {
			id := fmt.Sprintf("fixture-%d", i)
			harnesses[id] = &roleSettingsHarness{id: id, native: roleSettingsNative{snapshots: &snapshots}}
			if !cold || i != selected {
				profiles[id] = raw(map[string]int{"model": i + 1})
			}
		}
		id := fmt.Sprintf("fixture-%d", selected)
		disabled := map[string]string{}
		if count > 1 && rapid.Bool().Draw(t, "disabled-retained-harness") {
			disabled[fmt.Sprintf("fixture-%d", (selected+1)%count)] = "fixture disabled"
		}
		roles := []string{"tag.settings", "report.settings"}
		r, err := core.New(ctx, core.Config{Store: db, DataDir: root, DefaultCwd: root,
			Harnesses: harnesses, DisabledHarnesses: disabled, Applications: roleSettingsApplications{}})
		if err != nil {
			t.Fatal(err)
		}
		defer r.Close(context.Background())
		initial, revision, err := r.Settings()
		if err != nil {
			t.Fatal(err)
		}
		initial.Moku.HostHarnessPreference = id
		initial.Moku.ExecutionHarnesses = profiles
		retainedProfiles := map[string]json.RawMessage{id: raw(map[string]int{"model": 99})}
		for _, role := range roles {
			value := map[string]any{"mode": "inherit"}
			if retained && role == roles[0] {
				value["independent"] = map[string]any{"harnessPreference": id, "harnesses": retainedProfiles}
			}
			initial.PluginSettings = append(initial.PluginSettings, model.PluginSettings{ID: role, SchemaVersion: 1, Value: raw(value)})
		}
		if _, err := db.Update(ctx, func(tx *store.Tx) error { return tx.Put("settings", initial) }); err != nil {
			t.Fatal(err)
		}
		for i, role := range roles {
			result, err := r.Invoke(ctx, "harness:settings-presentation", []json.RawMessage{raw(map[string]any{
				"scope": "global", "harnessId": id, "applicationSettings": role, "previewIndependent": true,
			})})
			if err != nil {
				t.Fatal(err)
			}
			source := profiles[id]
			if retained && i == 0 {
				source = retainedProfiles[id]
			}
			if source == nil {
				source = harnesses[id].DefaultSettings()
			}
			owner, template, _ := (roleSettingsApplications{}).BackgroundSettingsWorkspace(role)
			want := raw(map[string]any{"cwd": filepath.Join(root, "plugins", owner, template), "source": source, "executionProfile": true})
			if string(result.(map[string]any)["value"].(json.RawMessage)) != string(want) {
				t.Fatalf("wrong preflight workspace or source for %s", role)
			}
		}
		if _, rev, err := r.Settings(); err != nil || rev != revision {
			t.Fatalf("preflight changed settings revision: %d, %v", rev, err)
		}

		save := func(settings model.Settings, revision int64) (core.SettingsResult, error) {
			value, err := r.Invoke(ctx, "app:update-settings", []json.RawMessage{raw(map[string]any{
				"settings": settings, "expectedSettingsRevision": revision,
			})})
			if err != nil {
				return core.SettingsResult{}, err
			}
			return value.(core.SettingsResult), nil
		}
		draft := func(base model.Settings, index int, harness string) model.Settings {
			base.PluginSettings = append([]model.PluginSettings(nil), base.PluginSettings...)
			copied := profiles
			if retained && index == 0 {
				copied = retainedProfiles
			}
			base.PluginSettings[index].Value = raw(map[string]any{"mode": "override", "harnessPreference": harness, "harnesses": copied})
			return base
		}
		if _, err := save(draft(initial, 0, "unknown"), revision); err == nil {
			t.Fatal("unknown selected Harness was accepted")
		}
		start := make(chan struct{})
		type write struct {
			index  int
			result core.SettingsResult
			err    error
		}
		writes := make(chan write, len(roles))
		for i := range roles {
			go func() {
				<-start
				result, err := save(draft(initial, i, id), revision)
				writes <- write{i, result, err}
			}()
		}
		close(start)
		first, second := <-writes, <-writes
		if first.result.Status == "conflict" {
			first, second = second, first
		}
		if first.err != nil || second.err != nil || first.result.Status != "saved" || second.result.Status != "conflict" ||
			first.result.SettingsRevision != revision+1 || string(raw(first.result.Settings)) != string(raw(second.result.Settings)) {
			t.Fatalf("same-revision saves did not converge: %+v / %+v", first, second)
		}
		want := draft(draft(initial, first.index, id), second.index, id)
		retry, err := save(draft(second.result.Settings, second.index, id), second.result.SettingsRevision)
		if err != nil || retry.Status != "saved" || retry.SettingsRevision != revision+2 {
			t.Fatalf("retry failed to retain both profiles: %s / %v", retry.Status, err)
		}
		for i, entry := range want.PluginSettings {
			if string(retry.Settings.PluginSettings[i].Value) != string(entry.Value) {
				t.Fatalf("retry changed %s: got %s, want %s", entry.ID, retry.Settings.PluginSettings[i].Value, entry.Value)
			}
		}
		if string(raw(retry.Settings.Moku.ExecutionHarnesses)) != string(raw(profiles)) {
			t.Fatal("role save changed Chief's execution profiles")
		}
		unchanged, err := save(retry.Settings, retry.SettingsRevision)
		if err != nil || unchanged.Status != "saved" || unchanged.SettingsRevision != retry.SettingsRevision {
			t.Fatalf("unchanged save advanced the revision: %+v / %v", unchanged, err)
		}
		if count := snapshots.Load(); count != 0 {
			t.Fatalf("preview or save acquired %d native snapshots", count)
		}
		if cold {
			next, err := r.EnsureExecutionSettings(ctx, id, roles[1])
			var binding struct{ Harnesses map[string]json.RawMessage }
			if err != nil || json.Unmarshal(next.PluginSettings[1].Value, &binding) != nil ||
				string(binding.Harnesses[id]) != `{"captured":1}` || len(binding.Harnesses) != len(profiles)+1 ||
				string(next.PluginSettings[0].Value) != string(retry.Settings.PluginSettings[0].Value) || snapshots.Load() != 1 {
				t.Fatalf("cold admission did not capture only the missing slot: %v", err)
			}
		}
	})
}
