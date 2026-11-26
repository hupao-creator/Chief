package opencode

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"time"

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
func catalogAccountIdentity(ctx context.Context, env map[string]string, waitForAccount bool) (string, error) {
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
			rows, err = readAccountRevisions(ctx, path, waitForAccount)
			if err != nil {
				return "", err
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

func readAccountRevisions(ctx context.Context, path string, waitForAccount bool) ([]sqlite.Row, error) {
	deadline := time.Now().Add(2 * time.Second)
	for {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		rows, err := queryAccountRevisions(path)
		var failure *sqlite.Error
		if !errors.As(err, &failure) {
			return rows, err
		}
		if !failure.Contended() {
			return nil, fmt.Errorf("OpenCode account information could not be read (SQLite error %d)", failure.Code)
		}
		if !waitForAccount || !time.Now().Before(deadline) {
			return nil, fmt.Errorf("OpenCode account database is busy (SQLite error %d). Try again in a moment", failure.Code)
		}
		// Release the connection between attempts. Cancellation and advisory
		// lookups must never wait on SQLite's default two-second busy handler.
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(min(25*time.Millisecond, time.Until(deadline))):
		}
	}
}

func queryAccountRevisions(path string) ([]sqlite.Row, error) {
	db, err := sqlite.Open(path, true)
	if err != nil {
		return nil, err
	}
	defer db.Close()
	if err := db.Exec("PRAGMA busy_timeout=0; BEGIN"); err != nil {
		return nil, err
	}
	tables, err := db.Query("SELECT name FROM sqlite_master WHERE type='table' AND name='credential'")
	if err != nil || len(tables) == 0 {
		return tables, err
	}
	return db.Query("SELECT id, integration_id, active, connector_id, method_id, time_updated FROM credential ORDER BY integration_id, id")
}
