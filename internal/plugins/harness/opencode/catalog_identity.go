package opencode

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"

	"github.com/hupao-creator/Chief/internal/platform/sqlite"
)

// OpenCode creates its global configuration directory on the first launch.
// A missing directory and an empty one supply the same configuration inputs.
// Preserve observation of symlinks and paths that could not be inspected.
func hasCatalogConfigDirectory(path string) bool {
	info, err := os.Lstat(path)
	if err != nil {
		return !errors.Is(err, os.ErrNotExist)
	}
	if !info.IsDir() {
		return true
	}
	dir, err := os.Open(path)
	if err != nil {
		return true
	}
	defer dir.Close()
	_, err = dir.ReadDir(1)
	return !errors.Is(err, io.EOF)
}

// OpenCode 2 stores credential selection in its native database, not auth.json.
// Read only non-secret identity/revision columns: unrelated session writes must
// not invalidate a complete directory, and tokens never leave the native store.
func catalogAccountIdentity(ctx context.Context, env map[string]string) (string, error) {
	if err := ctx.Err(); err != nil {
		return "", err
	}
	path := nativeDatabasePath(env)
	rows := []sqlite.Row{}
	if path != ":memory:" {
		_, err := os.Stat(path)
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return "", errors.New("OpenCode account identity cannot be inspected")
		}
		if err == nil {
			db, err := sqlite.Open(path, true)
			if err != nil {
				return "", errors.New("OpenCode account identity cannot be opened")
			}
			defer db.Close()
			// A routing cache lookup never waits on another process's write lock.
			if err := db.Exec("PRAGMA busy_timeout=0"); err != nil {
				return "", err
			}
			tables, err := db.Query("SELECT name FROM sqlite_master WHERE type='table' AND name='credential'")
			if err != nil {
				return "", errors.New("OpenCode account identity schema is unavailable")
			}
			if len(tables) > 0 {
				rows, err = db.Query("SELECT id, integration_id, active, connector_id, method_id, time_updated FROM credential ORDER BY integration_id, id")
				if err != nil {
					return "", errors.New("OpenCode account identity revision is unavailable")
				}
			}
		}
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	encoded, err := json.Marshal([]any{path, rows})
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%x", sha256.Sum256(encoded)), nil
}
