package git

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/hupao-creator/Chief/internal/core/plugin"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

type trackedNumstat string

func (output trackedNumstat) Run(context.Context, plugin.ApplicationProcessInput) (plugin.ApplicationProcessResult, error) {
	return plugin.ApplicationProcessResult{Stdout: string(output)}, nil
}

func TestGitRankingBudgetProperties(t *testing.T) {
	rapidcheck.Check(t, func(rt *rapid.T) {
		root := t.TempDir()
		name := rapid.StringMatching("[a-z]{1,12}").Draw(rt, "tracked-file")
		added := rapid.IntRange(1, 1000).Draw(rt, "added")
		deleted := rapid.IntRange(0, 1000).Draw(rt, "deleted")
		if err := os.WriteFile(filepath.Join(root, name), nil, 0600); err != nil {
			rt.Fatal(err)
		}
		peer := trackedNumstat(fmt.Sprintf("%d\t%d\t%s\x00", added, deleted, name))
		c := &client{gate: make(chan struct{}, 2)}
		observe := func() Snapshot {
			s := Snapshot{Root: root, Head: ptr("HEAD"), Changed: 1}
			if err := c.lineStats(context.Background(), peer, &s, nil); err != nil {
				rt.Fatal(err)
			}
			if s.Additions == nil || s.Deletions == nil || *s.Additions != added || *s.Deletions != deleted {
				rt.Fatal("optional ranking lost completed totals")
			}
			return s
		}

		// A metadata call can remain in the OS after its observation is cancelled.
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		started, release := make(chan struct{}), make(chan struct{})
		resume := sync.OnceFunc(func() { close(release) })
		defer resume()
		result := make(chan []FileLineStats, 1)
		go func() {
			result <- runRecentRanking(ctx, func() []FileLineStats {
				close(started)
				<-release
				return []FileLineStats{{Path: "late"}}
			})
		}()
		<-started
		cancel()
		select {
		case files := <-result:
			if len(files) != 0 {
				rt.Fatal("cancelled observation published late rows")
			}
		case <-time.After(time.Second):
			rt.Fatal("cancellation waited for filesystem metadata")
		}
		for range rapid.IntRange(1, 4).Draw(rt, "observations-while-stalled") {
			if len(observe().RecentFiles) != 0 {
				rt.Fatal("a second ranking was admitted while filesystem metadata was blocked")
			}
		}
		resume()
		// The worker releases the slot only after the stalled read returns.
		rankingSlot.Lock()
		rankingSlot.Unlock()
		files := observe().RecentFiles
		if len(files) != 1 || files[0] != (FileLineStats{Path: name, Additions: added, Deletions: deleted}) {
			rt.Fatal("fresh ranking failed to recover its path and counts")
		}
	})
}
