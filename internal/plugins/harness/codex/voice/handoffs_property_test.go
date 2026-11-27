package voice

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"
	"testing/synctest"
	"time"

	"github.com/hupao-creator/Chief/internal/core/plugin"
	"github.com/hupao-creator/Chief/internal/plugins/harness/codex"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

type realtimePeer struct {
	notify  func(string, codex.Map, any)
	exit    func(error)
	start   chan codex.Map
	speech  chan string
	session string
	appends int
}

func (p *realtimePeer) SetHandler(h func(string, codex.Map, any), exit func(error)) {
	p.notify = h
	p.exit = exit
}
func (*realtimePeer) Reply(any, codex.Map, error) error { return nil }
func (p *realtimePeer) Call(ctx context.Context, method string, params any) (codex.Map, error) {
	switch method {
	case "thread/realtime/start":
		p.session = params.(codex.Map)["realtimeSessionId"].(string)
		p.start <- params.(codex.Map)
	case "thread/realtime/appendSpeech":
		text := params.(codex.Map)["text"].(string)
		p.speech <- text
		if text == "hold this append" {
			<-ctx.Done()
			return nil, ctx.Err()
		}
		if text == "A new result from Chief." || text == "没有播出的结果" {
			return codex.Map{}, nil // Simulate native acceptance before any playback event.
		}
		p.appends++
		item := codex.Map{"type": "transcriptSegment", "role": "assistant", "realtimeSessionId": p.session,
			"id": fmt.Sprintf("output-%d", p.appends), "text": text}
		if text == "Talk with delayed playback" {
			item["id"] = "slow-playout"
		}
		p.notify("thread/realtime/item/started", codex.Map{"threadId": "relay", "item": item}, nil)
		if text != "Talk with delayed playback" {
			p.notify("thread/realtime/item/completed", codex.Map{"threadId": "relay", "item": item}, nil)
		}
	case "thread/realtime/stop":
	default:
		return nil, fmt.Errorf("unexpected native method %s", method)
	}
	return codex.Map{}, nil
}

func await[T any](t *rapid.T, ctx context.Context, ch <-chan T) T {
	t.Helper()
	select {
	case value := <-ch:
		return value
	case <-ctx.Done():
		t.Fatal("timed out at a voice protocol boundary")
	}
	var zero T
	return zero
}

// PBT-CODEX-VOICE-HANDOFF exercises the running relay through its native RPC
// boundary. The destination observes actual submissions, never the ledger.
func TestVoiceHandoffProperties(t *testing.T) {
	rapidcheck.Check(t, func(rt *rapid.T) {
		synctest.Test(t, func(*testing.T) { exerciseHandoffs(rt) })
	})
}

