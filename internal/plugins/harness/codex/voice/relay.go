// Package voice adapts Codex realtime V3 to a single, global Chief conversation.
package voice

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"os"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/hupao-creator/Chief/internal/core/plugin"
	"github.com/hupao-creator/Chief/internal/platform/diagnostics"
	"github.com/hupao-creator/Chief/internal/plugins/harness/codex"
)

type Relay struct {
	Codex         *codex.Adapter
	TemporaryRoot string
}

const frontend = "You are the voice interface for Chief. The client automatically sends each completed user utterance to Chief. Acknowledge hearing the user briefly, then wait. Never answer a task, start work or promise a result."
const backing = "You are the transport for Chief's voice session. The client delivers completed user speech directly to Chief. Do not perform the task, call tools, or provide a substantive answer."

// Run owns a fresh native process and disposable native home for the entire call.
// The returned error retains native startup, protocol, admission or exit detail.
func (r Relay) Run(ctx context.Context, executable string, call plugin.GlobalVoice) (failure error) {
	diagnostics.Event(ctx, "codex.voice_relay", "starting")
	defer func() { diagnostics.End(ctx, "codex.voice_relay", failure) }()
	dir, err := os.MkdirTemp(r.TemporaryRoot, "chief-voice-")
	if err != nil {
		return err
	}
	defer func() { failure = errors.Join(failure, os.RemoveAll(dir)) }()
	startup, finishStartup := context.WithTimeout(ctx, 90*time.Second)
	defer finishStartup()
	server, err := r.Codex.OpenSubscriptionServer(startup, dir, executable)
	if err != nil {
		diagnostics.Event(ctx, "codex.voice_relay", "native_start_failed")
		return err
	}
	defer func() { failure = errors.Join(failure, server.Close()) }()
	thread, err := prepareThread(startup, server, dir)
	if err != nil {
		diagnostics.Event(ctx, "codex.voice_relay", "native_admission_failed")
		return err
	}
	return runSession(ctx, server, thread, call)
}

type nativeServer interface {
	codex.CatalogTransport
	SetHandler(func(string, codex.Map, any), func(error))
	Reply(any, codex.Map, error) error
}

func prepareThread(ctx context.Context, server codex.CatalogTransport, dir string) (string, error) {
	voices, err := server.Call(ctx, "thread/realtime/listVoices", codex.Map{})
	if err != nil {
		return "", fmt.Errorf("list Codex realtime voices: %w", err)
	}
	inventory, _ := voices["voices"].(map[string]any)
	v3, _ := inventory["v3"].([]any)
	if !slices.ContainsFunc(v3, func(value any) bool {
		name, _ := value.(string)
		return strings.TrimSpace(name) != ""
	}) {
		return "", errors.New("Codex does not advertise V3 voices")
	}
	models, err := codex.ListModels(ctx, server)
	if err != nil {
		return "", err
	}
	// The backing model has no task authority. Prefer the lightweight relay
	// when offered, otherwise use the account's explicitly advertised default.
	selected := "gpt-6-luna"
	if preferred := codex.SelectModel(models, selected); preferred != nil {
		selected = preferred["value"].(string)
	} else {
		selected = ""
		for _, model := range models {
			if model["isDefault"] == true {
				if selected != "" {
					return "", errors.New("Codex advertises multiple default voice relay models")
				}
				selected, _ = model["value"].(string)
			}
		}
		if selected == "" {
			return "", errors.New("Codex has no available voice relay model or advertised default")
		}
	}
	config, err := codex.ExclusiveToolsConfig(ctx, server, dir)
	if err != nil {
		return "", err
	}
	result, err := server.Call(ctx, "thread/start", codex.Map{
		// Use the native V3 timeline in the call-private home, which Close removes.
		"cwd": dir, "model": selected, "allowProviderModelFallback": false,
		"ephemeral": false, "experimentalRawEvents": true, "serviceName": "chief_desktop",
		"approvalPolicy": "never", "sandbox": "read-only", "config": config, "developerInstructions": backing,
	})
	if err != nil {
		return "", fmt.Errorf("start Codex voice relay: %w", err)
	}
	thread, _ := result["thread"].(map[string]any)
	id, _ := thread["id"].(string)
	sandbox, _ := result["sandbox"].(map[string]any)
	if id == "" || result["model"] != selected || result["modelProvider"] != "openai" ||
		result["approvalPolicy"] != "never" || sandbox["type"] != "readOnly" {
		return "", errors.New("Codex did not confirm the requested relay model, provider and read-only permission policy")
	}
	return id, nil
}

type notification struct {
	method string
	params codex.Map
}

