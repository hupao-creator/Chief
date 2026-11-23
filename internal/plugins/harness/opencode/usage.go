package opencode

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"regexp"
	"strings"
	"time"

	"github.com/hupao-creator/Chief/internal/core/plugin"
	"github.com/hupao-creator/Chief/internal/platform/discovery"
	"github.com/hupao-creator/Chief/internal/plugins/harness/opencode/accounttelemetry"
)

var authHeaderPattern = regexp.MustCompile(`(?i)authorization|api[-_]?key|token`)

func usageAttribution(ctx context.Context, runtime *Runtime, session, id, provider, modelID string) []string {
	keys := []string{}
	if runtime == nil || provider == "" {
		return keys
	}
	var message Object
	if runtime.Request(ctx, "GET", sessionPath(session, "/message/"+url.PathEscape(id)), nil, &message) != nil || message["type"] != "assistant" {
		return keys
	}
	agentID := str(message["agent"])
	if agentID == "" {
		return keys
	}
	var agent Object
	if runtime.Request(ctx, "GET", "/api/agent/"+url.PathEscape(agentID), nil, &agent) != nil {
		return keys
	}
	request := object(agent["request"])
	for name := range object(request["headers"]) {
		if authHeaderPattern.MatchString(name) {
			return keys
		}
	}
	if object(request["body"])["model"] != nil {
		return keys
	}
	variant := str(object(message["model"])["variant"])
	credential, err := runtime.ReadProviderCredential(ctx, provider, modelID, variant)
	if err != nil || credential == nil || !accounttelemetry.IsOpenCodeGoEndpoint(credential.BaseURL) {
		return keys
	}
	return accounttelemetry.OpenCodeGoAttributionKeys(credential.APIKey)
}
func unknownTelemetry(note, availability string) Object {
	return Object{"source": "OpenCode account telemetry", "observedAt": time.Now().UnixMilli(), "availability": availability, "limitReached": nil, "windows": []any{}, "note": note}
}
func formatTelemetry(value Object) string {
	value = clone(value)
	value["namespace"] = "opencode"
	if at := number(value["observedAt"]); at != 0 {
		value["observedAt"] = time.UnixMilli(int64(at)).UTC().Format("2006-01-02T15:04:05.000Z")
	}
	for _, raw := range array(value["windows"]) {
		delete(object(raw), "usageAttribution")
	}
	raw, _ := json.Marshal(value)
	return string(raw)
}
func attachLedger(ctx context.Context, snapshot Object, ledger plugin.TelemetryLedger) error {
	if ledger == nil {
		return nil
	}
	windows := []Object{}
	for _, raw := range array(snapshot["windows"]) {
		window := object(raw)
		if window["metering"] == nil {
			continue
		}
		reading := Object{}
		for _, key := range []string{"id", "metering", "usageAttribution", "usedPercent", "usedUnits", "limitUnits", "resetsAt", "durationMinutes"} {
			if value, ok := window[key]; ok {
				reading[key] = value
			}
		}
		windows = append(windows, reading)
	}
	encoded, _ := json.Marshal(Object{"type": "window-reading", "observedAt": snapshot["observedAt"], "windows": windows})
	if err := ledger.Record(ctx, encoded); err != nil {
		return err
	}
	raw, err := ledger.Read(ctx)
	if err != nil {
		return err
	}
	var observed Object
	if err = json.Unmarshal(raw, &observed); err != nil {
		return err
	}
	byID := map[string]any{}
	for _, v := range array(observed["windows"]) {
		window := object(v)
		byID[str(window["id"])] = window["ledger"]
	}
	for _, v := range array(snapshot["windows"]) {
		window := object(v)
		if previous := byID[str(window["id"])]; previous != nil {
			window["ledger"] = previous
		}
	}
	return nil
}

var _ plugin.MokuMessageTelemetrySource = (*Harness)(nil)

type telemetryCacheEntry struct {
	source string
	at     time.Time
	text   string
}

func (h *Harness) MokuContext(ctx context.Context, purpose string, request plugin.SettingsRequest, ledger plugin.TelemetryLedger) (string, error) {
	if purpose != "telemetry" {
		return "", ctx.Err()
	}
	return h.MokuMessageTelemetry(ctx, request, ledger)
}