func exerciseHandoffs(t *rapid.T) {
	timeout, deadline := context.WithTimeout(context.Background(), 100*time.Second)
	defer deadline()
	ctx, stop := context.WithCancel(timeout)
	defer stop()
	peer := &realtimePeer{start: make(chan codex.Map, 1), speech: make(chan string, 8)}
	answer, inputs := make(chan string, 1), make(chan handoff, 32)
	replies := make(chan plugin.VoiceReply, 16)
	done := make(chan error, 1)
	go func() {
		done <- runSession(ctx, peer, "relay", plugin.GlobalVoice{ID: "product-call", Offer: "offer", Answer: func(s string) error { answer <- s; return nil }, Replies: replies,
			Submit: func(ctx context.Context, id, text string) error {
				inputs <- handoff{id, text}
				if text == "reject" {
					return errors.New("target rejected")
				}
				return ctx.Err()
			}})
	}()
	start := await(t, timeout, peer.start)
	session := start["realtimeSessionId"]
	if session == nil || session == "product-call" || start["voiceSessionId"] != "product-call" || start["clientManagedHandoffs"] != true || start["version"] != "v3" {
		t.Fatal("wrong realtime ownership")
	}
	emit := func(method string, params codex.Map) { peer.notify(method, params, nil) }
	if rapid.IntRange(0, 9).Draw(t, "startup-failure") == 0 {
		version, identity := "v3", session
		if rapid.Bool().Draw(t, "old-protocol") {
			version = "v2"
		} else {
			identity = "another-session"
		}
		emit("thread/realtime/started", codex.Map{"threadId": "relay", "version": version, "realtimeSessionId": identity})
		if err := await(t, timeout, done); err == nil || !strings.Contains(err.Error(), "different voice session or protocol") {
			t.Fatalf("incompatible startup: %v", err)
		}
		return
	}
	confirmed := func() {
		emit("thread/realtime/started", codex.Map{"threadId": "relay", "version": "v3", "realtimeSessionId": session})
	}
	sdp := func() { emit("thread/realtime/sdp", codex.Map{"threadId": "relay", "sdp": "answer"}) }
	if rapid.Bool().Draw(t, "sdp-first") {
		sdp()
		confirmed()
	} else {
		confirmed()
		sdp()
	}
	if await(t, timeout, answer) != "answer" {
		t.Fatal("wrong SDP")
	}
	request := func(thread, id, text string) {
		emit("thread/realtime/item/completed", codex.Map{"threadId": thread, "item": codex.Map{"type": "transcriptSegment", "realtimeSessionId": session, "id": id, "role": "user", "text": text}})
	}
	words := rapid.SampledFrom([]string{"repeat", "你好", "<request>&"}).Draw(t, "repeated-speech")
	count := rapid.IntRange(2, 9).Draw(t, "handoffs")
	for i := range count {
		id := fmt.Sprint(i)
		if rapid.Bool().Draw(t, "segment-start") {
			emit("thread/realtime/item/started", codex.Map{"threadId": "relay", "item": codex.Map{"type": "transcriptSegment", "role": "user", "realtimeSessionId": session, "id": id}})
		}
		request("another-thread", id, "wrong owner")
		emit("thread/realtime/itemAdded", codex.Map{"threadId": "relay", "item": codex.Map{"type": "handoff_request", "handoff_id": id, "input_transcript": words}})
		for _, noise := range []codex.Map{
			{"type": "transcriptSegment", "role": "assistant", "realtimeSessionId": session, "id": id, "text": "acknowledgement"},
			{"type": "transcriptSegment", "role": "user", "realtimeSessionId": "expired", "id": id, "text": words},
		} {
			emit("thread/realtime/item/completed", codex.Map{"threadId": "relay", "item": noise})
		}
		emit("thread/realtime/transcript/done", codex.Map{"threadId": "relay", "role": "user", "text": words})
		emit("thread/realtime/item/completed", codex.Map{"threadId": "relay", "item": codex.Map{"type": "turnInputAccepted", "realtimeSessionId": session, "handoffId": id}})
		for range rapid.IntRange(1, 4).Draw(t, "redelivery") {
			request("relay", id, words)
		}
		if i > 0 {
			request("relay", "0", words)
		}
		if got := await(t, timeout, inputs); got != (handoff{id, words}) {
			t.Fatalf("unexpected target input: %+v", got)
		}
		expired, revoke := context.WithCancel(ctx)
		revoke()
		replies <- plugin.VoiceReply{Context: expired, HandoffID: id, Text: "revoked"}
		if i > 0 {
			replies <- plugin.VoiceReply{Context: ctx, HandoffID: "0", Text: "stale"}
		}
		text := "the committed Talk"
		if i+1 < count && rapid.Bool().Draw(t, "overlapping-speech") {
			text = "hold this append"
		}
		replies <- plugin.VoiceReply{Context: ctx, HandoffID: id, Text: text}
		if got := await(t, timeout, peer.speech); got != text {
			t.Fatalf("unexpected speech %q", got)
		}
	}
	// A native ack and then a playout each occupy the one speech lane.
	// Wait for the actual relay to block before releasing either one.
	assistant := func(method, id, text string) {
		emit("thread/realtime/item/"+method, codex.Map{"threadId": "relay", "item": codex.Map{
			"type": "transcriptSegment", "role": "assistant", "realtimeSessionId": session, "id": id, "text": text}})
	}
	assistant("started", "native-ack", "")
	last := fmt.Sprint(count - 1)
	replies <- plugin.VoiceReply{Context: ctx, HandoffID: last, Text: "Talk with delayed playback"}
	replies <- plugin.VoiceReply{Context: ctx, HandoffID: last, Text: words}
	synctest.Wait()
	if len(peer.speech) != 0 {
		t.Fatal("Talk interrupted the native acknowledgement")
	}
	assistant("completed", "native-ack", "heard")
	if got := await(t, timeout, peer.speech); got != "Talk with delayed playback" {
		t.Fatalf("first Talk after acknowledgement: %q", got)
	}
	synctest.Wait()
	if len(peer.speech) != 0 {
		t.Fatal("the second Talk interrupted the first")
	}
	assistant("completed", "slow-playout", "Talk with delayed playback")
	if got := await(t, timeout, peer.speech); got != words {
		t.Fatalf("second Talk after playout: %q", got)
	}
	// An acknowledgement can start after a successful append, even when the
	// peer never plays that append. Only a transcript containing the Talk
	// should release the next append.
	const delayed = "A new result from Chief."
	replies <- plugin.VoiceReply{Context: ctx, HandoffID: last, Text: delayed}
	replies <- plugin.VoiceReply{Context: ctx, HandoffID: last, Text: words}
	if got := await(t, timeout, peer.speech); got != delayed {
		t.Fatalf("missing fast Talk: %q", got)
	}
	assistant("started", "late-ack", "")
	assistant("completed", "late-ack", "I heard you.")
	synctest.Wait()
	if len(peer.speech) != 0 {
		t.Fatal("an unrelated acknowledgement confirmed the pending Talk")
	}
	assistant("completed", "talk-start", "A new")
	assistant("completed", "talk-end", "result from Chief!")
	if got := await(t, timeout, peer.speech); got != words {
		t.Fatalf("next Talk after confirmed speech: %q", got)
	}

	// The next segment starts before its predecessor finishes. Both
	// destination admissions survive, but only the newer one may speak.
	for _, id := range []string{"first", "blank", "second"} {
		emit("thread/realtime/item/started", codex.Map{"threadId": "relay", "item": codex.Map{
			"type": "transcriptSegment", "role": "user", "realtimeSessionId": session, "id": id}})
	}
	request("relay", "blank", "  ")
	if rapid.Bool().Draw(t, "second-transcript-finishes-first") {
		request("relay", "second", words)
		synctest.Wait()
		if len(inputs) != 0 {
			t.Fatal("newer transcript overtook an incomplete earlier utterance")
		}
		request("relay", "first", words)
	} else {
		request("relay", "first", words)
		request("relay", "second", words)
	}
	for _, id := range []string{"first", "second"} {
		if got := await(t, timeout, inputs); got != (handoff{id, words}) {
			t.Fatalf("incorrect overlapping handoff: %+v", got)
		}
		replies <- plugin.VoiceReply{Context: ctx, HandoffID: id, Text: id}
	}
	if got := await(t, timeout, peer.speech); got != "second" {
		t.Fatalf("superseded speech: %s", got)
	}
	var expected string
	switch rapid.IntRange(0, 6).Draw(t, "retirement") {
	case 0:
		request("relay", "0", "conflict")
		expected = "reused"
	case 1:
		request("relay", "rejected", "reject")
		expected = "target rejected"
		if got := await(t, timeout, inputs); got.id != "rejected" {
			t.Fatalf("wrong rejection: %+v", got)
		}
	case 2:
		emit("thread/realtime/error", codex.Map{"threadId": "relay", "message": "provider failure"})
		expected = "provider failure"
	case 3:
		peer.exit(errors.New("process exit"))
		expected = "process exit"
	case 4:
		stop()
		expected = "context canceled"
	case 5:
		replies <- plugin.VoiceReply{Context: ctx, HandoffID: "first", Failure: errors.New("stale error")}
		replies <- plugin.VoiceReply{Context: ctx, HandoffID: "second", Failure: errors.New("target account failed")}
		expected = "target account failed"
	case 6:
		replies <- plugin.VoiceReply{Context: ctx, HandoffID: "second", Text: "没有播出的结果"}
		if got := await(t, timeout, peer.speech); got != "没有播出的结果" {
			t.Fatalf("unexpected pending Talk: %q", got)
		}
		assistant("completed", "only-ack", "好的")
		expected = "did not confirm voice playback"
	}
	if err := await(t, timeout, done); err == nil || !strings.Contains(err.Error(), expected) {
		t.Fatalf("wrong call termination: %v", err)
	}
	request("relay", "late", "late")
	select {
	case v := <-inputs:
		t.Fatalf("late or duplicate target input %+v", v)
	default:
	}
}

