package accounttelemetry

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"regexp"
	"strings"
	"time"
)

// ConsoleAccount contains only the native account facts needed for telemetry.
type ConsoleAccount struct {
	AccessToken string    `json:"-"`
	OrgID       string    `json:"-"`
	ExpiresAt   time.Time `json:"-"`
}

const (
	consoleAPI              = "https://opencode.ai/console/api"
	consoleWorkspaceURL     = consoleAPI + "/orgs/current"
	consoleGoStatusURL      = consoleAPI + "/go/status"
	ConsoleZenBillingSource = consoleAPI + "/billing/status"
)

var organizationPattern = regexp.MustCompile(`^(org|wrk)_[A-Za-z0-9_-]+$`)
var microCentPattern = regexp.MustCompile(`^-?\d{1,30}$`)

type consoleWorkspaceClient struct {
	client HTTPClient
	org    string
}

func (c consoleWorkspaceClient) Do(r *http.Request) (*http.Response, error) {
	switch r.URL.String() {
	case consoleWorkspaceURL, consoleGoStatusURL, ConsoleZenBillingSource:
	default:
		return nil, errors.New("Console OAuth telemetry refuses an unrecognized route")
	}
	request := r.Clone(r.Context())
	request.Header.Set("x-org-id", c.org)
	request.Header.Set("x-opencode-org-id", c.org)
	return c.client.Do(request)
}

func readConsoleWorkspace(ctx context.Context, host ClientOptions, credentials ConsoleAccount, endpoint string) (object, error) {
	org := credentials.OrgID
	if !organizationPattern.MatchString(org) || strings.TrimSpace(credentials.AccessToken) == "" {
		return nil, errors.New("Console OAuth telemetry requires a live workspace lease")
	}
	host.HTTP = consoleWorkspaceClient{host.HTTP, org}
	const timeout = 2500 * time.Millisecond
	bounded, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	read := func(endpoint string) (object, error) {
		if !credentials.ExpiresAt.After(host.Now()) {
			return nil, errors.New("Console OAuth telemetry requires a live workspace lease")
		}
		status, payload, err := readJSON(bounded, host, endpoint, credentials.AccessToken, timeout)
		if err != nil {
			return nil, err
		}
		if status < 200 || status >= 300 {
			return nil, fmt.Errorf("OpenCode Console returned HTTP %d", status)
		}
		return record(payload), nil
	}
	current, err := read(consoleWorkspaceURL)
	if err != nil {
		return nil, err
	}
	if text(record(current["org"])["id"]) != org {
		return nil, errors.New("OpenCode Console workspace could not be verified")
	}
	return read(endpoint)
}

// ReadConsoleGoTelemetry keeps Console OAuth distinct from workspace API-key
// usage. Only server-reported access meters establish subscription windows.
func ReadConsoleGoTelemetry(ctx context.Context, host ClientOptions, credentials ConsoleAccount) (json.RawMessage, error) {
	host = normalizeOptions(host)
	status, err := readConsoleWorkspace(ctx, host, credentials, consoleGoStatusURL)
	if err != nil {
		return nil, err
	}
	now := host.Now()
	var plan, useBalance, endsAt, active any
	if value := text(status["product"]); value == "go" || value == "go-plus" {
		plan = value
	}
	if value, ok := status["useBalance"].(bool); ok {
		useBalance = value
	}
	access := record(status["access"])
	start, startOK := telemetryTime(text(access["startsAt"]))
	end, endOK := telemetryTime(text(access["endsAt"]))
	if endOK {
		endsAt = end.UTC().Format("2006-01-02T15:04:05.000Z")
	}
	if value, exists := status["access"]; exists && value == nil {
		active = false
	} else if startOK && endOK && start.Before(end) {
		active = !now.Before(start) && now.Before(end)
	}
	result := object{"source": "OpenCode Console OAuth", "observedAt": now.UnixMilli(), "availability": "unknown", "windows": []object{}, "limitReached": nil,
		"note": "Console Go subscription meters are unknown."}
	if plan != nil || useBalance != nil || active != nil || endsAt != nil {
		result["plan"] = plan
		result["console"] = object{"source": consoleGoStatusURL, "observedAt": now.UTC().Format("2006-01-02T15:04:05.000Z"),
			"plan": plan, "useBalance": useBalance, "accessEndsAt": endsAt, "accessActive": active}
	}
	if active == true && plan != nil {
		windows := consoleGoWindows(status, credentials.OrgID, now)
		result["windows"] = windows
		if len(windows) > 0 {
			result["availability"] = "available"
			result["note"] = "Server-reported Console Go subscription meters for this workspace. Free models and prepaid credits have separate availability."
		}
	}
	return jsonValue(result), nil
}

