// The observer lives only in this single-database measurement executable.
package main

/*
#include <sqlite3.h>
#include <stdlib.h>
#include <libproc.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/param.h>
#include <time.h>
#include <unistd.h>
#include <string.h>

// Darwin exports the SQLite pre-update API separately from its public header.
extern void *sqlite3_preupdate_hook(sqlite3*, void (*)(void*, sqlite3*, int, const char*, const char*, sqlite3_int64, sqlite3_int64), void*);
extern int sqlite3_preupdate_new(sqlite3*, int, sqlite3_value**);
extern int sqlite3_preupdate_count(sqlite3*);
extern void recordBlobBytes(char*, int);

static sqlite3 *writer;
static int commits, invalid, awaitingWriter;
static sqlite3_int64 blobs, dbWritten, walWritten;
static uint64_t commitStart, commitNS;

// Count successful bytes including overwrites of recycled WAL frames and
// checkpoint writes. Keep the system VFS's locking, sync and checkpoint hooks.
static ssize_t (*systemPwrite)(int, const void*, size_t, off_t);
static ssize_t (*systemWrite)(int, const void*, size_t);
static ssize_t countWrite(int fd, ssize_t n) {
    if (n <= 0) return n;
    int savedErrno = errno;
    char path[MAXPATHLEN];
    if (fcntl(fd, F_GETPATH, path) < 0) invalid = 1;
    else {
        const char *name = strrchr(path, '/');
        if (name && strcmp(name, "/state.sqlite-wal") == 0) walWritten += n;
        if (name && strcmp(name, "/state.sqlite") == 0) dbWritten += n;
    }
    errno = savedErrno;
    return n;
}
static ssize_t countedPwrite(int fd, const void *b, size_t n, off_t off) {
    return countWrite(fd, systemPwrite(fd, b, n, off));
}
static ssize_t countedWrite(int fd, const void *b, size_t n) {
    return countWrite(fd, systemWrite(fd, b, n));
}

static int commit(void *unused) { commits++; return 0; }
static int trace(unsigned kind, void *unused, void *stmt, void *value) {
    const char *sql = sqlite3_sql(stmt);
    if (sql && strcmp(sql, "COMMIT") == 0) {
        uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        if (kind == SQLITE_TRACE_STMT) commitStart = now;
        if (kind == SQLITE_TRACE_PROFILE) commitNS += now - commitStart;
    }
    return 0;
}
static void row(void *unused, sqlite3 *db, int op, const char *schema, const char *table,
                sqlite3_int64 oldID, sqlite3_int64 newID) {
    if (op == SQLITE_DELETE) return;
    int bytes = 0;
    for (int i = 0; i < sqlite3_preupdate_count(db); i++) {
        sqlite3_value *v;
        if (sqlite3_preupdate_new(db, i, &v) != SQLITE_OK) { invalid = 1; return; }
        if (sqlite3_value_type(v) == SQLITE_BLOB) bytes += sqlite3_value_bytes(v);
    }
    blobs += bytes;
    if (bytes && (!strcmp(table, "records") || !strcmp(table, "record_chunks"))) {
        sqlite3_value *key;
        if (sqlite3_preupdate_new(db, 0, &key) != SQLITE_OK) { invalid = 1; return; }
        recordBlobBytes((char*)sqlite3_value_text(key), bytes);
    }
}
static void connection(void *unused, sqlite3 *db, const char *text, int event) {
    if (event != 0 || !awaitingWriter) return;
    awaitingWriter = 0;
    writer = db;
    sqlite3_commit_hook(db, commit, NULL);
    sqlite3_preupdate_hook(db, row, NULL);
    if (sqlite3_trace_v2(db, SQLITE_TRACE_STMT | SQLITE_TRACE_PROFILE, trace, NULL) != SQLITE_OK) invalid = 1;
}
static int install(void) {
    // The two fixture seeding connections have both closed. SQLITE_CONFIG_SQLLOG
    // exposes the next production connection without a product instrumentation hook.
    int rc = sqlite3_shutdown();
    if (rc != SQLITE_OK) return rc;
    rc = sqlite3_config(SQLITE_CONFIG_SQLLOG, connection, NULL);
    if (rc != SQLITE_OK) return rc;
    sqlite3_vfs *v = sqlite3_vfs_find(NULL);
    if (!v || v->iVersion < 3 || strcmp(v->zName, "unix") != 0) return SQLITE_ERROR;
    systemPwrite = (ssize_t(*)(int, const void*, size_t, off_t))v->xGetSystemCall(v, "pwrite");
    systemWrite = (ssize_t(*)(int, const void*, size_t))v->xGetSystemCall(v, "write");
    if (!systemPwrite || !systemWrite ||
        v->xSetSystemCall(v, "pwrite", (sqlite3_syscall_ptr)countedPwrite) != SQLITE_OK ||
        v->xSetSystemCall(v, "write", (sqlite3_syscall_ptr)countedWrite) != SQLITE_OK) return SQLITE_ERROR;
    awaitingWriter = 1;
    return SQLITE_OK;
}
static int checkpoint(void) {
    return sqlite3_wal_checkpoint_v2(writer, "main", SQLITE_CHECKPOINT_TRUNCATE, NULL, NULL);
}
static int pragmaInt(const char *sql) {
    sqlite3_stmt *s = NULL;
    int value = -1;
    if (writer && sqlite3_prepare_v2(writer, sql, -1, &s, NULL) == SQLITE_OK &&
        sqlite3_step(s) == SQLITE_ROW) value = sqlite3_column_int(s, 0);
    sqlite3_finalize(s);
    return value;
}
static int observe(int *frames, int *txs, sqlite3_int64 *blobBytes, uint64_t *osBytes, sqlite3_int64 *dbBytes, sqlite3_int64 *walBytes, uint64_t *ns) {
    int unused;
    struct rusage_info_v4 usage = {0};
    if (invalid || !writer || sqlite3_db_status(writer, SQLITE_DBSTATUS_CACHE_WRITE, frames, &unused, 0) != SQLITE_OK ||
        proc_pid_rusage(getpid(), RUSAGE_INFO_V4, (rusage_info_t *)&usage) != 0) return 0;
    *osBytes = usage.ri_diskio_byteswritten;
    *txs = commits;
    *blobBytes = blobs;
    *dbBytes = dbWritten;
    *walBytes = walWritten;
    *ns = commitNS;
    return 1;
}
*/
import "C"

