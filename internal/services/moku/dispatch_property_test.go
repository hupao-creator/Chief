package moku

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

type dispatchHost struct {
	plugin.Harness
	steer bool
}

func (h *dispatchHost) Descriptor() plugin.HarnessDescriptor {
	return plugin.HarnessDescriptor{ThreadCapabilities: plugin.ThreadCapabilities{FollowUpOnly: h.steer}}
}

// PBT-DISPATCH-LIFECYCLE: README.md
func TestDispatchLifecycleProperties(t *testing.T) {
	rapidcheck.Check(t, func(t *rapid.T) {
		ctx := context.Background()
		host := &dispatchHost{}
		observation := &model.PublicExecution{}
		record := model.ThreadRecord{SessionRecord: model.SessionRecord{ID: "chief", HarnessID: "host"}}
		record.Observation.LatestExecution = observation
		settings := model.Settings{}
		settings.Moku.TargetHarnessIDs = []string{"host"}
		visible := ""
		steers := 0
		reject := false
		c := Coordinator{id: "chief", applied: &SessionConfiguration{AppliedSettings: settings}, injection: &plugin.Injection{}, config: Configuration{
			Thread: func(string) (model.ThreadRecord, error) { return record, nil }, Harnesses: map[string]plugin.Harness{"host": host},
			DispatchOptions: func([]string) json.RawMessage { return mokuRaw(map[string]any{"host": []string{visible}}) },
			SteerDispatchOptions: func(_ context.Context, owner, execution string, _ *plugin.Injection, entry plugin.ContextEntry) error {
				steers++
				if owner != "chief" || execution != observation.ExecutionID || !strings.Contains(entry.Content, visible) {
					t.Fatal("steer lost execution or replacement content")
				}
				if reject {
					return errors.New("native execution ended")
				}
				return nil
			},
		}}
		deliveredExecution, deliveredModel := "", ""
		for _, action := range rapid.SliceOfN(rapid.IntRange(0, 4), 2, 32).Draw(t, "actions") {
			observation.ExecutionID = fmt.Sprintf("execution-%d", rapid.IntRange(1, 3).Draw(t, "execution"))
			observation.Status = rapid.SampledFrom([]string{"running", "completed", "waiting-for-user"}).Draw(t, "status")
			host.steer = rapid.Bool().Draw(t, "supports-steer")
			reject = rapid.Bool().Draw(t, "native-ended")
			if action < 3 {
				visible = fmt.Sprintf("model-%d", action)
			}
			if action == 4 {
				entries, err := c.sendContext(ctx, textInput("task"), nil, nil)
				if err != nil {
					t.Fatal(err)
				}
				found := false
				for _, e := range entries {
					if e.ID == "dispatch-options" && strings.Contains(e.Content, visible) {
						found = true
					}
				}
				if !found {
					t.Fatal("natural admission missed the latest publication")
				}
				c.rememberDispatch(observation.ExecutionID, entries)
				deliveredExecution, deliveredModel = observation.ExecutionID, visible
				continue
			}
			want := host.steer && observation.Status == "running" && (deliveredExecution != observation.ExecutionID || deliveredModel != visible)
			before := steers
			c.steerDispatchOptions(ctx)
			if (steers != before) != want {
				t.Fatal("publication delivery violated execution ownership or duplicate suppression")
			}
			if want && !reject {
				deliveredExecution, deliveredModel = observation.ExecutionID, visible
			}
		}
	})
}
