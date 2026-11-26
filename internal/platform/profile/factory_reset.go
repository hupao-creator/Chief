package profile

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

const resetMarker = "chief-factory-reset.json"

func (p Profile) StateDirectory() string {
	return ExistingPathOr(filepath.Join(p.DataDir, "mokusei-go-state-v1"), filepath.Join(p.DataDir, "chief-go-state-v1"))
}

type resetIntent struct {
	Version int
	DataDir string
	Epoch   string
}

// Commit only after this exact Runtime has drained writes, closed its stores
// and retired discovery, while its ownership guard still excludes replacement.
func CommitFactoryReset(p Profile, epoch string) error {
	request := filepath.Join(p.DataDir, "chief-factory-reset-request.json")
	var intent resetIntent
	if err := ReadPrivateJSON(request, &intent); err != nil {
		return err
	}
	if intent.Version != 1 || intent.DataDir != p.DataDir || intent.Epoch != epoch {
		return errors.New("factory reset confirmation does not match the retiring Runtime")
	}
	if err := os.Rename(request, filepath.Join(p.DataDir, resetMarker)); err != nil {
		return err
	}
	return syncDirectory(p.DataDir)
}

// FinishFactoryReset runs after the confirming native process has retired.
// The marker is private, profile-bound, and survives partial deletion. Neither
// normal client startup nor a replacement daemon may use a partial profile.
func FinishFactoryReset(p Profile) error {
	return WithClientMaintenance([]string{p.DataDir}, func(profiles []Profile) error {
		if profiles[0].DataDir != p.DataDir {
			return errors.New("profile identity changed before reset")
		}
		return WithExclusiveAccess(p, func() error {
			var intent resetIntent
			if err := ReadPrivateJSON(filepath.Join(p.DataDir, resetMarker), &intent); err != nil {
				return err
			}
			if intent.Version != 1 || intent.DataDir != p.DataDir || intent.Epoch == "" {
				return errors.New("factory reset confirmation does not match this profile")
			}
			root, err := os.OpenRoot(p.DataDir)
			if err != nil {
				return err
			}
			defer root.Close()
			paths, err := resetPaths(root, filepath.Base(p.StateDirectory()))
			if err != nil {
				return err
			}
			// Paths are postorder and each removal is nonrecursive. Unexpected
			// files arriving during cleanup cannot be swept up by a directory delete.
			changed := map[string]bool{}
			for _, entry := range paths {
				if err := entry.remove(root); err != nil {
					return err
				}
				delete(changed, entry.path)
				changed[filepath.Dir(entry.path)] = true
			}
			// Make each surviving directory durable before dropping the retry marker.
			for name := range changed {
				directory, err := root.Open(name)
				if err != nil {
					return err
				}
				if err = errors.Join(directory.Sync(), directory.Close()); err != nil {
					return err
				}
			}
			if err := root.Remove(resetMarker); err != nil {
				return err
			}
			return syncDirectory(p.DataDir)
		})
	})
}

const resetUUID = "(?i:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})"
const resetHash = "[0-9a-f]{64}"

