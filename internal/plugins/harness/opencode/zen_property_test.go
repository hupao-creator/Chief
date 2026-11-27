package opencode

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/hupao-creator/Chief/internal/plugins/harness/opencode/accounttelemetry"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

func TestZenBillingTelemetryProperties(t *testing.T) {
	rapidcheck.Check(t, func(rt *rapid.T) {
		fault := rapid.SampledFrom([]string{
			"", "key-only", "foreign-route", "go-route", "other-integration", "duplicate", "override",
			"describe-route-changed", "lease-changed", "expired-lease", "expires-after-verification", "lease-org-override", "org-conflict", "wrong-workspace",
			"unauthorized", "redirect", "missing-balance", "malformed-balance", "invoiced", "subscription-mode",
		}).Draw(rt, "billing-or-binding")
		whole := rapid.Int64Range(0, 100_000_000_000).Draw(rt, "whole-dollars")
		fraction := rapid.IntRange(0, 99_999_999).Draw(rt, "fraction-of-dollar")
		if rapid.Bool().Draw(rt, "zero-balance") {
			whole, fraction = 0, 0
		}
		billing := Object{"billingMode": "prepaid", "mode": "pay-as-you-go",
			"balanceMicroCents": fmt.Sprintf("%d%08d", whole, fraction),
			"budgetMicroCents":  "999999999999999999", "availableMicroCents": "123"}
		switch fault {
		case "missing-balance":
			delete(billing, "balanceMicroCents")
		case "malformed-balance":
			billing["balanceMicroCents"] = rapid.SampledFrom([]any{nil, 0, "0.0", "1e8", ""}).Draw(rt, "malformed-amount")
		case "invoiced":
			billing["billingMode"] = "invoiced"
		case "subscription-mode":
			billing["mode"] = "subscription"
		}
		peer := quotaPeer{account: "zen", oauth: fault != "key-only", percent: 37,
			zen: &zenQuotaFixture{only: rapid.Bool().Draw(rt, "Zen-only"), fault: fault, billing: billing}}
		if fault == "expires-after-verification" {
			peer.zen.only = true
		}
		if !peer.zen.only && rapid.Bool().Draw(rt, "failed-Go-status") {
			peer.fault = "remote-error"
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		native := &Runtime{URL: "http://native", ctx: ctx, client: &http.Client{Transport: quotaTransport(peer.native)}}
		var billingRequests, unsafeRequests atomic.Int32
		var workspaceRead atomic.Bool
		remote := quotaTransport(func(req *http.Request) (*http.Response, error) {
			if req.URL.Host != "models.dev" && (req.URL.Host != "opencode.ai" || req.URL.Scheme != "https" || req.Method != "GET" || req.Header.Get("Cookie") != "") {
				unsafeRequests.Add(1)
			}
			if strings.HasPrefix(req.URL.Path, "/console/") && (!peer.oauth || req.Header.Get("x-org-id") != "org_zen" || req.Header.Get("Authorization") != "Bearer fixture-secret-zen") {
				unsafeRequests.Add(1)
			}
			if req.URL.Path == "/console/api/billing/status" {
				billingRequests.Add(1)
			}
			if req.URL.Path == "/console/api/orgs/current" {
				workspaceRead.Store(true)
			}
			return peer.remote(req)
		})
		now := func() time.Time {
			if fault == "expires-after-verification" && workspaceRead.Load() {
				return quotaNow.Add(time.Hour)
			}
			return quotaNow
		}
		snapshot, err := readAccountTelemetry(ctx, native, accounttelemetry.ClientOptions{HTTP: &http.Client{Transport: remote}, Now: now})
		if err != nil {
			rt.Fatal(err)
		}
		if unsafeRequests.Load() != 0 || strings.Contains(formatTelemetry(snapshot), "fixture-secret-") {
			rt.Fatal("Zen probe used or exposed credentials outside its verified Console destination")
		}
		if fault == "expires-after-verification" && !workspaceRead.Load() {
			rt.Fatal("live lease did not reach workspace verification")
		}
		reading := object(snapshot["zen"])
		balance := object(reading["balance"])
		if fault == "" {
			want := strings.TrimRight(strings.TrimRight(fmt.Sprintf("%d.%08d", whole, fraction), "0"), ".")
			if reading["availability"] != "available" || balance["currency"] != "USD" || balance["total"] != want {
				rt.Fatalf("expected exact Zen balance USD %s, got %v", want, reading)
			}
		} else if reading["availability"] != "unknown" || reading["balance"] != nil {
			rt.Fatalf("unverified Zen balance for %s: %v", fault, reading)
		}
		var wantRequests int32
		switch fault {
		case "", "unauthorized", "redirect", "missing-balance", "malformed-balance", "invoiced", "subscription-mode":
			wantRequests = 1
		}
		if billingRequests.Load() != wantRequests {
			rt.Fatalf("expected %d billing requests, got %d", wantRequests, billingRequests.Load())
		}
		if snapshot["balances"] != nil || object(snapshot["console"])["balance"] != nil {
			rt.Fatal("Zen credits leaked into the Go subscription reading")
		}
		goAvailability, goWindows := "available", 1
		switch {
		case peer.zen.only:
			goAvailability, goWindows = "unknown", 0
		case peer.fault == "remote-error" || peer.oauth && fault == "wrong-workspace":
			goAvailability, goWindows = "error", 0
		}
		if snapshot["availability"] != goAvailability || len(array(snapshot["windows"])) != goWindows {
			rt.Fatalf("expected Go state %s with %d windows, got %v", goAvailability, goWindows, snapshot)
		}
	})
}

type zenQuotaFixture struct {
	only    bool
	fault   string
	billing Object
}

func (z zenQuotaFixture) provider() Object {
	provider := Object{"id": "opencode", "integrationID": "opencode", "package": "@opencode/ai/providers/openai-compatible",
		"settings": Object{"baseURL": "https://opencode.ai/zen/v1"}}
	switch z.fault {
	case "foreign-route":
		provider["settings"] = Object{"baseURL": "https://opencode.ai.example.org/zen/v1"}
	case "go-route":
		provider["settings"] = Object{"baseURL": quotaRoute}
	case "other-integration":
		provider["integrationID"] = "other"
	case "override":
		provider["headers"] = Object{"Authorization": "Bearer fixture-secret-override"}
	case "org-conflict":
		provider["headers"] = Object{"x-org-id": "org_elsewhere"}
	}
	return provider
}

func (z zenQuotaFixture) native(path string, input Object, account string, oauth bool) (*http.Response, error) {
	output := Object{}
	if path != "/api/rpc/chief.harness/consoleAccount" {
		return quotaReply(404, nil)
	}
	if oauth {
		switch input["phase"] {
		case "describe":
			output = Object{"provider": z.provider(), "sourceCredentialID": account}
			if input["sourceCredentialID"] != nil {
				switch z.fault {
				case "lease-changed":
					output["sourceCredentialID"] = "elsewhere"
				case "describe-route-changed":
					object(output["provider"])["settings"] = Object{"baseURL": quotaRoute}
				}
			}
		case "lease":
			if input["sourceCredentialID"] != account {
				return quotaReply(400, nil)
			}
			expires := quotaNow.Add(time.Hour)
			if z.fault == "expired-lease" {
				expires = quotaNow
			}
			output["lease"] = Object{"type": "oauth", "methodID": "oauth", "access": "fixture-secret-" + account, "expires": expires.UnixMilli(),
				"metadata": Object{"orgID": "org_" + account}}
			if z.fault == "lease-org-override" {
				output["configuration"] = Object{"orgID": "org_elsewhere"}
			}
		}
	}
	return quotaReply(200, Object{"output": output})
}

func (z zenQuotaFixture) billingReply() (*http.Response, error) {
	switch z.fault {
	case "unauthorized":
		return quotaReply(401, z.billing)
	case "redirect":
		res, err := quotaReply(302, z.billing)
		res.Header = http.Header{"Location": []string{"https://foreign.example/console/api/billing/status"}}
		return res, err
	default:
		return quotaReply(200, z.billing)
	}
}
