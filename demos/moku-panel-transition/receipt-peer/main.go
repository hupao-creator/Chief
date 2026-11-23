// The native Composer replay uses the production HTTP executor and ReceiptStore.
// Only the business handler and the timing of its result are fixtures.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/platform/profile"
	"github.com/hupao-creator/Chief/internal/platform/transport"
	"github.com/hupao-creator/Chief/internal/plugins/harness/codex"
)

type host struct {
	calls   *os.File
	forks   atomic.Uint64
	steerMu sync.Mutex
	initial codex.Map
	state   codex.Map
}

func (*host) HasChannel(channel string) bool {
	switch channel {
	case "thread:fork", "thread:follow-up", "moku:submit", "harness:detect-installations":
		return true
	}
	return false
}

func (*host) SubscribeMutations(func(json.RawMessage)) func() { return func() {} }

func (*host) ReadThreadContent(context.Context, string, transport.ContentScope, *int64) (*transport.ContentSnapshot, error) {
	return nil, fmt.Errorf("unexpected content read")
}

func (h *host) Invoke(ctx context.Context, channel string, args []json.RawMessage) (any, error) {
	if channel == "harness:detect-installations" {
		return []any{}, nil
	}
	var next codex.Map
	var target string
	if channel == "thread:follow-up" || channel == "moku:submit" {
		var request struct {
			ThreadID string    `json:"threadId"`
			Input    codex.Map `json:"input"`
		}
		if err := json.Unmarshal(args[0], &request); err != nil {
			return nil, err
		}
		target = request.ThreadID
		if channel == "moku:submit" {
			mode, err := os.ReadFile("mode")
			if err != nil {
				return nil, err
			}
			if string(mode) == "hold-chief" {
				target = "chief"
			}
		}
		if target == "steer-reader" || target == "chief" {
			h.steerMu.Lock()
			defer h.steerMu.Unlock()
			state := h.state
			if target == "chief" {
				state = h.initial
			}
			rowID := model.FollowUpRowID(ctx)
			if rowID == "" {
				return nil, fmt.Errorf("missing transport row identity")
			}
			next = codex.AppendFollowUp(state, "E", request.Input, time.Now().UnixMilli(), "msg-"+rowID, rowID)
			if err := writeSteerState(target+"-next", next); err != nil {
				return nil, err
			}
		}
	}
	if err := json.NewEncoder(h.calls).Encode(map[string]any{"channel": channel, "args": args}); err != nil {
		return nil, err
	}
	for {
		mode, err := os.ReadFile("mode")
		if err != nil {
			return nil, err
		}
		switch string(mode) {
		case "lose", "hold", "hold-chief":
		case "lose-fork":
			if channel != "thread:fork" {
				return nil, fmt.Errorf("unexpected %s before fork", channel)
			}
		case "lose-followup":
			if channel == "thread:fork" {
				return h.branch(), nil
			}
		case "reject", "direct-reject":
			return nil, model.NewError("REJECTED", "Fixture rejected the input")
		case "execution-changed":
			var request struct {
				ExpectedExecutionID string `json:"expectedExecutionId"`
			}
			if err := json.Unmarshal(args[0], &request); err != nil {
				return nil, err
			}
			if request.ExpectedExecutionID != "" {
				return nil, model.NewError("EXECUTION_CHANGED", "Fixture checkpoint changed")
			}
			fallthrough
		case "accepted":
			if channel == "thread:fork" {
				return h.branch(), nil
			}
			if target == "steer-reader" && next != nil {
				h.state = next
			}
			if channel == "moku:submit" {
				return nil, nil
			}
			return map[string]string{"executionId": "E"}, nil
		default:
			return nil, fmt.Errorf("unexpected fixture mode %q", mode)
		}
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(5 * time.Millisecond):
		}
	}
}

func writeSteerState(name string, state codex.Map) error {
	raw, err := json.Marshal(state)
	if err != nil {
		return err
	}
	return os.WriteFile("steer-"+name+".json", raw, 0600)
}

func (h *host) branch() map[string]string {
	return map[string]string{"threadId": fmt.Sprintf("fixture-branch-%d", h.forks.Add(1))}
}

func run() error {
	dir, err := os.Getwd()
	if err != nil || filepath.Base(dir) != "workspace" || !strings.HasPrefix(filepath.Base(filepath.Dir(dir)), "chief-native-replay-") {
		return fmt.Errorf("receipt peer requires a disposable native replay workspace")
	}
	p, err := profile.Resolve(profile.Options{DataDir: filepath.Join(dir, "server-profile"), HomeDir: dir})
	if err != nil {
		return err
	}
	owner, err := profile.Acquire(p)
	if err != nil {
		return err
	}
	defer owner.Release()
	calls, err := os.OpenFile("handler-calls.jsonl", os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	defer calls.Close()
	state := codex.StageExecution(codex.EmptyState(1), "E", codex.Map{"parts": []any{codex.Map{"kind": "text", "text": "Initial instruction"}}}, 2, nil)
	if err := writeSteerState("initial", state); err != nil {
		return err
	}
	working := codex.ReduceEvent(state, "E", codex.Map{"type": "status", "label": "Processing request"})
	if err := writeSteerState("working", working); err != nil {
		return err
	}
	server, err := transport.Start(transport.Options{Profile: p, Epoch: owner.Epoch, Host: &host{calls: calls, state: state, initial: state}})
	if err != nil {
		return err
	}
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = server.Close(ctx)
	}()
	if err := json.NewEncoder(os.Stdout).Encode(server.Connection); err != nil {
		return err
	}
	_, err = io.Copy(io.Discard, os.Stdin)
	return err
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
