package voice

import (
	"context"
	"errors"
	"strings"
	"sync"
	"time"
	"unicode"

	"github.com/hupao-creator/Chief/internal/plugins/harness/codex"
)

// V3 accepts appendSpeech while its frontend is talking, but can consume that
// append without speaking it. Serialize at the native assistant timeline, which
// advances independently of the RPC response and the destination's Talk audit.
type playback struct {
	mu       sync.Mutex
	active   map[string]bool
	finished map[string]bool
	pending  *speechConfirmation
	changed  chan struct{}
}

// The native transcript has no append ID. Match the pending Talk's words
// across newly completed segments, including when an acknowledgement shares
// its turn. Keep only the suffix needed to match the next segment.
type speechConfirmation struct {
	want, tail string
	confirmed  bool
}

func (c *speechConfirmation) observe(text string) {
	if c.confirmed || strings.TrimSpace(text) == "" {
		return
	}
	heard := c.tail + speechTerms(text)
	c.confirmed = strings.Contains(heard+" ", c.want+" ")
	c.tail = strings.Clone(heard[max(0, len(heard)-len(c.want)):])
}

// Leading spaces delimit whole words. Han characters can be split across
// native segments without any whitespace in the original Talk.
func speechTerms(text string) string {
	var terms strings.Builder
	inWord := false
	for _, r := range strings.ToLower(text) {
		switch {
		case unicode.Is(unicode.Han, r) || unicode.IsSymbol(r):
			terms.WriteByte(' ')
			terms.WriteRune(r)
			inWord = false
		case unicode.IsLetter(r) || unicode.IsNumber(r) || unicode.IsMark(r) || r == '_':
			if !inWord {
				terms.WriteByte(' ')
			}
			terms.WriteRune(r)
			inWord = true
		default:
			inWord = false
		}
	}
	if terms.Len() == 0 {
		return " " + strings.TrimSpace(text)
	}
	return terms.String()
}

func newPlayback() *playback {
	return &playback{active: make(map[string]bool), finished: make(map[string]bool), changed: make(chan struct{})}
}

func (p *playback) observe(item codex.Map, complete bool) error {
	id, _ := item["id"].(string)
	if id == "" || len(id) > 512 {
		return errors.New("invalid Codex voice playback identity")
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.finished[id] || !complete && p.active[id] {
		return nil
	}
	if len(p.active)+len(p.finished) >= 4096 && !p.active[id] {
		return errors.New("voice call reached its playback limit; start a new call")
	}
	if complete {
		delete(p.active, id)
		p.finished[id] = true
		if p.pending != nil {
			text, _ := item["text"].(string)
			p.pending.observe(text)
		}
	} else {
		p.active[id] = true
	}
	close(p.changed)
	p.changed = make(chan struct{})
	return nil
}

func (p *playback) quiet(ctx context.Context, timeout time.Duration, ready func() bool) error {
	deadline := time.NewTimer(timeout)
	defer deadline.Stop()
	for {
		p.mu.Lock()
		idle := len(p.active) == 0 && ready()
		changed := p.changed
		p.mu.Unlock()
		if idle {
			return ctx.Err()
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-changed:
		case <-deadline.C:
			return errors.New("Codex did not confirm voice playback; the Talk remains in the Chief conversation")
		}
	}
}

func (p *playback) say(ctx context.Context, server nativeServer, thread, text string) error {
	confirmation := &speechConfirmation{want: speechTerms(text)}
	err := p.quiet(ctx, 60*time.Second, func() bool {
		p.pending = confirmation
		return true
	})
	defer func() { p.mu.Lock(); p.pending = nil; p.mu.Unlock() }()
	if err != nil {
		return err
	}
	rpc, finish := context.WithTimeout(ctx, 15*time.Second)
	_, err = server.Call(rpc, "thread/realtime/appendSpeech", codex.Map{"threadId": thread, "text": text})
	finish()
	if err == nil {
		err = p.quiet(ctx, 90*time.Second, func() bool { return confirmation.confirmed })
	}
	return err
}
