package runtime

import "context"

// A command lease pins the shared gate before its caller starts waiting. Never
// remove a gate merely because its thread was deleted: a waiter may still own
// a reference to it and must serialize with subsequent callers for that ID.
type threadCommandLock struct {
	held  chan struct{}
	users int // protected by Runtime.mu
}

type threadCommandLease struct {
	runtime *Runtime
	id      string
	lock    *threadCommandLock
}

func (r *Runtime) threadLock(id string) *threadCommandLease {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.locks == nil {
		r.locks = map[string]*threadCommandLock{}
	}
	lock := r.locks[id]
	if lock == nil {
		lock = &threadCommandLock{held: make(chan struct{}, 1)}
		r.locks[id] = lock
	}
	lock.users++
	return &threadCommandLease{runtime: r, id: id, lock: lock}
}

// Each lease is used for one Lock/Unlock pair.
func (l *threadCommandLease) Lock() { l.lock.held <- struct{}{} }

// A history query must be able to leave the queue while a source command is busy.
func (l *threadCommandLease) LockContext(ctx context.Context) error {
	select {
	case l.lock.held <- struct{}{}:
		if err := ctx.Err(); err != nil {
			l.Unlock()
			return err
		}
		return nil
	case <-ctx.Done():
		l.release()
		return ctx.Err()
	}
}

// A destructive operation must reject a busy command (including a native
// history read) instead of queuing behind it and acting later.
func (l *threadCommandLease) TryLock() bool {
	select {
	case l.lock.held <- struct{}{}:
		return true
	default:
		l.release()
		return false
	}
}
func (l *threadCommandLease) Unlock() {
	<-l.lock.held
	l.release()
}
func (l *threadCommandLease) release() {
	l.runtime.mu.Lock()
	defer l.runtime.mu.Unlock()
	l.lock.users--
	if l.lock.users == 0 {
		delete(l.runtime.locks, l.id)
	}
}

func (r *Runtime) cancellationState(id string) (*threadCancellation, func()) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.cancellationStates == nil {
		r.cancellationStates = map[string]*threadCancellation{}
	}
	state := r.cancellationStates[id]
	if state == nil {
		state = &threadCancellation{claims: map[*sendClaim]struct{}{}}
		r.cancellationStates[id] = state
	}
	state.users++
	return state, func() {
		r.mu.Lock()
		defer r.mu.Unlock()
		state.users--
		r.pruneCancellationStateLocked(id, state)
	}
}

func (r *Runtime) pruneCancellationStateLocked(id string, state *threadCancellation) {
	if state.users != 0 {
		return
	}
	// Keep identity/closedTarget for live sessions. Snapshot.Has does not enter
	// the store writer, so this remains safe while holding the runtime mutex.
	snapshot := r.config.Store.Snapshot()
	if !snapshot.Has("thread:"+id) && !snapshot.Has("private-session-index:"+id) {
		delete(r.cancellationStates, id)
	}
}

func (r *Runtime) pruneCancellationState(id string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if state := r.cancellationStates[id]; state != nil {
		r.pruneCancellationStateLocked(id, state)
	}
}

// Run after removing durable records, including history replacement. Outstanding
// claims/waiters retain their gates and perform the final cleanup on release.
func (r *Runtime) pruneCancellationStates() {
	r.mu.Lock()
	defer r.mu.Unlock()
	for id, state := range r.cancellationStates {
		r.pruneCancellationStateLocked(id, state)
	}
}
