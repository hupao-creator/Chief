package model

import "context"

// commandReadOnly is the protocol registry, independent of installed plugins.
var commandReadOnly = map[string]bool{
	"attachment:preview": true, "attachment:image-path": true, "attachment:discard": false,
	"moku:deliveries": true, "moku:resolve-delivery": false,
	"moku:submit": false, "moku:clear": false, "moku:stage-attachments": false, "moku:cancel": false,
	"history:clear": false, "history:prepare-reset": false, "thread:follow-up": false, "thread:interrupt": false,
	"thread:interaction-respond": false, "thread:read": true, "thread:fork": false,
	"thread:update-settings": false, "app:update-settings": false,
	"harness:detect-installations": false, "harness:detect-installation": true, "workspace:list-known-directories": true,
	"harness:install": false, "harness:settings-presentation": true, "harness:extension": false,
	"thread:set-archived": false, "application:archive": false, "application:initialize-conversation": false,
	"application:command": false, "state:load": true, "application:query": true,
}

func IsCommandChannel(channel string) bool  { _, ok := commandReadOnly[channel]; return ok }
func IsReadOnlyChannel(channel string) bool { return commandReadOnly[channel] }

type followUpRowKey struct{}

// The transport receipt identifies a manual input across independent command
// and transcript streams. Native dispatch and checkpoint IDs remain private.
func WithFollowUpCommand(ctx context.Context, commandID string) context.Context {
	return context.WithValue(ctx, followUpRowKey{}, "steer:"+commandID)
}

func FollowUpRowID(ctx context.Context) string {
	id, _ := ctx.Value(followUpRowKey{}).(string)
	return id
}
