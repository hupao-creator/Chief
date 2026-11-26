package dispatchconfig

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/hupao-creator/Chief/internal/core/store"

	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

func snapshot(model string) json.RawMessage {
	models := []map[string]any{}
	if model != "" {
		models = append(models, map[string]any{"id": model, "defaultServiceTier": nil, "body": map[string]string{"secret": "private-canary"}})
	}
	b, _ := json.Marshal(map[string]any{"cli": map[string]any{"status": "ready", "message": "provider notice"}, "models": models})
	return b
}
func load(b json.RawMessage, err error) Acquire {
	return func(context.Context) (json.RawMessage, json.RawMessage, error) { return b, nil, err }
}

// PBT-DISPATCH-PUBLICATION: README.md
func TestDispatchPublicationProperties(t *testing.T) {
	rapidcheck.Check(t, func(t *rapid.T) {
		root, err := os.MkdirTemp("", "chief-dispatch-")
		if err != nil {
			t.Fatal(err)
		}
		defer os.RemoveAll(root)
		file := filepath.Join(root, "state.sqlite")
		db, err := store.Open(file)
		if err != nil {
			t.Fatal(err)
		}
		defer func() { _ = db.Close() }()
		c := New(db, root)
		changes, stop := c.Subscribe()
		defer func() { stop() }()
		<-changes
		expected := map[string]string{}
		ctx := context.Background()
		steps := rapid.SliceOfN(rapid.IntRange(0, 6), 2, 24).Draw(t, "actions")
		for _, step := range steps {
			id := rapid.SampledFrom([]string{"alpha", "beta"}).Draw(t, "provider")
			previous, had := expected[id]
			var update Acquire
			switch step {
			case 0, 1:
				model := fmt.Sprintf("model-%d", rapid.IntRange(1, 3).Draw(t, "visible"))
				expected[id] = model
				update = load(snapshot(model), nil)
			case 2:
				expected[id] = ""
				update = load(snapshot(""), nil)
			case 3:
				update = load(nil, errors.New("account identity schema is unavailable"))
			case 4:
				update = load(json.RawMessage(`{"cli":{"status":"unavailable"},"models":[]}`), nil)
			case 5:
				stop()
				if err := db.Close(); err != nil {
					t.Fatal(err)
				}
				db, err = store.Open(file)
				if err != nil {
					t.Fatal(err)
				}
				c = New(db, root)
				changes, stop = c.Subscribe()
				<-changes
			case 6: // A later source wins even if the old native read ignores cancellation.
				entered, release, finished := make(chan struct{}), make(chan struct{}), make(chan error, 1)
				go func() {
					_, err := c.Update(ctx, id, "old", func(context.Context) (json.RawMessage, json.RawMessage, error) {
						close(entered)
						<-release
						return snapshot("obsolete"), nil, nil
					}, nil)
					finished <- err
				}()
				<-entered
				expected[id] = "new"
				_, err = c.Update(ctx, id, "new", load(snapshot("new"), nil), nil)
				close(release)
				if err != nil {
					t.Fatal(err)
				}
				if <-finished == nil {
					t.Fatal("superseded publisher succeeded")
				}
			}
			if update != nil {
				_, err = c.Update(ctx, id, "source", update, nil)
				if err != nil && step != 3 {
					t.Fatal(err)
				}
			}
			_, now := expected[id]
			changed := now && (!had || previous != expected[id])
			select {
			case <-changes:
				if !changed {
					t.Fatal("unrelated or identical update woke subscriber")
				}
			default:
				if changed {
					t.Fatal("missing publication notification")
				}
			}
			if raw := New(db, filepath.Join(root, "another-workspace")).Options([]string{id}); string(raw) != "{}" {
				t.Fatal("another workspace inherited a publication")
			}
			raw := c.Options([]string{"alpha", "beta"})
			var actual map[string][]struct{ Model string }
			if err := json.Unmarshal(raw, &actual); err != nil {
				t.Fatal(err)
			}
			if len(actual) != len(expected) {
				t.Fatalf("presence changed: %s; want %v", raw, expected)
			}
			for key, want := range expected {
				options, ok := actual[key]
				if !ok || want == "" && len(options) != 0 || want != "" && (len(options) != 1 || options[0].Model != want) {
					t.Fatalf("provider %s: got %s, want %q", key, raw, want)
				}
				presentation := c.Read(key).Presentation
				if !bytes.Contains(presentation, []byte(`"message":"provider notice"`)) || (want != "" && !bytes.Contains(presentation, []byte(`"defaultServiceTier":null`))) {
					t.Fatal("settings presentation lost its provider notice or explicit standard tier")
				}
				if bytes.Contains(presentation, []byte("private-canary")) {
					t.Fatal("private provider field persisted")
				}
			}
		}
	})
}
