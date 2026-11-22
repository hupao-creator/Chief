//go:build chief_transcript_replay

// Feed offline protocol frames to the installed adapter implementations and
// write their actual renderer inputs for the native half of the replay.
package main

import (
	"bufio"
	"bytes"
	"embed"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
	"github.com/hupao-creator/Chief/internal/plugins/harness/claude"
	"github.com/hupao-creator/Chief/internal/plugins/harness/codex"
	"github.com/hupao-creator/Chief/internal/plugins/harness/opencode"
	"github.com/hupao-creator/Chief/internal/plugins/harness/pi"
)

//go:embed *.jsonl retained/*.json
var frames embed.FS

type feed func(map[string]any) (json.RawMessage, error)

func openCodeFeed() feed {
	state, err := opencode.DecodeState(nil)
	check(err)
	state.NativeSessionID = "primary"
	check(state.Begin("run", 1))
	state.Messages = append(state.Messages, &opencode.Message{ID: "initial", ExecutionID: "run", NativeSessionID: "primary",
		Role: "user", Presentation: "ordinary", Text: "Initial instruction"})
	return func(frame map[string]any) (json.RawMessage, error) {
		switch {
		case frame == nil:
		case frame["steer"] != nil:
			state.SteerInputs = map[string]opencode.SteerInput{"follow": {
				RowID: "steer:fixture", ExecutionID: "run", NativeSessionID: "primary",
				Presentation: "ordinary", Text: frame["steer"].(string), CreatedAt: 2,
			}}
			event := opencode.Event{Type: "session.inbox.enqueued", Data: opencode.Object{
				"sessionID": "primary", "inboxID": "follow", "item": opencode.Object{"type": "user"},
			}}
			check(state.Reduce(event, "run"))
		case frame["history"] != nil:
			state.MergeMessages(frame["history"].([]any), "primary", "run", false)
		case frame["settle"] != nil:
			reason, _ := frame["error"].(string)
			state.Settle("run", frame["settle"].(string), 100, reason)
		default:
			raw, err := json.Marshal(frame)
			if err != nil {
				return nil, err
			}
			var event opencode.Event
			if err := json.Unmarshal(raw, &event); err != nil {
				return nil, err
			}
			if err := state.Reduce(event, "run"); err != nil {
				return nil, err
			}
		}
		return state.Encode(), nil
	}
}

func check(err error) {
	if err != nil {
		panic(err)
	}
}

func main() {
	directory := os.Args[1]
	for _, h := range []struct {
		id, row string
		adapter plugin.SessionStateAdapter
		start   func() feed
	}{
		{"codex", "turn:run", codex.NewSessionStateAdapter(), func() feed { return codex.NewTranscriptReplay() }},
		{"claude", "run", claude.StateAdapter{}, func() feed { return claude.NewTranscriptReplay() }},
		{"pi", "run", pi.New(plugin.HostContext{}).SessionState(), func() feed { return pi.NewTranscriptReplay() }},
		{"opencode", "run", opencode.StateAdapter{}, openCodeFeed},
	} {
		for _, outcome := range []string{"success", "failure", "waiting"} {
			input, err := frames.Open(h.id + ".jsonl")
			check(err)
			advance := h.start()
			scan := bufio.NewScanner(input)
			var raw json.RawMessage
			for scan.Scan() {
				var frame map[string]any
				check(json.Unmarshal(scan.Bytes(), &frame))
				if when, ok := frame["when"].(string); ok {
					if when != outcome {
						continue
					}
					delete(frame, "when")
				}
				stage, checkpoint := frame["sample"].(string)
				if !checkpoint {
					raw, err = advance(frame)
					check(err)
					continue
				}
				if outcome == "failure" && stage != "failed" || outcome == "waiting" && stage != "waiting" {
					continue
				}
				if stage == "reopen" {
					path := filepath.Join(directory, h.id+"-session.json")
					check(os.WriteFile(path, raw, 0600))
					raw, err = os.ReadFile(path)
					check(err)
				}
				writeSample(directory, h.id, h.row, stage, h.adapter, raw)
				if stage == "waiting" {
					break
				}
			}
			check(scan.Err())
			check(input.Close())
		}
		if h.id == "pi" || h.id == "claude" {
			data, err := frames.ReadFile(h.id + "-parts.jsonl")
			check(err)
			advance := h.start()
			var raw json.RawMessage
			for frame := range bytes.Lines(data) {
				var event map[string]any
				check(json.Unmarshal(frame, &event))
				raw, err = advance(event)
				check(err)
			}
			writeSample(directory, h.id, h.row, "parts", h.adapter, raw)
		}
		retained, err := frames.ReadFile("retained/" + h.id + ".json")
		check(err)
		writeSample(directory, h.id, h.row, "retained", h.adapter, retained)
	}
}

func writeSample(directory, id, row, stage string, adapter plugin.SessionStateAdapter, raw json.RawMessage) {
	observation, err := adapter.Project(raw)
	check(err)
	sample := map[string]any{"harness": id, "stage": stage, "rowKey": row, "observation": observation}
	for _, scope := range []string{"thread", "turn", "execution"} {
		projection, err := adapter.ProjectRenderer(raw, model.RendererScope{Kind: scope, Key: row})
		if err != nil {
			panic(fmt.Errorf("%s %s %s: %w", id, stage, scope, err))
		}
		sample[scope] = projection
	}
	if stage == "retained" && id == "claude" {
		value, err := adapter.ProjectRenderer(raw, model.RendererScope{Kind: "execution", Key: "fork-history"})
		check(err)
		sample["fork"] = value
	}
	data, err := json.Marshal(sample)
	check(err)
	check(os.WriteFile(filepath.Join(directory, id+"-"+stage+".json"), data, 0600))
}
