# SQLite write measurement

This macOS executable drives the production [session admission and commit paths](../../../../internal/core/runtime/threads.go) and [Store](../../../../internal/core/store/README.md) in a new temporary directory. It takes no profile or database argument. The deterministic peer supplies Codex events and Git observations. The Codex reducer, projections, Git command and receipts, telemetry ledger, lifecycle events and SQLite writer are production code.

Both binaries open an inline v1 fixture with 16 completed Codex turns in each of two sessions. The report identifies the starting database by SHA-256. After setup, the runner drains the WAL and performs eight idle reads over one second, four changed Git observations with identical request retries, and four telemetry updates. It then admits one public execution and one private execution in sequence. A second SQLite connection checks the published revision at each native admission return. Each gets forty 100-byte text packets, one follow-up and a terminal transition. Every packet enters through its own Harness commit. Before the next packet, the runner checks the accumulated answer and the exact published session bytes. The first write to each existing session is included. After a final checkpoint the runner reopens the database and compares its revision and every record with the acknowledged snapshot.

| Measurement | Source and units |
| --- | --- |
| Input and records | Bytes supplied by the fixture, changed logical keys by kind and full JSON size per changed key. Packet inputs count new text once. |
| Transactions and SQL payload | SQLite commit hook cross-checked against the Store revision delta. A pre-update hook measures new BLOB bytes by record kind, including all rows changed by a command. |
| WAL frames | Writer connection’s `SQLITE_DBSTATUS_CACHE_WRITE` delta in WAL mode. It counts page writes across automatic checkpoints and WAL reuse. |
| File writes | Successful bytes returned by the system SQLite Unix VFS `pwrite` and `write` calls, classified by database or WAL descriptor path. Every sample must account for at least the observed WAL page payload. The final checkpoint’s writes are reported separately. |
| Process writes | Same process’s `proc_pid_rusage(RUSAGE_INFO_V4).ri_diskio_byteswritten` delta. macOS can coalesce and charge writes at different times. SSD controller writes and endurance are outside this collector. |
| Latency | Microseconds for the fixture operation to return and for the traced SQLite `COMMIT` statement. Timing includes observer overhead. Background publication can overlap. |

The writer must report 8 KiB pages, FULL synchronization, full fsync for commits and checkpoints, and a 1,000-page automatic checkpoint. Build both binaries against the same collector. The [baseline overlay](../prepare_baseline.py) restores the specified revision's production Go sources. Run under the repository's shared [performance lease](../../../benchmarks/gate/runner.py) and [desktop lease](../../../benchmarks/gate/ux.py), serially and separately from builds and property checks.

```sh
python3 tools/verification/runtime-performance/prepare_baseline.py 2aed57156caae91e38bb651da16340d861e9624d .build/sqlite-baseline
./scripts/go.sh build -trimpath -overlay=.build/sqlite-baseline/overlay.json -o .build/sqlite-before ./tools/verification/runtime-performance/sqlite-writes
./scripts/go.sh build -trimpath -o .build/sqlite-after ./tools/verification/runtime-performance/sqlite-writes
.build/sqlite-before > .build/sqlite-before.json
.build/sqlite-after > .build/sqlite-after.json
```

Compare the same ordered inputs, logical changes and committed revisions. Sum database and WAL write bytes including the final checkpoint. File size after checkpoint measures net allocation. The fixture supplies the activity mix, history size and packet boundaries. Live profiles, native event pacing, model services, GUI latency and power loss require separate evidence.
