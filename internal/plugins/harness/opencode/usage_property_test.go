package opencode

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/hupao-creator/Chief/internal/core/plugin"
	"github.com/hupao-creator/Chief/internal/platform/sqlite"
	"github.com/hupao-creator/Chief/internal/plugins/harness/opencode/accounttelemetry"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

type quotaTransport func(*http.Request) (*http.Response, error)

type failingQuotaLedger struct{ failRecord bool }

func (f failingQuotaLedger) Record(context.Context, json.RawMessage) error {
	if f.failRecord {
		return errors.New("fixture-secret-ledger-write")
	}
	return nil
}

func (failingQuotaLedger) Read(context.Context) (json.RawMessage, error) {
	return nil, errors.New("fixture-secret-ledger-read")
}

func (f quotaTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func quotaReply(status int, value any) (*http.Response, error) {
	data, err := json.Marshal(value)
	if err != nil {
		return nil, err
	}
	return &http.Response{StatusCode: status, Body: io.NopCloser(strings.NewReader(string(data)))}, nil
}

// Both HTTP peers are scripted. Source fingerprints, native RPC selection,
// remote response parsing, cache publication and the contributor are production.
func TestGoAccountTelemetryProperties(t *testing.T) {
	rapidcheck.Check(t, func(rt *rapid.T) {
		check := func(err error) {
			rt.Helper()
			if err != nil {
				rt.Fatal(err)
			}
		}
		root := t.TempDir()
		database := filepath.Join(root, "opencode.db")
		db, err := sqlite.Open(database, false)
		check(err)
		defer db.Close()
		check(db.Exec("CREATE TABLE credential(id TEXT, integration_id TEXT, active INTEGER, connector_id TEXT, method_id TEXT, time_updated INTEGER)"))
		selectAccount := func(id string) {
			check(db.Exec("UPDATE credential SET active = (id = ?), time_updated = time_updated + 1", id))
		}
		for _, id := range []string{"A", "B", "late", "invalid"} {
			check(db.Exec("INSERT INTO credential VALUES(?, 'opencode', 0, 'native', 'key', 0)", id))
		}
		selectAccount("A")
		executable := filepath.Join(root, "opencode")
		check(os.WriteFile(executable, nil, 0700))
		h := New(plugin.HostContext{Environment: func(context.Context) (map[string]string, error) {
			return map[string]string{"HOME": root, "PATH": root, "OPENCODE_DB": database}, nil
		}})
		defer h.Close()
		percentA := rapid.IntRange(0, 48).Draw(rt, "A-percent")
		percentB := rapid.IntRange(52, 100).Draw(rt, "B-percent")
		faults := []string{"foreign", "zen", "conflicting-org", "other-integration", "duplicate", "rpc-error", "remote-error", "no-meter"}
		block := make(chan struct{})
		started := make(chan struct{})
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		oauth := rapid.Bool().Draw(rt, "Console-OAuth")
		latePath := "/zen/go/v1/usage"
		if oauth {
			faults = append(faults, "switched-lease", "wrong-workspace")
			latePath = rapid.SampledFrom([]string{"/console/api/go/status", "/console/api/billing/status"}).Draw(rt, "late-Console-reading")
		}
		invalid := rapid.SampledFrom(faults).Draw(rt, "invalid-binding-or-reply")
		var invalidRemoteCalls atomic.Int32
		h.readTelemetry = func(ctx context.Context, opts Options) (Object, error) {
			rows, err := db.Query("SELECT id FROM credential WHERE active = 1")
			if err != nil {
				return nil, err
			}
			account := ""
			if len(rows) == 1 {
				account = rows[0]["id"].(string)
			}
			peer := quotaPeer{account: account, oauth: oauth, percent: percentA}
			if account == "B" {
				peer.percent = percentB
			}
			if account == "invalid" {
				peer.fault = invalid
			} else if oauth && account != "" {
				peer.zen = &zenQuotaFixture{billing: Object{"billingMode": "prepaid", "mode": "pay-as-you-go", "balanceMicroCents": fmt.Sprintf("%d00000000", peer.percent)}}
			}
			native := &Runtime{URL: "http://native", ctx: ctx, client: &http.Client{Transport: quotaTransport(peer.native)}, options: opts}
			remote := quotaTransport(func(req *http.Request) (*http.Response, error) {
				if account == "invalid" {
					invalidRemoteCalls.Add(1)
				}
				if !oauth && strings.HasPrefix(req.URL.Path, "/console/") {
					t.Error("Go API key reached the Console API")
				}
				if account == "late" && req.URL.Path == latePath {
					close(started)
					select {
					case <-block:
					case <-ctx.Done():
						return nil, ctx.Err()
					}
				}
				return peer.remote(req)
			})
			return readAccountTelemetry(ctx, native, accounttelemetry.ClientOptions{HTTP: &http.Client{Transport: remote}, Now: func() time.Time { return quotaNow }})
		}
		request := plugin.SettingsRequest{Cwd: root, Settings: h.DefaultSettings()}
		var ledger plugin.TelemetryLedger
		read := func() Object {
			raw, err := h.MokuContext(ctx, "telemetry", request, ledger)
			check(err)
			if strings.Contains(raw, "fixture-secret-") {
				rt.Fatal("credential in public telemetry")
			}
			var snapshot Object
			check(json.Unmarshal([]byte(raw), &snapshot))
			return snapshot
		}
		settled := func() Object { read(); h.workers.Wait(); return read() }
		window := func(s Object, pct int) string {
			ws := array(s["windows"])
			if s["availability"] != "available" || len(ws) != 1 || object(ws[0])["usedPercent"] != float64(pct) {
				rt.Fatalf("expected verified %d%% window, availability=%v windows=%d", pct, s["availability"], len(ws))
			}
			if oauth && object(object(s["zen"])["balance"])["total"] != fmt.Sprint(pct) {
				rt.Fatalf("expected separate Zen balance for the selected workspace, got %v", s["zen"])
			}
			return str(object(ws[0])["id"])
		}
		empty := func(s Object, availability string) {
			if s["availability"] != availability || len(array(s["windows"])) != 0 {
				rt.Fatalf("expected empty %s reading, got %v", availability, s["availability"])
			}
			if zen := object(s["zen"]); zen["availability"] != "unknown" || zen["balance"] != nil {
				rt.Fatal("unverified source supplied a Zen balance")
			}
		}
		a := window(settled(), percentA)
		model := rapid.StringMatching("[a-z][a-z0-9-]{0,12}").Draw(rt, "non-Go-model")
		request.Settings = json.RawMessage(fmt.Sprintf(`{"threadSettings":{"provider":"external","model":%q}}`, model))
		if window(read(), percentA) != a {
			rt.Fatal("model change lost the account window")
		}
		selectAccount("late")
		empty(read(), "unknown")
		select {
		case <-started:
		case <-ctx.Done():
			rt.Fatal("old read did not start")
		}
		selectAccount("B")
		empty(read(), "unknown")
		// B can finish and become visible before the superseded read returns.
		var b Object
		for {
			b = read()
			if b["availability"] == "available" {
				break
			}
			if ctx.Err() != nil {
				rt.Fatal("B never published")
			}
			time.Sleep(time.Millisecond)
		}
		bID := window(b, percentB)
		if bID == a {
			rt.Fatal("accounts shared window identity")
		}
		close(block)
		h.workers.Wait()
		if window(read(), percentB) != bID {
			rt.Fatal("late read displaced B")
		}
		// A broken config dependency prevents source verification even if the
		// credential rows and selected model are unchanged.
		broken := filepath.Join(root, "opencode.json")
		check(os.Symlink(filepath.Join(root, "missing"), broken))
		empty(read(), "error")
		check(os.Remove(broken))
		selectAccount("")
		empty(read(), "unknown")
		empty(settled(), "unknown")
		selectAccount("invalid")
		status := "unknown"
		if invalid == "rpc-error" || invalid == "remote-error" || invalid == "switched-lease" || invalid == "wrong-workspace" {
			status = "error"
		}
		empty(settled(), status)
		if invalid != "remote-error" && invalid != "no-meter" && invalid != "wrong-workspace" && invalidRemoteCalls.Load() != 0 {
			rt.Fatal("unverified binding contacted remote telemetry")
		}
		if oauth {
			ledger = failingQuotaLedger{failRecord: rapid.Bool().Draw(rt, "fail-ledger-write-before-read")}
			selectAccount("A")
			empty(read(), "unknown")
			s := settled()
			if s["availability"] != "error" || len(array(s["windows"])) != 0 ||
				object(object(s["zen"])["balance"])["total"] != fmt.Sprint(percentA) {
				rt.Fatal("Go ledger failure lost the verified Zen balance or published unverified Go usage")
			}
		}
	})
}

var quotaNow = time.Date(2026, 11, 23, 0, 0, 0, 0, time.UTC)

const quotaRoute = "https://opencode.ai/inference/go/openai/v1"

type quotaPeer struct {
	account, fault string
	oauth          bool
	percent        int
	zen            *zenQuotaFixture
}

func (p quotaPeer) native(req *http.Request) (*http.Response, error) {
	provider := Object{"id": "opencode-go", "integrationID": "opencode", "package": "@opencode/ai/providers/openai-compatible", "settings": Object{"baseURL": quotaRoute}}
	switch p.fault {
	case "foreign":
		provider["settings"] = Object{"baseURL": "https://example.org/zen/go/v1"}
	case "zen":
		provider["settings"] = Object{"baseURL": "https://opencode.ai/zen/v1"}
	case "conflicting-org":
		provider["headers"] = Object{"x-org-id": "org_elsewhere"}
	case "other-integration":
		provider["integrationID"] = "other"
	}
	if req.URL.Path == "/api/provider" {
		rows := []Object{{"id": "opencode", "integrationID": "opencode"}, provider}
		if p.zen != nil {
			rows[0] = p.zen.provider()
			if p.zen.only {
				rows = rows[:1]
			}
			if p.zen.fault == "duplicate" {
				rows = append(rows, rows[0])
			}
		}
		if p.fault == "duplicate" {
			rows = append(rows, provider)
		}
		return quotaReply(200, rows)
	}
	var in struct{ Input Object }
	if req.Body == nil || json.NewDecoder(req.Body).Decode(&in) != nil || str(in.Input["modelID"]) != "" {
		return quotaReply(400, nil)
	}
	if in.Input["providerID"] == "opencode" && p.zen != nil {
		return p.zen.native(req.URL.Path, in.Input, p.account, p.oauth)
	}
	if in.Input["providerID"] != "opencode-go" || p.zen != nil && p.zen.only {
		return quotaReply(400, nil)
	}
	output := Object{}
	switch req.URL.Path {
	case "/api/rpc/chief.harness/credential":
		if p.fault == "rpc-error" {
			return quotaReply(400, nil)
		}
		output["baseUrl"] = quotaRoute
		if p.oauth && p.account != "" {
			output["authentication"] = "oauth"
		} else if p.account != "" {
			output["apiKey"] = "fixture-secret-" + p.account
		}
	case "/api/rpc/chief.harness/consoleAccount":
		if !p.oauth {
			return quotaReply(400, nil)
		}
		if in.Input["phase"] == "describe" {
			output = Object{"provider": provider, "sourceCredentialID": p.account}
			if p.fault == "switched-lease" && in.Input["sourceCredentialID"] != nil {
				output["sourceCredentialID"] = "someone-else"
			}
		} else if in.Input["phase"] == "lease" && in.Input["sourceCredentialID"] == p.account {
			output["lease"] = Object{"type": "oauth", "methodID": "oauth", "access": "fixture-secret-" + p.account, "expires": quotaNow.Add(time.Hour).UnixMilli(), "metadata": Object{"orgID": "org_" + p.account}}
		} else {
			return quotaReply(400, nil)
		}
	default:
		return quotaReply(404, nil)
	}
	return quotaReply(200, Object{"output": output})
}

func (p quotaPeer) remote(req *http.Request) (*http.Response, error) {
	if req.URL.Host == "models.dev" && !p.oauth && req.Header.Get("Authorization") == "" {
		return quotaReply(200, Object{})
	}
	if req.URL.Host != "opencode.ai" || req.Header.Get("Authorization") != "Bearer fixture-secret-"+p.account {
		return quotaReply(403, nil)
	}
	if p.oauth && req.Header.Get("x-org-id") != "org_"+p.account {
		return quotaReply(403, nil)
	}
	switch req.URL.Path {
	case "/console/api/orgs/current":
		org := "org_" + p.account
		if p.fault == "wrong-workspace" || p.zen != nil && p.zen.fault == "wrong-workspace" {
			org = "org_elsewhere"
		}
		return quotaReply(200, Object{"org": Object{"id": org}})
	case "/console/api/billing/status":
		if p.zen != nil {
			return p.zen.billingReply()
		}
		return quotaReply(200, Object{})
	case "/console/api/go/status":
		if !p.oauth {
			return quotaReply(200, Object{})
		}
		if p.fault == "remote-error" {
			return quotaReply(503, nil)
		}
		meter := Object{"usedMicroCents": fmt.Sprint(p.percent), "limitMicroCents": "100", "resetsAt": "2026-12-01"}
		if p.fault == "no-meter" {
			meter = nil
		}
		return quotaReply(200, Object{"product": "go", "access": Object{"startsAt": "2026-11-01", "endsAt": "2026-12-01", "meters": Object{"week": meter}}})
	case "/zen/go/v1/usage":
		if p.oauth {
			return quotaReply(403, nil)
		}
		if p.fault == "remote-error" {
			return quotaReply(503, nil)
		}
		if p.fault == "no-meter" {
			return quotaReply(200, Object{"usage": Object{}})
		}
		return quotaReply(200, Object{"usage": Object{"weekly": Object{"status": "ok", "percent": p.percent, "resetsAt": "2026-12-01"}}})
	}
	return quotaReply(404, nil)
}
