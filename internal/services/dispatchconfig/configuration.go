// Package dispatchconfig owns the published ordinary-thread options for a Chief
// profile. Readers never open a native process or inspect provider accounts.
package dispatchconfig

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"sync"

	"github.com/hupao-creator/Chief/internal/core/store"
	"github.com/hupao-creator/Chief/internal/platform/diagnostics"
)

type Publication struct {
	Presentation json.RawMessage `json:"presentation"`
	Options      json.RawMessage `json:"options"`
	Benchmarks   json.RawMessage `json:"benchmarks,omitempty"`
}

type pending struct {
	cancel       context.CancelFunc
	readers      int
	source       string
	done         chan struct{}
	presentation json.RawMessage
	err          error
}

type Configurations struct {
	scope       string
	db          *store.Store
	mu          sync.Mutex
	flights     map[string]*pending
	subscribers map[chan struct{}]struct{}
}

func New(db *store.Store, workspace string) *Configurations {
	return &Configurations{scope: fmt.Sprintf("dispatch-configuration:v1:%x:", sha256.Sum256([]byte(workspace))), db: db, flights: make(map[string]*pending), subscribers: make(map[chan struct{}]struct{})}
}

func (c *Configurations) Read(id string) Publication {
	var p Publication
	_, _ = c.db.Snapshot().Get(c.scope+"provider:"+id, &p)
	return p
}

// Subscribe includes an initial wake. Every wake means read the latest snapshot.
func (c *Configurations) Subscribe() (<-chan struct{}, func()) {
	c.mu.Lock()
	defer c.mu.Unlock()
	ch := make(chan struct{}, 1)
	ch <- struct{}{}
	c.subscribers[ch] = struct{}{}
	return ch, func() { c.mu.Lock(); defer c.mu.Unlock(); delete(c.subscribers, ch) }
}

type Acquire func(context.Context) (json.RawMessage, json.RawMessage, error)

func (c *Configurations) VersionsKey() string { return c.scope + "versions" }

// Update coalesces acquisition for a provider and its current settings. A newer
// source supersedes unfinished work. Only provider publications replace data.
func (c *Configurations) Update(ctx context.Context, id, source string, acquire Acquire, current func(*store.Tx) bool) (json.RawMessage, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	c.mu.Lock()
	f := c.flights[id]
	if f == nil || f.source != source {
		if f != nil {
			f.cancel()
		}
		shared, cancel := context.WithCancel(context.WithoutCancel(ctx))
		f = &pending{source: source, cancel: cancel, done: make(chan struct{})}
		c.flights[id] = f
		go c.acquire(shared, id, f, acquire, current)
	}
	f.readers++
	c.mu.Unlock()
	select {
	case <-f.done:
		return bytes.Clone(f.presentation), f.err
	case <-ctx.Done():
		c.mu.Lock()
		f.readers--
		last := f.readers == 0
		if last {
			f.cancel()
			if c.flights[id] == f {
				delete(c.flights, id)
			}
		}
		c.mu.Unlock()
		if last {
			<-f.done
		}
		return nil, ctx.Err()
	}
}

func (c *Configurations) acquire(ctx context.Context, id string, f *pending, load Acquire, current func(*store.Tx) bool) {
	ctx = diagnostics.EnsureTrace(ctx)
	diagnostics.Event(ctx, "dispatchconfig.acquire", "loading")
	defer func() { diagnostics.End(ctx, "dispatchconfig.acquire", f.err) }()
	defer f.cancel()
	raw, bench, err := load(ctx)
	publication, ready := project(raw, bench)
	c.mu.Lock()
	defer c.mu.Unlock()
	defer close(f.done)
	if c.flights[id] != f {
		f.err = errors.New("provider update superseded")
		return
	}
	delete(c.flights, id)
	if err := ctx.Err(); err != nil {
		f.err = err
		return
	}
	previous := c.Read(id)
	if err != nil || !ready {
		f.presentation, f.err = raw, err
		if len(previous.Presentation) > 0 {
			diagnostics.Event(ctx, "dispatchconfig.acquire", "using_previous_publication")
			f.presentation, f.err = previous.Presentation, nil
		}
		if len(previous.Presentation) == 0 {
			diagnostics.Event(ctx, "dispatchconfig.acquire", "publication_unavailable")
		}
		return
	}
	// Persist context, UI and its change token in the same transaction.
	f.presentation = publication.Presentation
	if bytes.Equal(previous.Presentation, publication.Presentation) && bytes.Equal(previous.Options, publication.Options) && bytes.Equal(previous.Benchmarks, publication.Benchmarks) {
		return
	}
	_, f.err = c.db.Update(ctx, func(tx *store.Tx) error {
		if current != nil && !current(tx) {
			return errors.New("provider settings changed during discovery")
		}
		if err := tx.Put(c.scope+"provider:"+id, publication); err != nil {
			return err
		}
		if bytes.Equal(previous.Presentation, publication.Presentation) {
			return nil
		}
		versions := map[string]string{}
		if _, err := tx.Get(c.VersionsKey(), &versions); err != nil {
			return err
		}
		versions[id] = fmt.Sprintf("%x", sha256.Sum256(publication.Presentation))
		return tx.Put(c.VersionsKey(), versions)
	})
	if f.err == nil && !bytes.Equal(previous.Options, publication.Options) {
		for ch := range c.subscribers {
			select {
			case ch <- struct{}{}:
			default:
			}
		}
	}
}

// AfterCurrent orders an adapter invalidation behind an earlier partial read.
func (c *Configurations) AfterCurrent(ctx context.Context, id string) error {
	c.mu.Lock()
	f := c.flights[id]
	c.mu.Unlock()
	if f != nil {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-f.done:
		}
	}
	return ctx.Err()
}

// Options takes one storage snapshot across every selected provider.
func (c *Configurations) Options(ids []string) json.RawMessage {
	snapshot := c.db.Snapshot()
	selected := map[string]json.RawMessage{}
	for _, id := range ids {
		var p Publication
		if ok, err := snapshot.Get(c.scope+"provider:"+id, &p); ok && err == nil && len(p.Options) > 0 {
			selected[id] = p.Options
		}
	}
	raw, _ := json.Marshal(selected)
	return raw
}
