package moku

import (
	"context"
	"strings"
	"testing"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

type messageAccountPeer struct {
	plugin.Harness
	window string
}

func (*messageAccountPeer) Descriptor() plugin.HarnessDescriptor {
	return plugin.HarnessDescriptor{ID: "account", DisplayName: "Account"}
}
func (p *messageAccountPeer) MokuContext(context.Context, string, plugin.SettingsRequest, plugin.TelemetryLedger) (string, error) {
	return p.window, nil
}
func (p *messageAccountPeer) MokuMessageTelemetry(context.Context, plugin.SettingsRequest, plugin.TelemetryLedger) (string, error) {
	return p.window, nil
}

func TestMessageAccountTelemetryProperties(t *testing.T) {
	rapidcheck.Check(t, func(rt *rapid.T) {
		peer := &messageAccountPeer{window: "window-of-A"}
		ctx := context.Background()
		c := &Coordinator{id: "moku", running: true, ctx: ctx, applied: &SessionConfiguration{}, config: Configuration{
			Harnesses: map[string]plugin.Harness{"account": peer}, Thread: func(string) (model.ThreadRecord, error) { return model.ThreadRecord{}, nil },
		}}
		cached, err := c.collectNativeContext(ctx, "telemetry", model.Settings{})
		if err != nil {
			rt.Fatal(err)
		}
		c.runContext = append([]plugin.ContextEntry{}, cached...)
		for _, next := range append([]string{"window-of-B", "signed-out"}, rapid.SliceOfN(rapid.SampledFrom([]string{"window-of-A", "window-of-B", "signed-out"}), 1, 8).Draw(rt, "account-switches")...) {
			peer.window = next
			entries, err := c.sendContext(ctx, textInput("next message"), nil, nil)
			if err != nil {
				rt.Fatal(err)
			}
			var telemetry string
			for _, entry := range entries {
				if entry.ID == "telemetry" {
					telemetry += entry.Content
				}
			}
			if strings.Count(telemetry, "### Account (account)") != 1 || !strings.HasSuffix(telemetry, "\n"+next) {
				rt.Fatalf("message carried stale account telemetry: %q", telemetry)
			}
		}
		c.workers.Wait()
	})
}
