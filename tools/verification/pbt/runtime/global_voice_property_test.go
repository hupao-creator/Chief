package runtime_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
	core "github.com/hupao-creator/Chief/internal/core/runtime"
	"github.com/hupao-creator/Chief/internal/core/store"
	"github.com/hupao-creator/Chief/internal/platform/transport"
	"github.com/hupao-creator/Chief/internal/services/moku"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

// PBT-MOKU-GLOBAL-VOICE observes the destination's actual admission, tool
// audit, public conversation and retained execution through a non-Codex Harness.
func TestGlobalVoiceAdmissionProperties(t *testing.T) {
	rapidcheck.Check(t, func(t *rapid.T) {
		check := func(err error) {
			t.Helper()
			if err != nil {
				t.Fatal(err)
			}
		}
		ctx, stop := context.WithTimeout(context.Background(), 10*time.Second)
		defer stop()
		root, err := os.MkdirTemp("", "chief-global-voice-pbt-")
		check(err)
		defer os.RemoveAll(root)
		db, err := store.Open(filepath.Join(root, "state.sqlite"))
		check(err)
		defer db.Close()
		peer := &injectedToolPeer{}
		harnesses := map[string]plugin.Harness{"fixture": peer}
		r, err := core.New(ctx, core.Config{Store: db, Harnesses: harnesses, DataDir: root, DefaultCwd: root})
		check(err)
		defer r.Close(context.Background())
		chief, err := r.EnsureMokuThread(ctx, "fixture", nil, root)
		check(err)
		config := chiefToolConfiguration(r, root, harnesses)
		opened := make(chan plugin.GlobalVoice, 1)
		drain, releaseDrain := context.WithCancel(ctx)
		config.RunVoice = func(ctx context.Context, _ string, call plugin.GlobalVoice) error {
			if err := call.Answer("test answer"); err != nil {
				return err
			}
			opened <- call
			<-ctx.Done()
			<-drain.Done()
			return ctx.Err()
		}
		c, err := moku.New(config)
		check(err)
		check(c.Start(ctx, plugin.RuntimeStartContext{}))
		defer c.Stop(context.Background())
		defer releaseDrain()
		r.SetMoku(c)
		start := func() (plugin.GlobalVoice, context.CancelFunc, <-chan error) {
			callCtx, cancel := context.WithCancel(ctx)
			done := make(chan error, 1)
			go func() {
				done <- r.RunGlobalVoice(callCtx, "offer", func(answer string) error {
					if answer != "test answer" {
						return errors.New("wrong answer")
					}
					return nil
				})
			}()
			select {
			case call := <-opened:
				return call, cancel, done
			case err := <-done:
				cancel()
				t.Fatalf("open: %v", err)
			case <-ctx.Done():
				cancel()
				t.Fatal(ctx.Err())
			}
			return plugin.GlobalVoice{}, nil, nil
		}
		call, cancel, done := start()
		defer cancel()
		if err := r.RunGlobalVoice(ctx, "duplicate", nil); err == nil {
			t.Fatal("two clients acquired media")
		}
		words := rapid.SampledFrom([]string{"same words", "重复的请求", "A & <B>"}).Draw(t, "repeated-utterance")
		reply := rapid.SampledFrom([]string{"same reply", "原样\n回复"}).Draw(t, "public-talk")
		rounds := rapid.IntRange(2, 7).Draw(t, "handoffs")
		wantIDs := []string{}
		wantReplies := 0
		for i := range rounds {
			id := fmt.Sprintf("native/%d", i)
			check(call.Submit(ctx, id, words))
			wantIDs = append(wantIDs, id)
			talk := peer.tools.Bindings[slices.IndexFunc(peer.tools.Bindings, func(b plugin.ToolBinding) bool { return b.Name == "talk" })]
			if _, err := talk.Execute(ctx, plugin.ToolCall{CallID: "bad", Arguments: raw(map[string]string{"text": "  "})}); err == nil {
				t.Fatal("invalid Talk succeeded")
			}
			_, err = talk.Execute(ctx, plugin.ToolCall{CallID: id, Arguments: raw(map[string]string{"text": reply})})
			check(err)
			wantReplies++
			if rapid.Bool().Draw(t, "interleaved-typed-input") {
				check(c.Submit(ctx, moku.SubmitRequest{Input: model.AgentInput{Parts: []model.AgentInputPart{{Kind: "text", Text: "typed"}}}}))
				_, err = talk.Execute(ctx, plugin.ToolCall{CallID: "typed", Arguments: raw(map[string]string{"text": reply})})
				check(err)
				wantReplies++
			}
		}
		cancel()
		// A cancelled HTTP lease is no longer a competitor, even while the
		// native relay is still releasing its process. A waiting request can
		// abandon its place without acquiring the profile.
		probe, endProbe := context.WithTimeout(ctx, 10*time.Millisecond)
		err = r.RunGlobalVoice(probe, "cancelled replacement", func(string) error {
			return errors.New("replacement entered before native teardown finished")
		})
		endProbe()
		if !errors.Is(err, context.DeadlineExceeded) {
			t.Fatalf("replacement while previous relay was draining: %v", err)
		}
		releaseDrain()
		next, closeNext, finished := start()
		defer closeNext()
		if err = <-done; !errors.Is(err, context.Canceled) {
			t.Fatalf("stop: %v", err)
		}
		record, err := r.Thread(chief.ID)
		check(err)
		if record.HarnessID != "fixture" || record.Observation.LatestExecution == nil || record.Observation.LatestExecution.Terminal() {
			t.Fatal("ending media interrupted the selected harness")
		}
		gotIDs := []string{}
		var session string
		for _, raw := range record.Transcript {
			var row struct{ VoiceHandoffID, VoiceSessionID, ExecutionID, Content string }
			check(json.Unmarshal(raw, &row))
			if row.VoiceHandoffID != "" {
				if row.Content != words || row.ExecutionID != record.Observation.LatestExecution.ExecutionID || row.VoiceSessionID == "" || session != "" && row.VoiceSessionID != session {
					t.Fatal("incorrect durable target admission")
				}
				session = row.VoiceSessionID
				gotIDs = append(gotIDs, row.VoiceHandoffID)
			}
		}
		if !slices.Equal(gotIDs, wantIDs) {
			t.Fatalf("admitted %v, want %v", gotIDs, wantIDs)
		}
		content, err := r.ReadThreadContent(ctx, chief.ID, transport.ContentScope{Kind: "moku-conversation"}, nil)
		check(err)
		var page struct{ Messages []struct{ Role, Text string } }
		check(json.Unmarshal(content.Value, &page))
		gotReplies := 0
		for _, msg := range page.Messages {
			if msg.Role == "chief" {
				if msg.Text != reply {
					t.Fatalf("unexpected public reply: %q", msg.Text)
				}
				gotReplies++
			}
		}
		if gotReplies != wantReplies {
			t.Fatalf("visible replies = %d, want %d", gotReplies, wantReplies)
		}
		if err := call.Submit(ctx, "late", "stale"); err == nil {
			t.Fatal("accepted a retired voice call")
		}
		select {
		case <-next.Failures:
			t.Fatal("unexpected failure on a replacement call")
		default:
		}
		check(next.Submit(ctx, "last", "check the account"))
		check(r.UpdateThread(ctx, chief.ID, func(record *model.ThreadRecord) error {
			execution := record.Observation.LatestExecution
			at := time.Now().UnixMilli()
			message := "target account refused the request"
			execution.Status, execution.Error, execution.FinishedAt = "failed", &message, &at
			return nil
		}))
		select {
		case failure := <-next.Failures:
			if failure.HandoffID != "last" || failure.Err == nil ||
				failure.Err.Error() != "Chief (fixture): target account refused the request" {
				t.Fatalf("incorrect destination failure: %+v", failure)
			}
		case <-ctx.Done():
			t.Fatal("target failure did not reach the voice caller")
		}
		closeNext()
		<-finished
	})
}
