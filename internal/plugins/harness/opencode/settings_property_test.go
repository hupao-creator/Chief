package opencode

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/hupao-creator/Chief/internal/core/plugin"
	"github.com/hupao-creator/Chief/internal/platform/sqlite"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

const flashProfile = `{"useDefaultThreadSettings":false,"threadSettings":{"provider":"opencode-go","model":"deepseek-v4.1-flash","variant":"max","agent":"build","permissionMode":"auto"}}`

func TestExecutionCatalogProperties(t *testing.T) {
	rapidcheck.Check(t, func(rt *rapid.T) {
		root := t.TempDir()
		// A non-forced retry after an error and an explicit refresh after a
		// settled read must both observe the new facts for the retained profile.
		order := rapid.Permutation([]string{"available", "excluded", "read error"}).Draw(rt, "refresh order")
		steps := append(order, "available")
		remaining := steps
		api := NewSettings(plugin.HostContext{Environment: func(context.Context) (map[string]string, error) {
			return map[string]string{"HOME": root, "OPENCODE_DB": ":memory:"}, nil
		}}, func(ctx context.Context, _ Settings, _ string) (*Runtime, error) {
			if len(remaining) == 0 {
				return nil, errors.New("unexpected extra catalog probe")
			}
			state := remaining[0]
			remaining = remaining[1:]
			owner, cancel := context.WithCancel(ctx)
			return &Runtime{ctx: owner, cancel: cancel, URL: "http://native",
				client: &http.Client{Transport: quotaTransport(func(req *http.Request) (*http.Response, error) {
					return flashCatalogReply(req, state)
				})}}, nil
		})
		defer api.Close()
		settings := json.RawMessage(flashProfile)
		for i, state := range steps {
			raw, err := api.Presentation(t.Context(), plugin.SettingsPresentationRequest{
				Settings: settings, Cwd: root, Refresh: i > 0 && steps[i-1] != "read error", ExecutionProfile: true,
			})
			if err != nil {
				rt.Fatal(err)
			}
			var result struct {
				CLI                 Object
				Models              []CatalogModel
				EffectiveModel      Object
				AccountCheckPending bool
			}
			if err := json.Unmarshal(raw, &result); err != nil {
				rt.Fatal(err)
			}
			if state == "read error" {
				if result.CLI["status"] != "unavailable" || !strings.Contains(str(result.CLI["message"]), "/api/model") {
					rt.Fatalf("native read failure lost: %s", raw)
				}
				continue
			}
			if result.AccountCheckPending || result.CLI["status"] != "ready" {
				rt.Fatalf("execution editor received unsettled catalog: %s", raw)
			}
			_, err = api.SnapshotExecution(t.Context(), plugin.SettingsRequest{Cwd: root, Settings: settings}, false)
			if state == "excluded" {
				if len(result.Models) != 0 || result.EffectiveModel != nil || str(result.CLI["message"]) == "" ||
					err == nil || !strings.Contains(err.Error(), str(result.CLI["message"])) {
					rt.Fatalf("filtered model lost its restriction: %s, %v", raw, err)
				}
			} else if err != nil || len(result.Models) != 1 || result.EffectiveModel["model"] != "deepseek-v4.1-flash" ||
				result.EffectiveModel["provider"] != "opencode-go" || result.EffectiveModel["variant"] != "max" {
				rt.Fatalf("retained Flash max selection unavailable: %s, %v", raw, err)
			}
		}
		if len(remaining) != 0 {
			rt.Fatal("refresh reused an obsolete catalog")
		}
	})
}

func flashCatalogReply(req *http.Request, state string) (*http.Response, error) {
	switch req.URL.Path {
	case "/api/model":
		if state == "read error" {
			return quotaReply(503, nil)
		}
		return quotaReply(200, []Object{{"providerID": "opencode-go", "id": "deepseek-v4.1-flash",
			"name": "DeepSeek V4.1 Flash 1017", "enabled": true,
			"capabilities": Object{"input": []string{"text"}, "output": []string{"text"}, "tools": true},
			"variants":     []Object{{"id": "max"}}, "cost": []Object{{"input": 1, "output": 1, "cache": Object{"read": 0, "write": 0}}}}})
	case "/api/agent":
		return quotaReply(200, []Object{{"id": "build", "name": "Build", "mode": "primary"}})
	case "/api/rpc/chief.harness/credential":
		// The excluded case supplies positive evidence of a paid route with
		// no credential. Other routes use the native model's availability.
		base := "http://provider.invalid/v1"
		if state == "excluded" {
			base = "https://opencode.ai/zen/go/v1"
		}
		return quotaReply(200, Object{"output": Object{"baseUrl": base}})
	case "/api/rpc/chief.harness/consoleAccount":
		return quotaReply(200, Object{"output": Object{}})
	case "/api/model/default":
		return quotaReply(200, nil)
	case "/api/plugin", "/api/config", "/api/provider":
		return quotaReply(200, []Object{})
	default:
		return quotaReply(404, nil)
	}
}

