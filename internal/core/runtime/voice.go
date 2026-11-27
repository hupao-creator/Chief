package runtime

import (
	"context"
	"errors"
)

type voiceLease struct {
	ctx     context.Context
	drained chan struct{}
}

// A media call keeps the service busy but does not reserve task admission.
// A coordinating Harness change can still retire that call through its owner.
func (r *Runtime) RunGlobalVoice(ctx context.Context, offer string, answer func(string) error) error {
	if err := r.begin(); err != nil {
		return err
	}
	defer r.operations.Done()
	ctx, cancel := r.operationContext(ctx)
	defer cancel()
	r.mu.Lock()
	host, ok := r.config.Moku.(interface {
		RunGlobalVoice(context.Context, string, func(string) error) error
	})
	r.mu.Unlock()
	if !ok {
		return errors.New("global Voice Mode is unavailable")
	}
	release, err := r.acquireVoice(ctx)
	if err != nil {
		return err
	}
	defer release()
	return host.RunGlobalVoice(ctx, offer, answer)
}

func (r *Runtime) acquireVoice(ctx context.Context) (func(), error) {
	r.serviceMu.Lock()
	defer r.serviceMu.Unlock()
	for {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		previous := r.voice
		if r.serviceDraining || r.mokuHarnessChanging || previous != nil && previous.ctx.Err() == nil {
			return nil, errors.New("global Voice Mode is busy or the service is restarting")
		}
		if previous == nil {
			break
		}
		// The client can restart as soon as it closes the HTTP lease. Wait
		// for that relay's native process and in-flight admissions to exit.
		r.serviceMu.Unlock()
		select {
		case <-previous.drained:
		case <-ctx.Done():
		}
		r.serviceMu.Lock()
	}
	lease := &voiceLease{ctx: ctx, drained: make(chan struct{})}
	r.voice = lease
	return func() {
		r.serviceMu.Lock()
		r.voice = nil
		close(lease.drained)
		r.serviceMu.Unlock()
	}, nil
}
