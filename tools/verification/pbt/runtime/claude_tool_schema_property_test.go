package runtime_test

import (
	"encoding/json"
	"testing"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/plugins/harness/claude"
	"github.com/hupao-creator/Chief/internal/services/moku"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"github.com/santhosh-tekuri/jsonschema/v6"
	"pgregory.net/rapid"
)

// PBT-MOKU-CLAUDE-TOOLS: internal/plugins/harness/claude/README.md#chief-tool-schemas
func TestClaudeToolSchemaProperties(t *testing.T) {
	rapidcheck.Check(t, func(t *rapid.T) {
		targets := []moku.TargetDescription{{HarnessID: "fixture", NativeSchema: json.RawMessage(`{"type":"object"}`)}}
		if rapid.Bool().Draw(t, "second-target") {
			targets = append(targets, moku.TargetDescription{HarnessID: "second", NativeSchema: json.RawMessage(`{"type":"object"}`)})
		}
		description, err := moku.DescribeThreadCreation(targets, "/chief")
		if err != nil {
			t.Fatal(err)
		}
		var create *jsonschema.Schema
		for _, tool := range moku.ToolSchemas(description) {
			schema, err := claude.ToolSchema(tool.InputSchema)
			if err != nil {
				t.Fatal(err)
			}
			root, err := model.DecodeObject(schema)
			if err != nil {
				t.Fatal(err)
			}
			for _, keyword := range []string{"allOf", "anyOf", "oneOf"} {
				if _, exists := root[keyword]; exists {
					t.Fatalf("Claude can skip %s because its input schema has root %s", tool.Name, keyword)
				}
			}
			if tool.Name == "create_thread" {
				compiler := jsonschema.NewCompiler()
				compiler.DefaultDraft(jsonschema.Draft7)
				const uri = "urn:chief:create-thread"
				if err := compiler.AddResource(uri, root); err != nil {
					t.Fatal(err)
				}
				create, err = compiler.Compile(uri)
				if err != nil {
					t.Fatal(err)
				}
			}
		}
		if create == nil {
			t.Fatal("missing create_thread")
		}
		worktree := rapid.SampledFrom([]any{true, false, nil, "true"}).Draw(t, "worktree")
		withCwd := rapid.Bool().Draw(t, "cwd")
		name := rapid.SampledFrom([]string{"", " \t", "feature"}).Draw(t, "worktree-name")
		args := map[string]any{"target": map[string]any{"fixture": map[string]any{}}, "prompt": "review"}
		if worktree != nil {
			args["worktree"] = worktree
		}
		if withCwd {
			args["cwd"] = "/project"
		}
		if name != "" {
			args["worktreeName"] = name
		}
		want := (worktree == true && withCwd) || (worktree == false && name != "feature")
		schemaErr := create.Validate(args)
		_, parseErr := moku.ParseCreateRequest(raw(args))
		if (schemaErr == nil) != want || (parseErr == nil) != want {
			t.Fatalf("args %v: want accepted=%t, schema error=%v, parser error=%v", args, want, schemaErr, parseErr)
		}
	})
}
