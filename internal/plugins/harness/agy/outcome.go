package agy

import (
	"os"
	"path/filepath"
	"regexp"
	"syscall"

	"github.com/hupao-creator/Chief/internal/platform/sqlite"
)

var sessionName = regexp.MustCompile(`^[a-zA-Z0-9_-]{1,128}$`)

// agy can return end_turn after an upstream error. Inspect only step indices
// and types in this session's own trajectory, never its payload or credentials.
type trajectory struct {
	path  string
	file  os.FileInfo
	after int64
}

func watchTrajectory(dir, id string) *trajectory {
	if !sessionName.MatchString(id) || !filepath.IsAbs(dir) {
		return nil
	}
	t := &trajectory{path: filepath.Join(dir, "antigravity-cli", "conversations", id+".db"), after: -1}
	f, err := t.inspect()
	if os.IsNotExist(err) {
		return t
	}
	if err != nil {
		return nil
	}
	t.file = f
	idx, _, ok := t.last()
	if !ok {
		return nil
	}
	t.after = idx
	return t
}
func (t *trajectory) inspect() (os.FileInfo, error) {
	real, err := filepath.EvalSymlinks(t.path)
	if err != nil {
		return nil, err
	}
	if real != t.path {
		return nil, os.ErrPermission
	}
	f, err := os.Stat(real)
	if err != nil {
		return nil, err
	}
	if !f.Mode().IsRegular() || f.Sys().(*syscall.Stat_t).Nlink != 1 {
		return nil, os.ErrPermission
	}
	return f, nil
}
func (t *trajectory) last() (int64, int64, bool) {
	f, err := t.inspect()
	if err != nil || t.file != nil && !os.SameFile(t.file, f) {
		return 0, 0, false
	}
	db, err := sqlite.Open(t.path, true)
	if err != nil {
		return 0, 0, false
	}
	defer db.Close()
	rows, err := db.Query("SELECT idx, step_type FROM steps ORDER BY idx DESC LIMIT 1")
	if err != nil {
		return 0, 0, false
	}
	if len(rows) == 0 {
		return -1, 0, true
	}
	idx, a := rows[0]["idx"].(int64)
	kind, b := rows[0]["step_type"].(int64)
	return idx, kind, a && b
}
func (t *trajectory) failed() bool {
	if t == nil {
		return false
	}
	idx, kind, ok := t.last()
	return ok && idx > t.after && kind == 17
}