// startupPeer supplies independent account catalog and native admission
// outcomes. prepareThread must not grant those peers a task-capable relay.
type startupPeer struct {
	voices, fallback, luna bool
	confirmation           string
	request                codex.Map
}

func (p *startupPeer) Call(_ context.Context, method string, params any) (codex.Map, error) {
	switch method {
	case "thread/realtime/listVoices":
		v3 := []any{}
		if p.voices {
			v3 = append(v3, "alloy")
		}
		return codex.Map{"voices": codex.Map{"v3": v3}}, nil
	case "model/list":
		data := []any{codex.Map{"model": "account-default", "isDefault": p.fallback}}
		if p.luna {
			data = append(data, codex.Map{"model": "gpt-6-luna"})
		}
		return codex.Map{"data": data, "nextCursor": nil}, nil
	case "config/read", "skills/list":
		return codex.Map{}, nil
	case "thread/start":
		p.request = params.(codex.Map)
		result := codex.Map{"thread": codex.Map{"id": "native"}, "model": p.request["model"], "modelProvider": "openai",
			"sandbox": codex.Map{"type": "readOnly"}, "approvalPolicy": "never"}
		if p.confirmation != "" {
			delete(result, p.confirmation)
		}
		return result, nil
	}
	return nil, fmt.Errorf("unexpected startup call %s", method)
}

