package git

import (
	"context"
	"errors"
	"os"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/hupao-creator/Chief/internal/core/plugin"
)

// Statistics never load patches or run text conversion. The separate budget
// prevents large new directories from delaying status/diff observation indefinitely.
const maxStatsFiles = 256
const maxRecentCandidates = 1024

type lineStatistics struct {
	additions, deletions int
	byPath               map[string]FileLineStats
}

func (c *client) lineStats(ctx context.Context, p plugin.ApplicationProcessCapability, snapshot *Snapshot, files []ChangedFile) error {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	current := map[string]bool{}
	tracked := map[string]bool{}
	for _, file := range files {
		if file.Scope != "untracked" {
			tracked[file.Path] = true
		}
		if !file.Submodule && (snapshot.Head == nil || file.Scope == "untracked") {
			current[file.Path] = true
		}
	}
	if len(current) > maxStatsFiles {
		return readFailure("too-large")
	}
	// An index-deleted path recreated as untracked is not a simple addition to
	// the HEAD diff. Do not present a double-counted delete/add pair as net work.
	if snapshot.Head != nil {
		for path := range current {
			if tracked[path] {
				return readFailure("inaccessible")
			}
		}
	}
	stats := lineStatistics{byPath: make(map[string]FileLineStats)}
	flags := []string{"--numstat", "-z", "--no-ext-diff", "--no-textconv", "--no-color", "--no-relative", "--ignore-submodules=all", "--find-renames"}
	if snapshot.Head != nil && snapshot.Changed > 0 {
		result, err := c.run(ctx, p, snapshot.Root, maxStatus, append(append([]string{"diff", *snapshot.Head}, flags...), "--")...)
		if err != nil {
			return err
		}
		if result.ExitCode != 0 {
			return readFailure("inaccessible")
		}
		if err := stats.addNumstat(result.Stdout, ""); err != nil {
			return err
		}
	}
	if len(current) > 0 {
		root, err := os.OpenRoot(snapshot.Root)
		if err != nil {
			return err
		}
		defer root.Close()
		if err := c.addCurrentLineStats(ctx, p, root, flags, current, &stats); err != nil {
			return err
		}
	}
	if len(stats.byPath) > 0 {
		rootPath, changed := snapshot.Root, snapshot.Changed
		snapshot.RecentFiles = runRecentRanking(ctx, func() []FileLineStats {
			root, err := os.OpenRoot(rootPath)
			if err != nil {
				return nil
			}
			defer root.Close()
			return stats.rankFiles(ctx, root, changed)
		})
	}
	snapshot.Additions = &stats.additions
	snapshot.Deletions = &stats.deletions
	return nil
}

func (c *client) addCurrentLineStats(ctx context.Context, p plugin.ApplicationProcessCapability, root *os.Root,
	flags []string, current map[string]bool, stats *lineStatistics) error {
	for path := range current {
		if err := ctx.Err(); err != nil {
			return err
		}
		info, err := root.Lstat(path)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return err
		}
		if !info.Mode().IsRegular() && info.Mode()&os.ModeSymlink == 0 {
			return readFailure("inaccessible")
		}
		// Git handles binary attributes, symlink contents and missing final
		// newlines consistently with the native reader, without following links.
		args := append(append([]string{"diff", "--no-index"}, flags...), "--", "/dev/null", path)
		result, err := c.run(ctx, p, root.Name(), maxStatus, args...)
		if err != nil {
			return err
		}
		if result.ExitCode != 0 && result.ExitCode != 1 {
			return readFailure("inaccessible")
		}
		if err := stats.addNumstat(result.Stdout, path); err != nil {
			return err
		}
	}
	return nil
}

func addLines(total, value int) (int, error) {
	const maxSafeInteger = 9_007_199_254_740_991
	if total > maxSafeInteger-value {
		return 0, readFailure("too-large")
	}
	return total + value, nil
}

// NUL framing preserves tabs and newlines in filenames. Renames and --no-index
// use an empty pathname followed by source and destination NUL fields.
func (s *lineStatistics) addNumstat(output, currentPath string) error {
	if output == "" {
		return nil
	}
	if !strings.HasSuffix(output, "\x00") {
		return readFailure("inaccessible")
	}
	rows := strings.Split(strings.TrimSuffix(output, "\x00"), "\x00")
	for i := 0; i < len(rows); i++ {
		fields := strings.SplitN(rows[i], "\t", 3)
		if len(fields) != 3 {
			return readFailure("inaccessible")
		}
		path := fields[2]
		if path == "" {
			if i+2 >= len(rows) || !validPath(rows[i+1]) {
				return readFailure("inaccessible")
			}
			path = rows[i+2]
			i += 2
		}
		if !validPath(path) {
			return readFailure("inaccessible")
		}
		if fields[0] == "-" && fields[1] == "-" {
			continue
		}
		added, errA := strconv.Atoi(fields[0])
		deleted, errD := strconv.Atoi(fields[1])
		if errA != nil || errD != nil || added < 0 || deleted < 0 {
			return readFailure("inaccessible")
		}
		var err error
		s.additions, err = addLines(s.additions, added)
		if err != nil {
			return err
		}
		s.deletions, err = addLines(s.deletions, deleted)
		if err != nil {
			return err
		}
		if currentPath != "" {
			path = currentPath
		}
		if s.byPath != nil && (added > 0 || deleted > 0) && validRecentPath(path) {
			file := s.byPath[path]
			file.Path = path
			file.Additions += added
			file.Deletions += deleted
			s.byPath[path] = file
			if len(s.byPath) > maxRecentCandidates {
				s.byPath = nil
			}
		}
	}
	return nil
}

// Filesystem metadata calls have no context-aware cancellation. A stalled
// mount may hold this slot until its syscall returns, even across monitor restarts.
var rankingSlot sync.Mutex

func runRecentRanking(ctx context.Context, rank func() []FileLineStats) []FileLineStats {
	if ctx.Err() != nil || !rankingSlot.TryLock() {
		return nil
	}
	done := make(chan []FileLineStats, 1)
	go func() {
		files := rank()
		rankingSlot.Unlock()
		done <- files
	}()
	select {
	case <-ctx.Done():
		return nil
	case files := <-done:
		if ctx.Err() != nil {
			return nil
		}
		return files
	}
}

func (s lineStatistics) rankFiles(ctx context.Context, root *os.Root, changed int) []FileLineStats {
	type candidate struct {
		FileLineStats
		modified time.Time
	}
	files := make([]candidate, 0, len(s.byPath))
	for path, stats := range s.byPath {
		if ctx.Err() != nil {
			return nil
		}
		file := candidate{FileLineStats: stats}
		if info, err := root.Lstat(path); err == nil {
			file.modified = info.ModTime()
		}
		files = append(files, file)
	}
	if ctx.Err() != nil {
		return nil
	}
	slices.SortFunc(files, func(a, b candidate) int {
		if a.modified.IsZero() != b.modified.IsZero() {
			if a.modified.IsZero() {
				return 1
			}
			return -1
		}
		if order := b.modified.Compare(a.modified); order != 0 {
			return order
		}
		return strings.Compare(a.Path, b.Path)
	})
	limit := min(len(files), changed, maxRecentFiles)
	result := make([]FileLineStats, 0, limit)
	for _, file := range files[:limit] {
		result = append(result, file.FileLineStats)
	}
	return result
}
