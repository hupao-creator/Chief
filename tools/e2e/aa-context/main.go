// Replay the public roster and Astra release response through the before-send slot.
package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/hupao-creator/Chief/internal/core/plugin"
	"github.com/hupao-creator/Chief/internal/hosts/contexthost"
	aa "github.com/hupao-creator/Chief/internal/plugins/contexts/artificialanalysis"
)

const rosterURL = "https://artificialanalysis.ai/models/"
const releaseSlug = "gpt-6-2-astra"

type replay struct {
	bodies   map[string][]byte
	mu       sync.Mutex
	requests []string
}

func (r *replay) Do(req *http.Request) (*http.Response, error) {
	address := req.URL.String()
	r.mu.Lock()
	r.requests = append(r.requests, address)
	r.mu.Unlock()
	body, ok := r.bodies[address]
	if !ok {
		return nil, fmt.Errorf("unexpected replay URL %s", address)
	}
	return &http.Response{StatusCode: http.StatusOK, Body: io.NopCloser(bytes.NewReader(body)), Request: req}, nil
}

func collect(ctx context.Context, options aa.Options, catalogs []plugin.BoundModelCatalog) (string, error) {
	host, err := contexthost.New(contexthost.Config{Plugins: []plugin.ContextPlugin{aa.NewWithOptions(options)}})
	if err != nil {
		return "", err
	}
	if err := host.Start(ctx, plugin.RuntimeStartContext{}); err != nil {
		return "", err
	}
	defer host.Stop(ctx)
	entries, err := host.CollectMokuContexts(ctx, "before-send", catalogs)
	if err != nil {
		return "", err
	}
	if len(entries) != 1 || entries[0].ID != "evaluation" {
		return "", fmt.Errorf("missing evaluation slot")
	}
	return entries[0].Content, nil
}

func run(index, detail string) error {
	dir, err := os.MkdirTemp("", "chief-aa-replay-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(dir)
	peer := &replay{bodies: map[string][]byte{}}
	hashes := map[string]string{}
	for address, path := range map[string]string{rosterURL: index, rosterURL + releaseSlug: detail} {
		body, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		peer.bodies[address] = body
		hashes[address] = fmt.Sprintf("%x", sha256.Sum256(body))
	}
	options := aa.Options{CacheRoot: filepath.Join(dir, "cold-cache"), HTTPClient: peer}
	catalog := plugin.BoundModelCatalog{ID: "codex", DisplayName: "Codex", Load: func(context.Context) (json.RawMessage, error) {
		return json.RawMessage(`{"models":[{"selector":"gpt-6.2-astra","provenance":{"kind":"native"}}]}`), nil
	}}
	ctx := context.Background()
	live, err := collect(ctx, options, []plugin.BoundModelCatalog{catalog})
	if err != nil {
		return err
	}
	cached, err := collect(ctx, options, nil)
	if err != nil {
		return err
	}
	if len(peer.requests) != 2 || peer.requests[0] != rosterURL || peer.requests[1] != rosterURL+releaseSlug || !strings.Contains(live, "Native catalog identities: gpt-6.2-astra.") || !strings.Contains(cached, "Historical evaluator snapshot") {
		return fmt.Errorf("unexpected before-send route or requests: %v", peer.requests)
	}
	// These five configurations are listed in the public Astra comparison table.
	if strings.Count(live, "- configuration=") != 5 || strings.Count(cached, "- configuration=") != 5 {
		return fmt.Errorf("expected five measured configurations")
	}
	for _, effort := range []string{"max", "xhigh", "high", "medium", "low"} {
		prefix := "- configuration=reasoning:true,effort:" + effort + ";"
		start := strings.Index(live, prefix)
		if start < 0 {
			return fmt.Errorf("missing %s configuration", effort)
		}
		row, _, _ := strings.Cut(live[start:], "\n")
		if !strings.Contains(cached, row) {
			return fmt.Errorf("cached %s observation differs from cold route", effort)
		}
		for _, field := range []string{"intelligenceIndex", "costPerIntelligenceIndexTaskUsd", "headlineOutputTokensPerSecond", "headlineTimeToFirstAnswerTokenSeconds", "inputUsdPer1MTokens", "outputUsdPer1MTokens"} {
			if !strings.Contains(row, "; "+field+"=") || strings.Contains(row, "; "+field+"=null") {
				return fmt.Errorf("%s lacks %s", effort, field)
			}
		}
		for _, benchmark := range aa.BenchmarkIDs {
			if !strings.Contains(row, benchmark+":") || strings.Contains(row, benchmark+":null") {
				return fmt.Errorf("%s lacks %s", effort, benchmark)
			}
		}
		if !strings.Contains(row, "medianOutputTokensPerSecond=null;") || !strings.Contains(row, "medianTimeToFirstAnswerTokenSeconds=null;") {
			return fmt.Errorf("%s claims a median", effort)
		}
	}
	return json.NewEncoder(os.Stdout).Encode(map[string]any{"responseSHA256": hashes, "requests": peer.requests, "coldRoute": live, "reopenedFallback": cached})
}

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: aa-context roster.html astra.html")
		os.Exit(2)
	}
	if err := run(os.Args[1], os.Args[2]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