func TestVoiceStartupProperties(t *testing.T) {
	rapidcheck.Check(t, func(t *rapid.T) {
		peer := &startupPeer{voices: rapid.Bool().Draw(t, "v3"), luna: rapid.Bool().Draw(t, "luna"),
			fallback:     rapid.Bool().Draw(t, "advertised-default"),
			confirmation: rapid.SampledFrom([]string{"", "", "thread", "model", "modelProvider", "sandbox", "approvalPolicy"}).Draw(t, "omitted-confirmation")}
		id, err := prepareThread(context.Background(), peer, "/private/voice")
		eligible := peer.voices && (peer.luna || peer.fallback)
		if (peer.request != nil) != eligible || (err == nil) != (eligible && peer.confirmation == "") {
			t.Fatalf("admitted incompatible native startup: id=%s err=%v request=%v", id, err, peer.request)
		}
		if peer.request != nil {
			want := "account-default"
			if peer.luna {
				want = "gpt-6-luna"
			}
			config := peer.request["config"].(codex.Map)
			if peer.request["model"] != want || peer.request["allowProviderModelFallback"] != false ||
				peer.request["sandbox"] != "read-only" || peer.request["approvalPolicy"] != "never" ||
				config["features"].(codex.Map)["shell_tool"] != false || config["web_search"] != "disabled" {
				t.Fatal("relay did not request the advertised model and isolated tools")
			}
		}
	})
}