// Select storage by its writer's namespace. Never enumerate workspace roots,
// registry values, attachment source paths, external agent homes or siblings.
func resetPaths(root *os.Root, state string) ([]resetEntry, error) {
	base, err := root.Stat(".")
	if err != nil {
		return nil, err
	}
	type group struct {
		directory, files, trees string
		flatTrees               bool
	}
	groups := []group{
		{".", `desktop-preferences\.json|native-(html-zoom|moku-reply-read)\.json|client-command-journal\.json`, "", false},
		{"runtime", `receipts\.json|output-locale\.json|startup-error\.json`, "", false},
		{state, `state\.sqlite(|-shm|-wal|-journal|\.lock)|managed-worktrees\.json`, "", false},
		{state + "/model-evaluation", `moku-evaluation-facts\.json`, "", false},
		{state + "/moku-telemetry-ledgers", `(codex|pi|opencode|claude)\.json(\.corrupt-[0-9]+)?`, "", false},
		{state + "/attachments", `\.owners\.json`, resetUUID, true},
		{state + "/attachments/.metadata", resetUUID + `\.json`, "", false},
		{state + "/harnesses/codex/application-tools-only", "", `thread-` + resetHash + `|session-[0-9]+`, false},
		{state + "/harnesses/pi", "", resetUUID, false},
		{"thread-reading", resetHash, "", false},
		{"client-drafts", resetHash + `\.(json|lock)`, "", false},
		{"client-reading-cache", `(state|content-` + resetHash + `)\.json`, "", false},
		{"client-attachment-leases", `ownership\.lock|` + resetUUID + `\.(lock|refs\.json)`, "", false},
		{"downloads", "", resetUUID, true}, {"transfers", "", resetUUID, true}, {"clipboard", "", resetUUID, true},
	}
	var paths []resetEntry
	for _, g := range groups {
		// Refuse indirections even to another directory inside this profile.
		dir := "."
		for _, component := range strings.Split(g.directory, "/") {
			dir = filepath.Join(dir, component)
			info, err := root.Lstat(dir)
			if errors.Is(err, fs.ErrNotExist) {
				break
			}
			if err != nil {
				return nil, err
			}
			if !info.IsDir() || !sameResetVolume(base, info) {
				return nil, fmt.Errorf("expected a real profile directory at %s", dir)
			}
		}
		entries, err := fs.ReadDir(root.FS(), g.directory)
		if errors.Is(err, fs.ErrNotExist) {
			continue
		}
		if err != nil {
			return nil, err
		}
		files := regexp.MustCompile("^(" + g.files + ")$")
		trees := regexp.MustCompile("^(" + g.trees + ")$")
		for _, entry := range entries {
			path := filepath.Join(g.directory, entry.Name())
			switch {
			case files.MatchString(entry.Name()):
				if !entry.Type().IsRegular() {
					return nil, fmt.Errorf("unexpected profile file type at %s", path)
				}
				target, err := inspectResetEntry(root, base, path)
				if err != nil {
					return nil, err
				}
				paths = append(paths, target)
			case trees.MatchString(entry.Name()):
				if !entry.IsDir() {
					return nil, fmt.Errorf("expected a real profile directory at %s", path)
				}
				var tree []resetEntry
				err := fs.WalkDir(root.FS(), path, func(name string, item fs.DirEntry, err error) error {
					if err != nil {
						return err
					}
					if strings.EqualFold(item.Name(), ".git") {
						return fmt.Errorf("Git checkout inside managed storage at %s", name)
					}
					// Each transfer or attachment bucket contains a single copy.
					// Extra files or directories can be user work; leave them in place.
					if g.flatTrees && name != path && (len(tree) != 1 || !item.Type().IsRegular() ||
						(g.directory == "transfers" && item.Name() != "upload") ||
						(g.directory == "clipboard" && item.Name() != "bytes")) {
						return fmt.Errorf("unexpected contents inside managed storage at %s", name)
					}
					target, err := inspectResetEntry(root, base, name)
					if err != nil {
						return err
					}
					tree = append(tree, target)
					return nil
				})
				if err != nil {
					return nil, err
				}
				for i := len(tree) - 1; i >= 0; i-- {
					paths = append(paths, tree[i])
				}
			}
		}
	}
	return paths, nil
}

// Bind each unlink to the inspected parent and entry. In particular, an alias
// substituted inside the profile must not redirect removal into a project.
type resetEntry struct {
	path          string
	parent, entry fs.FileInfo
}

func inspectResetEntry(root *os.Root, base fs.FileInfo, path string) (resetEntry, error) {
	parent, err := root.Lstat(filepath.Dir(path))
	if err != nil {
		return resetEntry{}, err
	}
	info, err := root.Lstat(path)
	if err != nil {
		return resetEntry{}, err
	}
	if !parent.IsDir() || !sameResetVolume(base, info) || !ownedByCurrentUser(info) {
		return resetEntry{}, fmt.Errorf("foreign profile entry at %s", path)
	}
	return resetEntry{path: path, parent: parent, entry: info}, nil
}

func (entry resetEntry) remove(root *os.Root) error {
	parent, err := root.OpenRoot(filepath.Dir(entry.path))
	if err != nil {
		return err
	}
	defer parent.Close()
	dir, err := parent.Stat(".")
	if err != nil {
		return err
	}
	name := filepath.Base(entry.path)
	info, err := parent.Lstat(name)
	if err != nil {
		return err
	}
	if !os.SameFile(dir, entry.parent) || !os.SameFile(info, entry.entry) {
		return fmt.Errorf("profile entry changed during reset at %s", entry.path)
	}
	return parent.Remove(name)
}

func syncDirectory(path string) error {
	dir, err := os.Open(path)
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}