func runSession(parent context.Context, server nativeServer, thread string, call plugin.GlobalVoice) error {
	ctx, cancel := context.WithCancelCause(parent)
	defer cancel(nil)
	var id [16]byte
	rand.Read(id[:])
	id[6] = id[6]&0x0f | 0x40
	id[8] = id[8]&0x3f | 0x80
	session := fmt.Sprintf("%x-%x-%x-%x-%x", id[:4], id[4:6], id[6:8], id[8:10], id[10:])
	events := make(chan notification, 8)
	requests := &handoffs{segments: make(map[string]segment), jobs: make(chan handoff, 32)}
	server.SetHandler(func(method string, p codex.Map, request any) {
		if ctx.Err() != nil {
			return
		}
		if request != nil {
			err := errors.New("the Codex voice relay cannot execute tools or answer approval requests")
			cancel(err)
			_ = server.Reply(request, nil, err)
			return
		}
		if p["threadId"] != thread {
			return
		}
		switch method {
		case "thread/realtime/closed", "thread/realtime/error":
			detail, _ := p["message"].(string)
			if detail == "" {
				detail, _ = p["reason"].(string)
			}
			cancel(fmt.Errorf("Codex %s: %s", method, detail))
			return
		case "model/rerouted":
			cancel(errors.New("Codex changed the admitted relay model"))
			return
		case "thread/realtime/item/transcript/delta":
			id, _ := p["itemId"].(string)
			requests.transcribing(id)
			return
		case "thread/realtime/item/started", "thread/realtime/item/completed":
			item, _ := p["item"].(map[string]any)
			if item["type"] != "transcriptSegment" || item["realtimeSessionId"] != session {
				return
			}
			if item["role"] != "user" {
				return
			}
			if err := requests.observe(item, method == "thread/realtime/item/completed"); err != nil {
				cancel(err)
			}
			return
		case "turn/completed":
			turn, _ := p["turn"].(map[string]any)
			if turn["status"] == "failed" {
				failure, _ := turn["error"].(map[string]any)
				message, _ := failure["message"].(string)
				cancel(fmt.Errorf("Codex voice relay turn failed: %s", message))
			}
			return
		case "thread/realtime/started":
			if p["version"] != "v3" || p["realtimeSessionId"] != session {
				cancel(errors.New("Codex confirmed a different voice session or protocol"))
				return
			}
		case "thread/realtime/sdp":
		default:
			return
		}
		select {
		case events <- notification{method, p}:
		default:
			cancel(errors.New("Codex voice event queue is full"))
		}
	}, cancel)
	start, started := context.WithTimeout(ctx, 45*time.Second)
	_, err := server.Call(start, "thread/realtime/start", codex.Map{
		"threadId": thread, "realtimeSessionId": session, "voiceSessionId": call.ID, "version": "v3",
		"transport": codex.Map{"type": "webrtc", "sdp": call.Offer}, "outputModality": "audio",
		"clientManagedHandoffs": true, "delegationAckFiller": true, "flushTranscriptTailOnSessionEnd": false,
		"includeStartupContext": false, "prompt": frontend, "initialItems": []any{codex.Map{"role": "developer", "text": frontend}},
	})
	started()
	if err != nil {
		return fmt.Errorf("start Codex realtime V3: %w", err)
	}
	defer func() {
		stop, done := context.WithTimeout(context.Background(), 2*time.Second)
		defer done()
		_, _ = server.Call(stop, "thread/realtime/stop", codex.Map{"threadId": thread})
	}()
	if err := connect(ctx, events, call.Answer); err != nil {
		return err
	}
	var workers sync.WaitGroup
	workers.Go(func() {
		for {
			select {
			case <-ctx.Done():
				return
			case h := <-requests.jobs:
				if ctx.Err() != nil {
					return
				}
				diagnostics.Event(ctx, "codex.voice_relay", "utterance_ready")
				if err := call.Submit(ctx, h.id, h.text); err != nil {
					cancel(fmt.Errorf("Chief voice handoff %s: %w", h.id, err))
					return
				}
			}
		}
	})
	defer func() { cancel(nil); workers.Wait() }()
	watch := time.NewTicker(2 * time.Second)
	defer watch.Stop()
	for {
		select {
		case <-ctx.Done():
			return context.Cause(ctx)
		case now := <-watch.C:
			requests.expireStalled(now)
		case failure := <-call.Failures:
			if ctx.Err() != nil {
				return context.Cause(ctx)
			}
			if failure.Context.Err() == nil && requests.current(failure.HandoffID) {
				diagnostics.Event(ctx, "codex.voice_relay", "destination_failed")
				return failure.Err
			}
		}
	}
}

// Both confirmations belong to this dedicated connection. V3 can deliver SDP
// before the started notification or before the start RPC's empty response.
func connect(ctx context.Context, events <-chan notification, answer func(string) error) error {
	deadline := time.NewTimer(30 * time.Second)
	defer deadline.Stop()
	started := false
	var sdp string
	for !started || sdp == "" {
		select {
		case <-ctx.Done():
			return context.Cause(ctx)
		case <-deadline.C:
			return errors.New("Codex did not confirm realtime V3 and a WebRTC answer")
		case e := <-events:
			if e.method == "thread/realtime/started" {
				started = true
			} else {
				value, _ := e.params["sdp"].(string)
				if strings.TrimSpace(value) == "" || len(value) > 128000 || sdp != "" && value != sdp {
					return errors.New("invalid Codex voice SDP answer")
				}
				sdp = value
			}
		}
	}
	if ctx.Err() != nil {
		return context.Cause(ctx)
	}
	return answer(sdp)
}
