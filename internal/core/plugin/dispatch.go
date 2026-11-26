package plugin

import "encoding/json"

// DispatchOptions describes the wire contract independently of native discovery.
type DispatchOptions interface {
	DispatchSchema() json.RawMessage
}

func DispatchSchema(required, optional, permissions []string) json.RawMessage {
	text := map[string]any{"type": "string", "minLength": 1, "maxLength": 512}
	properties := map[string]any{}
	for _, fields := range [][]string{required, optional} {
		for _, field := range fields {
			properties[field] = text
		}
	}
	properties["thinking"] = map[string]any{"type": "object", "additionalProperties": false,
		"required": []string{"mode"}, "properties": map[string]any{
			"mode": map[string]any{"type": "string", "enum": []string{"fixed", "off", "on", "effort"}}, "effort": text},
		"description": "Choose a thinking mode. Include effort for mode effort."}
	if len(permissions) > 0 {
		properties["permissionMode"] = map[string]any{"type": "string", "enum": permissions}
	}
	b, _ := json.Marshal(map[string]any{"type": "object", "additionalProperties": false, "properties": properties, "required": required,
		"description": "Use the published dispatch options in context. Native execution reports the outcome."})
	return b
}
