package codex

import (
	"context"
	"fmt"
	"slices"
	"strings"
	"testing"

	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

type tierCatalog struct{ models []Map }

func (p tierCatalog) Call(_ context.Context, method string, _ any) (Map, error) {
	if method != "model/list" {
		return nil, fmt.Errorf("unexpected method %s", method)
	}
	return Map{"data": p.models, "nextCursor": nil}, nil
}

func TestExecutionServiceTierProperties(t *testing.T) {
	rapidcheck.Check(t, func(t *rapid.T) {
		ids := rapid.Permutation([]string{"priority", "ultrafast", "fast", "custom"}).Draw(t, "catalog order")
		ids = ids[:rapid.IntRange(0, len(ids)).Draw(t, "catalog size")]
		tiers := []Map{}
		for _, id := range ids {
			// A display label alone must never confer Fast support.
			tiers = append(tiers, Map{"id": id, "name": "Fast"})
		}
		models, err := ListModels(context.Background(), tierCatalog{models: []Map{
			{"model": "astra", "supportsReasoning": false, "serviceTiers": tiers},
			{"model": "other", "serviceTiers": []Map{{"id": "priority"}}},
		}})
		if err != nil {
			t.Fatal(err)
		}
		// Build the accepted import spellings from the selected inventory.
		imports := map[string]string{"default": "default"}
		if slices.Contains(ids, "priority") {
			imports["fast"] = "priority"
		}
		for _, id := range ids {
			imports[id] = id
		}
		for _, pinned := range []string{"", "default", "priority", "ultrafast", "fast", "unknown"} {
			for _, native := range []string{"fast", "default", "priority", "ultrafast", "unknown"} {
				observed := Map{"models": models, "configuration": Map{"model": "astra", "service_tier": native}}
				current := Map{"model": "astra", "permissionMode": "full-access"}
				want := pinned
				if pinned != "" {
					current["serviceTier"] = pinned
				} else {
					want = imports[native]
				}
				got, err := executionThreadSettings(current, observed, true)
				if want != "default" && !slices.Contains(ids, want) {
					if err == nil || !strings.Contains(err.Error(), "does not report support for service tier") {
						t.Fatalf("tiers %v, pin %q, config %q: expected unsupported tier, got %v, %v", ids, pinned, native, got, err)
					}
					continue
				}
				if err != nil || got["serviceTier"] != want {
					t.Fatalf("tiers %v, pin %q, config %q: want %s, got %v, %v", ids, pinned, native, want, got, err)
				}
				// A later execution validates the retained profile without config/read.
				retained, err := executionThreadSettings(got, Map{"models": models}, false)
				if err != nil || retained["serviceTier"] != want {
					t.Fatalf("pinned tier %s: got %v, %v", want, retained, err)
				}
			}
		}
	})
}
