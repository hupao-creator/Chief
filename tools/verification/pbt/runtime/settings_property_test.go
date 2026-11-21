package runtime_test

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/hupao-creator/Chief/internal/core/plugin"
	core "github.com/hupao-creator/Chief/internal/core/runtime"
	"github.com/hupao-creator/Chief/internal/core/store"
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
	saves, reads settingsCall
}

func (s delayedSettings) SnapshotExecution(ctx context.Context, r plugin.SettingsRequest, initial bool) (json.RawMessage, error) {
	if !initial {
		if err := s.saves.await(ctx); err != nil {
			return nil, err
		}
	}
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
		native := delayedSettings{saves: make(settingsCall), reads: make(settingsCall)}
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
			saved := make(chan error, 1)
			go func() {
				result, err := r.UpdateSettings(ctx, revision, next)
				if err == nil && result.Status != "saved" {
					err = errors.New("save conflicted with read")
				}
				saved <- err
			}()
			commit := arrival(native.saves)
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
				close(commit)
				if err := <-saved; err != nil {
					t.Fatal(err)
				}
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
				close(commit)
				if err := <-saved; err != nil {
					t.Fatal(err)
				}
			}
			current, rev, err := r.Settings()
			if err != nil || rev != revision+1 || string(current.Moku.ExecutionHarnesses["fixture"]) != string(next.Moku.ExecutionHarnesses["fixture"]) {
				t.Fatalf("read changed saved settings/revision: %v", err)
			}
		}
	})
}
