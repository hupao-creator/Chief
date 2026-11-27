package voice

import (
	"context"
	"crypto/sha256"
	"errors"
	"strings"
	"sync"
	"time"

	"github.com/hupao-creator/Chief/internal/core/plugin"
)

type handoff struct{ id, text string }

type segment struct {
	complete bool
	digest   [sha256.Size]byte
	updated  time.Time
	text     string // released as soon as all earlier segments can be admitted
}

// The committed V3 user segment ID is the handoff ID to Chief. Native
// delegation is discretionary and has a different ID. Keep each source identity
// until Stop so redelivery after an uncertain admission cannot repeat work.
type handoffs struct {
	mu           sync.Mutex
	segments     map[string]segment
	pending      []string
	jobs         chan handoff
	latest       string
	cancelSpeech context.CancelFunc
}

func (h *handoffs) observe(item map[string]any, complete bool) error {
	id, _ := item["id"].(string)
	if strings.TrimSpace(id) == "" || len(id) > 512 || strings.ContainsRune(id, 0) {
		return errors.New("Codex voice segment is missing a valid ID")
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	previous, seen := h.segments[id]
	if !seen {
		if len(h.segments) >= 1024 {
			return errors.New("voice call reached its handoff limit; start a new call")
		}
		if len(h.pending)+len(h.jobs) >= cap(h.jobs) {
			return errors.New("too many pending voice handoffs")
		}
		h.pending = append(h.pending, id)
		h.segments[id] = segment{updated: time.Now()}
		h.latest = id
		if h.cancelSpeech != nil {
			h.cancelSpeech()
		}
	}
	if !complete {
		return nil
	}
	text, ok := item["text"].(string)
	if !ok || len(text) > 64*1024 || strings.ContainsRune(text, 0) {
		return errors.New("invalid completed Codex voice segment")
	}
	digest := sha256.Sum256([]byte(text))
	if previous.complete {
		if previous.digest != digest {
			return errors.New("Codex reused a handoff ID with different speech")
		}
		return nil
	}
	h.segments[id] = segment{complete: true, digest: digest, text: text}
	// V3 can finish a newer transcript first. Reserve queue capacity at
	// first sight so releasing this prefix never blocks the native reader.
	for len(h.pending) > 0 {
		first := h.pending[0]
		s := h.segments[first]
		if !s.complete {
			break
		}
		if strings.TrimSpace(s.text) != "" {
			h.jobs <- handoff{first, s.text}
		}
		s.text = ""
		h.segments[first] = s
		h.pending = h.pending[1:]
	}
	return nil
}

func (h *handoffs) transcribing(id string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if current, ok := h.segments[id]; ok && !current.complete {
		current.updated = time.Now()
		h.segments[id] = current
	}
}

// A provider can acknowledge hearing speech yet leave its timeline segment
// open. Surface that loss of finality without submitting a partial transcript.
func (h *handoffs) stalled(now time.Time) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, s := range h.segments {
		if !s.complete && now.Sub(s.updated) >= 30*time.Second {
			return true
		}
	}
	return false
}

// The native reader can revoke a queued or blocked append as soon as the
// next user segment starts. An append already accepted remotely is never replayed.
func (h *handoffs) speech(reply plugin.VoiceReply) (context.Context, context.CancelFunc, bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if reply.HandoffID != h.latest || !h.segments[h.latest].complete || reply.Context.Err() != nil {
		return nil, nil, false
	}
	ctx, cancel := context.WithCancel(reply.Context)
	h.cancelSpeech = cancel
	return ctx, cancel, true
}
