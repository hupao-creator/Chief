package dispatchconfig

import (
	"encoding/json"
	"sort"
)

type object = map[string]any

// Only public presentation fields cross the durable storage and context
// boundaries. Native request bodies, headers, credentials and account evidence
// remain owned by the adapter.
func fields(input object, keys ...string) object {
	out := object{}
	for _, key := range keys {
		switch value := input[key].(type) {
		case string, bool, float64:
			out[key] = value
		case []any:
			list := []string{}
			for _, x := range value {
				if s, ok := x.(string); ok {
					list = append(list, s)
				}
			}
			out[key] = list
		}
	}
	return out
}
func nested(input object, key string, keys ...string) []object {
	result := []object{}
	values, _ := input[key].([]any)
	for _, v := range values {
		if entry, ok := v.(map[string]any); ok {
			item := fields(entry, keys...)
			if control, ok := entry["control"].(map[string]any); ok && key == "variants" {
				item["control"] = fields(control, "mode", "effort")
			}
			result = append(result, item)
		}
	}
	return result
}
func project(raw, bench json.RawMessage) (Publication, bool) {
	var data object
	if json.Unmarshal(raw, &data) != nil {
		return Publication{}, false
	}
	cli, _ := data["cli"].(map[string]any)
	models, ok := data["models"].([]any)
	if !ok || data["modelsError"] != nil || (cli["available"] != true && cli["status"] != "available" && cli["status"] != "ready") || (data["accountCheckPending"] == true && len(models) == 0) {
		return Publication{}, false
	}
	ui := object{"cli": fields(cli, "status", "available", "executable", "executablePath", "version", "message"), "models": []object{}}
	choices := []object{}
	projected := []object{}
	for _, m := range models {
		model, ok := m.(map[string]any)
		if !ok {
			return Publication{}, false
		}
		item := fields(model, "value", "displayName", "provider", "id", "name", "description", "supportedEfforts", "input", "output", "thinkingLevels", "defaultReasoningEffort", "defaultServiceTier", "hasRequestOverrides", "unavailableReason", "exclusiveUnavailableReason")
		// Codex distinguishes an explicitly standard tier from an unreported default.
		if value, reported := model["defaultServiceTier"]; reported && value == nil {
			item["defaultServiceTier"] = nil
		}
		choice := fields(model, "provider", "thinkingLevels")
		id := model["id"]
		if id == nil {
			id = model["value"]
		}
		if s, ok := id.(string); !ok || s == "" {
			return Publication{}, false
		}
		choice["model"] = id
		if name := model["name"]; name != nil {
			choice["name"] = item["name"]
		} else if model["displayName"] != nil {
			choice["name"] = item["displayName"]
		}
		if thinking, ok := model["thinking"].(map[string]any); ok {
			item["thinking"] = fields(thinking, "kind", "efforts", "canDisable", "reason")
			choice["thinking"] = item["thinking"]
		}
		for _, k := range []string{"supportedReasoningEfforts", "serviceTiers", "variants", "dispatchThinking"} {
			if _, ok := model[k]; ok {
				values := nested(model, k, "id", "value", "displayName", "description", "mode", "effort", "variant", "thinkingLevel", "exclusiveUnavailableReason")
				if k != "dispatchThinking" {
					item[k] = values
				}
				if k != "supportedReasoningEfforts" {
					choice[k] = values
				}
			}
		}
		projected = append(projected, item)
		choices = append(choices, choice)
	}
	ui["models"] = projected
	if _, ok := data["agents"]; ok {
		ui["agents"] = nested(data, "agents", "id", "name", "mode", "hasRequestOverrides")
	}
	if v, ok := data["effectiveModel"].(map[string]any); ok {
		ui["effectiveModel"] = fields(v, "provider", "model", "variant", "exclusiveUnavailableReason")
	}
	if p, ok := data["accountCheckPending"].(bool); ok {
		ui["accountCheckPending"] = p
	}
	presentation, _ := json.Marshal(ui)
	// Presentation keeps the provider's display order. A permutation of that
	// order does not change the model identifiers available to a routing decision.
	sort.SliceStable(choices, func(i, j int) bool {
		a, _ := choices[i]["provider"].(string)
		b, _ := choices[j]["provider"].(string)
		if a != b {
			return a < b
		}
		return choices[i]["model"].(string) < choices[j]["model"].(string)
	})
	options, _ := json.Marshal(choices)
	var ranks struct {
		Models []struct {
			Selector    string   `json:"selector"`
			DisplayName string   `json:"displayName,omitempty"`
			Aliases     []string `json:"aliases,omitempty"`
			Provenance  struct {
				Kind string `json:"kind"`
			} `json:"provenance"`
		} `json:"models"`
	}
	var safeBench json.RawMessage
	if len(bench) > 0 && json.Unmarshal(bench, &ranks) == nil && ranks.Models != nil {
		safeBench, _ = json.Marshal(ranks)
	}
	return Publication{Presentation: presentation, Options: options, Benchmarks: safeBench}, true
}
