// Package diagnostics emits local, development-bundle-only operational events.
package diagnostics

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"sync"
)

const TraceHeader = "X-Chief-Dev-Trace"

var enabled = sync.OnceValue(func() bool {
	executable, err := os.Executable()
	if err != nil {
		return false
	}
	executable, err = filepath.EvalSymlinks(executable)
	if err != nil || filepath.Base(executable) != "chief-runtime" {
		return false
	}
	macOS := filepath.Dir(executable)
	contents := filepath.Dir(macOS)
	bundle := filepath.Dir(contents)
	if filepath.Base(macOS) != "MacOS" || filepath.Base(contents) != "Contents" || filepath.Ext(bundle) != ".app" {
		return false
	}
	data, err := os.ReadFile(filepath.Join(contents, "Resources", "build-provenance.json"))
	var provenance struct{ Channel string }
	return err == nil && json.Unmarshal(data, &provenance) == nil && provenance.Channel == "development" && isDevelopmentBundle(bundle)
})

type traceKey struct{}

var tracePattern = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)

// WithTrace is called after local transport authentication. Log only a digest
// of the optional renderer trace token, never the incoming header itself.
func WithTrace(ctx context.Context, token string) context.Context {
	if !enabled() {
		return ctx
	}
	if tracePattern.MatchString(token) {
		digest := sha256.Sum256([]byte(token))
		return context.WithValue(ctx, traceKey{}, hex.EncodeToString(digest[:12]))
	}
	var id [12]byte
	if _, err := rand.Read(id[:]); err != nil {
		return ctx
	}
	return context.WithValue(ctx, traceKey{}, hex.EncodeToString(id[:]))
}

func CopyTrace(ctx, source context.Context) context.Context {
	if id, ok := source.Value(traceKey{}).(string); ok {
		return context.WithValue(ctx, traceKey{}, id)
	}
	return ctx
}

func Traced(ctx context.Context) bool { return ctx.Value(traceKey{}) != nil }

func EnsureTrace(ctx context.Context) context.Context {
	if Traced(ctx) {
		return ctx
	}
	return WithTrace(ctx, "")
}

// Event accepts code-owned operation and phase labels only.
func Event(ctx context.Context, operation, phase string) {
	if enabled() {
		id, _ := ctx.Value(traceKey{}).(string)
		emit(operation + " " + phase + " trace=" + id)
	}
}

func End(ctx context.Context, operation string, err error) {
	phase := "completed"
	switch {
	case errors.Is(err, context.DeadlineExceeded):
		phase = "timed_out"
	case errors.Is(err, context.Canceled):
		phase = "canceled"
	case err != nil:
		phase = "failed"
	}
	Event(ctx, operation, phase)
}