// Check the native configuration and credential revision on the send path. Slow
// native/remote work belongs to a background flight for that exact launch source.
func (h *Harness) MokuMessageTelemetry(ctx context.Context, request plugin.SettingsRequest, ledger plugin.TelemetryLedger) (string, error) {
	settings, err := h.settings.defaults(request.Settings)
	if err != nil {
		return "", err
	}
	source, err := h.settings.resolveCatalogSource(ctx, settings, request.Cwd, discovery.SourceIdentity)
	if err != nil {
		if ctx.Err() != nil {
			return "", ctx.Err()
		}
		return formatTelemetry(unknownTelemetry("OpenCode account source could not be verified.", "error")), nil
	}
	h.backgroundMu.Lock()
	if h.telemetry.source != source.key {
		h.telemetry = telemetryCacheEntry{source: source.key}
	}
	cached := h.telemetry
	h.backgroundMu.Unlock()
	if time.Since(cached.at) >= 5*time.Minute {
		h.background("telemetry:"+source.key, func(life context.Context) {
			opts := Options{CWD: request.Cwd, ConfigurationCWD: settings.ConfigurationCWD, ExecutablePath: source.settings.ExecutablePath, Environment: source.environment}
			snapshot, err := h.readTelemetry(life, opts)
			// Opening OpenCode can itself refresh credentials. Never label the
			// resulting observation with a different launch/account generation.
			current, checkErr := h.settings.resolveCatalogSource(life, settings, request.Cwd, discovery.SourceIdentity)
			if checkErr == nil && current.key != source.key {
				return
			}
			if err == nil {
				err = checkErr
			}
			if err == nil {
				err = attachLedger(life, snapshot, ledger)
			}
			if err != nil {
				// Native HTTP errors may include private response data in other
				// transports. Publish only the operation class and HTTP status.
				note := "OpenCode account usage could not be resolved."
				var rpc *RequestError
				if errors.As(err, &rpc) {
					note = fmt.Sprintf("OpenCode %s failed (HTTP %d).", rpc.Path, rpc.Status)
				}
				if errors.Is(err, context.DeadlineExceeded) {
					note = "OpenCode account usage timed out."
				}
				snapshot = unknownTelemetry(note, "error")
			}
			text := formatTelemetry(snapshot)
			h.backgroundMu.Lock()
			defer h.backgroundMu.Unlock()
			if !h.closed && h.telemetry.source == source.key {
				h.telemetry = telemetryCacheEntry{source: source.key, at: time.Now(), text: text}
			}
		})
	}
	if cached.text != "" {
		return cached.text, nil
	}
	return formatTelemetry(unknownTelemetry("Native account telemetry is refreshing in the background; account capacity is unknown.", "unknown")), nil
}

func readTelemetry(ctx context.Context, opts Options) (_ Object, err error) {
	runtime, err := NewRuntime(ctx, opts)
	if err != nil {
		return nil, err
	}
	defer func() { err = errors.Join(err, runtime.Close()) }()
	return readGoAccountTelemetry(ctx, runtime, accounttelemetry.ClientOptions{})
}

func readGoAccountTelemetry(ctx context.Context, runtime *Runtime, client accounttelemetry.ClientOptions) (Object, error) {
	// The native provider owns the account binding. Neither an execution model
	// nor its build agent/variant can establish capacity for this account.
	const id = "opencode-go"
	unknown := func() Object {
		return unknownTelemetry("No verified native OpenCode Go provider account is available. Account capacity is unknown.", "unknown")
	}
	var providers []CatalogNativeProvider
	if err := runtime.Request(ctx, "GET", "/api/provider", nil, &providers); err != nil {
		return nil, err
	}
	var provider *CatalogNativeProvider
	for i := range providers {
		if providers[i].ID != id {
			continue
		}
		if provider != nil {
			return unknown(), nil
		}
		provider = &providers[i]
	}
	if provider == nil || !consoleProviderPackage(provider.Package) || (provider.IntegrationID != "opencode" && provider.IntegrationID != id) ||
		!accounttelemetry.OfficialOpenCodeGoEndpoint(str(provider.Settings["baseURL"]), true) ||
		hasCatalogAuthenticationHeader(provider.Headers, true) || hasCatalogField(provider.Settings, "headers") || hasIdentityOverride(provider.Body) {
		return unknown(), nil
	}
	credential, err := runtime.ReadProviderCredential(ctx, id, "", "")
	if err != nil {
		return nil, err
	}
	if !accounttelemetry.OfficialOpenCodeGoEndpoint(credential.BaseURL, true) {
		return unknown(), nil
	}
	org, conflict := sourceOrganization(provider.Headers)
	if conflict {
		return unknown(), nil
	}
	var raw json.RawMessage
	if credential.Authentication == "oauth" {
		if provider.IntegrationID != "opencode" {
			return unknown(), nil
		}
		account, err := runtime.ReadConsoleAccount(ctx, id, "", "")
		if err != nil {
			return nil, err
		}
		if account == nil || org != "" && org != account.OrgID {
			return unknown(), nil
		}
		raw, err = accounttelemetry.ReadConsoleGoTelemetry(ctx, client, accounttelemetry.ConsoleAccount{
			AccessToken: account.AccessToken, OrgID: account.OrgID, ExpiresAt: account.ExpiresAt,
		})
		if err != nil {
			if ctx.Err() != nil {
				return nil, ctx.Err()
			}
			return unknownTelemetry(err.Error(), "error"), nil
		}
	} else {
		key := strings.TrimSpace(credential.APIKey)
		if key == "" || key == "public" || org != "" {
			return unknown(), nil
		}
		raw, err = accounttelemetry.ReadOpenCodeGoTelemetry(ctx, client, credential.BaseURL, credential.APIKey)
		if err != nil {
			return nil, err
		}
	}
	var telemetry Object
	if err := json.Unmarshal(raw, &telemetry); err != nil {
		return nil, err
	}
	telemetry["note"] = "This reading belongs to the native opencode-go provider account. Check each model's own route and credentials for execution availability. " + str(telemetry["note"])
	return telemetry, nil
}
