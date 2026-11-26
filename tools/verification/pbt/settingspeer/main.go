// settingspeer serves one mounted property command in its disposable working
// directory. Each invocation reopens the real SQLite profile and Runtime.
// Only native discovery, catalog replies and imported defaults are scripted.
package main

import (
	"context"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/hupao-creator/Chief/internal/core/plugin"
	core "github.com/hupao-creator/Chief/internal/core/runtime"
	"github.com/hupao-creator/Chief/internal/core/store"
	"github.com/hupao-creator/Chief/internal/plugins/harness/claude"
	"github.com/hupao-creator/Chief/internal/plugins/harness/codex"
	"github.com/hupao-creator/Chief/internal/plugins/harness/opencode"
	"github.com/hupao-creator/Chief/internal/plugins/harness/pi"
)

// v0.1.0-alpha.2 settings wire format, installed before current Runtime initialization.
//
//go:embed alpha-settings.json
var alphaSettings json.RawMessage

type native struct {
	plugin.HarnessSettings
	id          string
	failCatalog bool
}

func (n native) SnapshotExecution(context.Context, plugin.SettingsRequest, bool) (json.RawMessage, error) {
	profiles := map[string]string{
		"codex":    `{"model":"chat","effort":"low","serviceTier":"default","permissionMode":"ask-for-approval"}`,
		"claude":   `{"model":"chat","effort":"low","permissionMode":"auto"}`,
		"pi":       `{"provider":"local","model":"chat","thinkingLevel":"low"}`,
		"opencode": `{"provider":"local","model":"chat","variant":"default","agent":"build","permissionMode":"auto"}`,
	}
	return json.RawMessage(`{"useDefaultThreadSettings":false,"threadSettings":` + profiles[n.id] + `}`), nil
}

//go:embed catalogs.json
var catalogJSON []byte

func (n native) Presentation(context.Context, plugin.SettingsPresentationRequest) (json.RawMessage, error) {
	if n.failCatalog {
		return nil, errors.New("fixture catalog unavailable")
	}
	var catalogs map[string]json.RawMessage
	if err := json.Unmarshal(catalogJSON, &catalogs); err != nil {
		return nil, err
	}
	return catalogs[n.id], nil
}

type harness struct {
	plugin.Harness
	failProbe   string
	failCatalog string
}

func (h harness) Settings() plugin.HarnessSettings {
	return native{HarnessSettings: h.Harness.Settings(), id: h.Descriptor().ID, failCatalog: h.failCatalog == h.Descriptor().ID}
}
func (h harness) Detect(context.Context, string) (plugin.Installation, error) {
	if h.failProbe == h.Descriptor().ID {
		return plugin.Installation{}, errors.New("fixture detection failed")
	}
	return plugin.Installation{Status: "installed"}, nil
}

func run() error {
	var request struct {
		Channel     string
		Args        []json.RawMessage
		FailProbe   string
		FailCatalog string
	}
	if err := json.NewDecoder(os.Stdin).Decode(&request); err != nil {
		return err
	}
	root, err := os.Getwd()
	if err != nil {
		return err
	}
	if home, err := filepath.EvalSymlinks(os.Getenv("HOME")); err != nil || home != root {
		return errors.New("settingspeer requires an isolated working directory and matching HOME")
	}
	db, err := store.Open(filepath.Join(root, "state.sqlite"))
	if err != nil {
		return err
	}
	defer db.Close()
	ctx := context.Background()
	if request.Channel == "fixture:alpha-profile" {
		_, err = db.Update(ctx, func(tx *store.Tx) error {
			if tx.Has("settings") {
				return errors.New("Alpha fixture requires an empty profile")
			}
			if err := tx.Put("settings", alphaSettings); err != nil {
				return err
			}
			return tx.Put("settings-revision", 7)
		})
		if err != nil {
			return err
		}
		request.Channel = "state:load"
	}
	host := plugin.HostContext{HarnessDataRoot: root, TemporaryWorkspaceRoot: root}
	adapters := map[string]plugin.Harness{}
	for _, h := range []plugin.Harness{codex.New(host), claude.New(host), pi.New(host), opencode.New(host)} {
		adapters[h.Descriptor().ID] = harness{Harness: h, failProbe: request.FailProbe, failCatalog: request.FailCatalog}
	}
	r, err := core.New(ctx, core.Config{Store: db, DataDir: root, DefaultCwd: root, Harnesses: adapters})
	if err != nil {
		return err
	}
	defer r.Close(ctx)
	result, err := r.Invoke(ctx, request.Channel, request.Args)
	if err != nil {
		return err
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
