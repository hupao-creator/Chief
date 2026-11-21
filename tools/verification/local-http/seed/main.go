// Seed a new benchmark profile before the first process opens it. Only the
// fixture Claude peer is enabled, including during runtime startup recovery.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/store"
)

func main() {
	if err := seed(os.Args[1]); err != nil {
		panic(err)
	}
}

func seed(path string) error {
	if err := os.Mkdir(path, 0700); err != nil {
		return err
	}
	db, err := store.Open(filepath.Join(path, "chief-go-state-v1", "state.sqlite"))
	if err != nil {
		return err
	}
	s := model.DefaultSettings([]string{"claude", "codex", "opencode", "pi"})
	for id := range s.Harnesses {
		s.Harnesses[id] = json.RawMessage(`{"threadSettings":{}}`)
	}
	s.Moku.TargetHarnessIDs = []string{"claude"}
	s.Moku.HostHarnessPreference = "claude"
	s.PluginEnabled = map[string]bool{"harness:codex": false, "harness:pi": false, "harness:opencode": false, "context:artificial-analysis": false, "extension:tag": false, "extension:report": false}
	_, err = db.Update(context.Background(), func(tx *store.Tx) error {
		if err := tx.Put("settings", s); err != nil {
			return err
		}
		return tx.Put("settings-revision", int64(1))
	})
	return errors.Join(err, db.Close())
}