import (
	"fmt"
	"unsafe"
)

func installCounters() {
	if rc := C.install(); rc != 0 {
		panic(fmt.Sprintf("SQLite observer unavailable (code %d)", rc))
	}
}

func drainWAL() {
	if C.checkpoint() != 0 {
		panic("incomplete checkpoint")
	}
}

func writerPragmas() map[string]int {
	values := map[string]int{}
	for name, want := range map[string]int{"page_size": 8192, "synchronous": 2, "fullfsync": 1, "checkpoint_fullfsync": 1, "wal_autocheckpoint": 1000} {
		sql := C.CString("PRAGMA " + name)
		v := int(C.pragmaInt(sql))
		C.free(unsafe.Pointer(sql))
		if v != want {
			panic(fmt.Sprintf("writer pragma %s = %d, want %d", name, v, want))
		}
		values[name] = v
	}
	return values
}

type counters struct {
	tx, frames, blob, process, db, wal, commitNS int64
}

func readCounters() counters {
	var f, t C.int
	var b, d, w C.sqlite3_int64
	var p, ns C.uint64_t
	if C.observe(&f, &t, &b, &p, &d, &w, &ns) == 0 {
		panic("missing SQLite or process counters")
	}
	return counters{int64(t), int64(f), int64(b), int64(p), int64(d), int64(w), int64(ns)}
}

func sqliteVersion() string { return C.GoString(C.sqlite3_sourceid()) }
