// Measure OpenCode's production renderer, including its canonical-state decoder.
package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"runtime"
	"strings"
	"time"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/plugins/harness/opencode"
)

func main() {
	state := &opencode.State{Version: opencode.StateVersion}
	for i := 0; i < 128; i++ {
		id := fmt.Sprintf("run-%d", i)
		end := int64(i + 1)
		state.Executions = append(state.Executions, &model.PublicExecution{
			ExecutionID: id, Status: "completed", StartedAt: int64(i), FinishedAt: &end,
		})
		state.Messages = append(state.Messages,
			&opencode.Message{ID: "tool-" + id, ExecutionID: id, Role: "tool", ToolCallID: id,
				ToolName: "inspect", Arguments: map[string]any{"path": "./fixture"}, Result: strings.Repeat("detail. ", 1024)},
			&opencode.Message{ID: "reply-" + id, ExecutionID: id, Role: "assistant", Status: "complete",
				Parts: []opencode.Part{{Type: "text", Text: "Result for " + id}}})
		state.LatestExecutionID = &id
	}
	raw, err := json.Marshal(state)
	if err != nil {
		panic(err)
	}
	scopes := []model.RendererScope{{Kind: "overview"}, {Kind: "thread"}, {Kind: "turn", Key: "run-127"},
		{Kind: "turn", Key: "run-0"}, {Kind: "execution", Key: "run-0"}, {Kind: "thread"}}
	out := json.NewEncoder(os.Stdout)
	for i, scope := range scopes {
		runtime.GC()
		var before, after runtime.MemStats
		runtime.ReadMemStats(&before)
		start := time.Now()
		result, err := (opencode.StateAdapter{}).ProjectRenderer(raw, scope)
		elapsed := time.Since(start)
		runtime.ReadMemStats(&after)
		if err != nil {
			panic(err)
		}
		if err := out.Encode(map[string]any{"step": i, "scope": scope, "sourceBytes": len(raw),
			"ns": elapsed.Nanoseconds(), "allocatedBytes": after.TotalAlloc - before.TotalAlloc,
			"allocations": after.Mallocs - before.Mallocs, "resultBytes": len(result),
			"sha256": fmt.Sprintf("%x", sha256.Sum256(result))}); err != nil {
			panic(err)
		}
	}
}
