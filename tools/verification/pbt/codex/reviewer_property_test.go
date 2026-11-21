package codex_test

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"testing"

	"github.com/hupao-creator/Chief/internal/plugins/harness/codex"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

type reviewerProbe struct {
	config, requirements codex.Map
	readError            bool
}

func (p reviewerProbe) Call(_ context.Context, method string, _ any) (codex.Map, error) {
	switch method {
	case "config/read":
		return codex.Map{"config": p.config}, nil
	case "configRequirements/read":
		if p.readError {
			return nil, errors.New("requirements unavailable")
		}
		return codex.Map{"requirements": p.requirements}, nil
	default:
		return nil, fmt.Errorf("unexpected probe %q", method)
	}
}

// PBT-CODEX-REVIEWER exercises the native read boundary without changing a Mac's managed policy.
func TestCodexReviewerProperties(t *testing.T) {
	rapidcheck.Check(t, func(t *rapid.T) {
		version := rapid.SampledFrom([]string{"0.153.3", "0.153.4", "0.171.0"}).Draw(t, "version")
		initialized := codex.Map{"userAgent": "codex/" + version}
		policy := rapid.SampledFrom([]string{"unrestricted", "list", "read-error"}).Draw(t, "requirements")
		allowed := rapid.SliceOfN(rapid.SampledFrom([]string{"user", "auto_review"}), 0, 3).Draw(t, "allowed")
		peer := reviewerProbe{readError: policy == "read-error"}
		if policy == "list" {
			peer.requirements = codex.Map{"allowedApprovalsReviewers": allowed}
		}
		eligible := version != "0.153.3" && (policy == "unrestricted" || policy == "list" && slices.Contains(allowed, "auto_review"))
		for _, reviewer := range []any{nil, "user", "auto_review", "unknown"} {
			peer.config = codex.Map{"approvals_reviewer": reviewer}
			got, err := codex.SupportsAutoReview(context.Background(), peer, "", initialized)
			if err != nil || got != (eligible && reviewer != "unknown") {
				t.Fatalf("reviewer %v, policy %s %v: got %v, error %v", reviewer, policy, allowed, got, err)
			}
		}
		peer.config = codex.Map{}
		if got, err := codex.SupportsAutoReview(context.Background(), peer, "", initialized); err != nil || got {
			t.Fatalf("missing reviewer field: got %v, error %v", got, err)
		}
	})
}
