package runtime_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
	core "github.com/hupao-creator/Chief/internal/core/runtime"
	"github.com/hupao-creator/Chief/internal/core/store"
	"github.com/hupao-creator/Chief/internal/platform/transport"
	"github.com/hupao-creator/Chief/internal/services/moku"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

// PBT-MOKU-RESEND: a host opening failure precedes native input admission.
// Exercise the public projection and race independent retry command identities.
func TestChiefFailureResendProperties(t *testing.T) {
	rapidcheck.Check(t, func(t *rapid.T) {
		ctx := context.Background()
		check := func(err error) {
			t.Helper()
			if err != nil {
				t.Fatal(err)
			}
		}
		root, err := os.MkdirTemp("", "chief-resend-")
		check(err)
		defer os.RemoveAll(root)
		db, err := store.Open(filepath.Join(root, "state.sqlite"))
		check(err)
		defer db.Close()
		peer := &injectedToolPeer{}
		harnesses := map[string]plugin.Harness{"fixture": peer}
		r, err := core.New(ctx, core.Config{Store: db, Harnesses: harnesses, DataDir: root, DefaultCwd: root})
		check(err)
		defer r.Close(ctx)
		owner, err := r.EnsureMokuThread(ctx, "fixture", nil, root)
		check(err)
		config := chiefToolConfiguration(r, root, harnesses)
		var available atomic.Bool
		open := config.OpenSession
		config.OpenSession = func(ctx context.Context, id string, injection *plugin.Injection) error {
			if !available.Load() {
				return errors.New("PRIVATE-native-startup-detail")
			}
			return open(ctx, id, injection)
		}
		scope := "doc-" + rapid.StringMatching("[a-z]{1,12}").Draw(t, "super-thread")
		config.SuperThreadContext = func(_ context.Context, id string) (json.RawMessage, error) {
			if id != scope {
				return nil, errors.New("wrong Super Thread")
			}
			return raw(map[string]string{"id": id}), nil
		}
		word := rapid.SampledFrom([]string{"你好", "A\nB", "é🏝"}).Draw(t, "text")
		request := moku.SubmitRequest{SuperThreadID: &scope, Input: model.AgentInput{Parts: []model.AgentInputPart{
			{Kind: "text", Text: word}, {Kind: "local-file", File: &model.InputFile{ID: "22345678-1234-4234-9234-123456789012"}}}}}
		var sends atomic.Int32
		send := config.SendSession
		config.SendSession = func(ctx context.Context, id string, input model.AgentInput, injection *plugin.Injection, entries []plugin.ContextEntry, accepted func(moku.SendResult) error) (moku.SendResult, error) {
			if !bytes.Equal(raw(input), raw(request.Input)) || !strings.Contains(string(raw(entries)), scope) {
				return moku.SendResult{}, errors.New("resend lost the original input or context")
			}
			sends.Add(1)
			return send(ctx, id, input, injection, entries, accepted)
		}
		c, err := moku.New(config)
		check(err)
		check(c.Start(ctx, plugin.RuntimeStartContext{}))
		defer c.Stop(ctx)
		_, err = c.Invoke(ctx, "moku:submit", []json.RawMessage{raw(request)})
		check(err)
		page := func() []map[string]any {
			page, err := r.ReadThreadContent(ctx, owner.ID, transport.ContentScope{Kind: "moku-conversation"}, nil)
			check(err)
			if strings.Contains(string(page.Value), "PRIVATE-") || strings.Contains(string(page.Value), "resendRequest") {
				t.Fatal("private failure content exposed")
			}
			var result struct{ Messages []map[string]any }
			check(json.Unmarshal(page.Value, &result))
			return result.Messages
		}
		rows := page()
		if len(rows) != 2 || rows[0]["text"] != word || rows[1]["failureCode"] != "startup" || rows[1]["resendState"] != "ready" {
			t.Fatalf("missing failure: %v", rows)
		}
		target := []json.RawMessage{raw(map[string]any{"threadId": owner.ID, "failureId": rows[1]["failureId"]})}
		if _, err := c.Invoke(ctx, "moku:resend", target); err == nil || len(page()) != 2 {
			t.Fatal("unavailable host consumed the retry")
		}
		available.Store(true)
		count := rapid.IntRange(2, 6).Draw(t, "concurrent-resends")
		results := make(chan error, count)
		for range count {
			go func() { _, err := c.Invoke(ctx, "moku:resend", target); results <- err }()
		}
		success := 0
		for range count {
			if <-results == nil {
				success++
			}
		}
		rows = page()
		if success != 1 || sends.Load() != 1 || len(rows) != 3 || rows[1]["resendState"] != "sent" || rows[2]["text"] != word {
			t.Fatalf("resend admission mismatch %d %d %v", success, sends.Load(), rows)
		}
	})
}