// Exercise the routing entry point with two independent SQLite connections.
// The account can commit a switch or roll it back while discovery is waiting.
func TestRoutingCatalogRecoveryProperties(t *testing.T) {
	rapidcheck.Check(t, func(rt *rapid.T) {
		root := t.TempDir()
		path := filepath.Join(root, "opencode.db")
		db, err := sqlite.Open(path, false)
		if err != nil {
			rt.Fatal(err)
		}
		defer db.Close()
		exec := func(sql string) {
			if err := db.Exec(sql); err != nil {
				rt.Fatal(err)
			}
		}
		exec("CREATE TABLE credential(id TEXT, integration_id TEXT, active INTEGER, connector_id TEXT, method_id TEXT, time_updated INTEGER)")
		exec("INSERT INTO credential VALUES('A','provider',1,'native','key',1)")
		commit := rapid.Bool().Draw(rt, "commit switch")
		drift := rapid.IntRange(0, 2).Draw(rt, "source changes during acquisition")
		status := rapid.SampledFrom([]int{502, 503, 504}).Draw(rt, "temporary model response")
		var launches, reads atomic.Int32
		env := map[string]string{"HOME": root, "OPENCODE_DB": path}
		api := NewSettings(plugin.HostContext{Environment: func(context.Context) (map[string]string, error) {
			return env, nil
		}}, func(ctx context.Context, _ Settings, _ string) (*Runtime, error) {
			if int(launches.Add(1)) <= drift {
				if err := db.Exec("UPDATE credential SET time_updated = time_updated + 1"); err != nil {
					return nil, err
				}
			}
			owner, cancel := context.WithCancel(ctx)
			return &Runtime{ctx: owner, cancel: cancel, URL: "http://native",
				client: &http.Client{Transport: quotaTransport(func(req *http.Request) (*http.Response, error) {
					if req.URL.Path == "/api/model" && reads.Add(1) == 1 {
						return quotaReply(status, nil)
					}
					return flashCatalogReply(req, "available")
				})}}, nil
		})
		defer api.Close()
		request := plugin.SettingsRequest{Cwd: root, RoutingCatalog: true}
		before, err := api.Describe(t.Context(), request)
		if drift == 2 {
			if !errors.Is(err, errCatalogSourceChanged) || launches.Load() != 2 {
				rt.Fatalf("persistent account change: %v, %d probes", err, launches.Load())
			}
			return
		}
		if err != nil || int(launches.Load()) != 1+drift || int(reads.Load()) != 2+drift {
			rt.Fatalf("cold admission: %v, %d probes, %d model reads", err, launches.Load(), reads.Load())
		}
		exec("BEGIN EXCLUSIVE; UPDATE credential SET id='B', time_updated=time_updated+1")
		limited, cancel := context.WithTimeout(t.Context(), 20*time.Millisecond)
		_, err = api.Describe(limited, request)
		cancel()
		if !errors.Is(err, context.DeadlineExceeded) {
			rt.Fatalf("admission under a held lock: %v", err)
		}
		end := "ROLLBACK"
		if commit {
			end = "COMMIT"
		}
		released := make(chan error, 1)
		time.AfterFunc(40*time.Millisecond, func() { released <- db.Exec(end) })
		after, err := api.Describe(t.Context(), request)
		if releaseErr := <-released; releaseErr != nil {
			rt.Fatal(releaseErr)
		}
		if err != nil || (string(before) != string(after)) != commit {
			rt.Fatalf("catalog identity after %s: %v, identity changed %t", end, err, string(before) != string(after))
		}
	})
}