// ReadConsoleZenBalance returns a decimal USD amount only for the verified
// workspace's prepaid pay-as-you-go ledger. An empty amount means unknown.
func ReadConsoleZenBalance(ctx context.Context, host ClientOptions, credentials ConsoleAccount) (string, error) {
	billing, err := readConsoleWorkspace(ctx, normalizeOptions(host), credentials, ConsoleZenBillingSource)
	if err != nil {
		return "", err
	}
	if billing["billingMode"] != "prepaid" || billing["mode"] != "pay-as-you-go" {
		return "", nil
	}
	s := text(billing["balanceMicroCents"])
	if !microCentPattern.MatchString(s) {
		return "", nil
	}
	amount, _ := new(big.Int).SetString(s, 10)
	usd := new(big.Rat).SetFrac(amount, big.NewInt(100000000)).FloatString(8)
	return strings.TrimRight(strings.TrimRight(usd, "0"), "."), nil
}

// Console uses decimal integer strings, not the percentages returned by the
// legacy key endpoint. Derive ratios without rounding the micro-cent operands.
func consoleGoWindows(status object, org string, now time.Time) []object {
	meters := record(record(status["access"])["meters"])
	windows := []object{}
	// Workspace capacity survives token rotation and is shared by native readers. This identity is separate from API-key attribution.
	hash := sha256.Sum256([]byte("mokusei.opencode-console.workspace.v1:" + org))
	key := fmt.Sprintf("opencode-go:console:sha256:%x", hash)
	for _, definition := range []struct {
		field, id, label string
		minutes          float64
	}{
		{"fiveHour", "rolling", "OpenCode Go 5-hour subscription window", 300},
		{"week", "weekly", "OpenCode Go weekly subscription window", 10080},
		{"month", "monthly", "OpenCode Go monthly subscription window", 0},
	} {
		meter := record(meters[definition.field])
		parse := func(value any) *big.Int {
			s := text(value)
			if !microCentPattern.MatchString(s) {
				return nil
			}
			n, ok := new(big.Int).SetString(s, 10)
			if !ok || n.Sign() < 0 {
				return nil
			}
			return n
		}
		used, limit := parse(meter["usedMicroCents"]), parse(meter["limitMicroCents"])
		if used == nil || limit == nil || limit.Sign() <= 0 {
			continue
		}
		reset, hasReset := telemetryTime(meter["resetsAt"])
		// A five-hour window starts on first use; null dates with zero consumption
		// are authoritative unused capacity, not a fabricated reset timestamp.
		startValue, hasStart := meter["startsAt"]
		resetValue, hasResetField := meter["resetsAt"]
		unused := definition.field == "fiveHour" && used.Sign() == 0 && hasStart && startValue == nil && hasResetField && resetValue == nil
		if !hasReset && !unused {
			continue
		}
		ratio, _ := new(big.Rat).SetFrac(new(big.Int).Mul(used, big.NewInt(100)), limit).Float64()
		percent := rounded(min(100.0, ratio))
		window := object{"id": key + ":" + definition.id, "label": definition.label, "scope": "feature", "selector": "OpenCode Go subscription", "usageAttribution": object{"type": "matching", "keys": []string{key}}, "usedPercent": percent, "remainingPercent": rounded(100 - percent), "resetsAt": nil, "exhausted": used.Cmp(limit) >= 0, "quality": "exact", "confidence": "high", "metering": "monetary"}
		if hasReset {
			window["resetsAt"] = reset.UTC().Format("2006-01-02T15:04:05.000Z")
		}
		if definition.minutes > 0 {
			window["durationMinutes"] = definition.minutes
			if hasReset {
				if pace := calculatePace(percent, definition.minutes, reset, now); pace != nil {
					window["pace"] = pace
				}
			}
		}
		windows = append(windows, window)
	}
	return windows
}
