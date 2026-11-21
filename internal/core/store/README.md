# Go storage contract

`internal/core/store` is the authoritative durability boundary. It links the host system
SQLite library through `internal/platform/sqlite`, a small cgo binding. There is no
Node process, SQLite CLI subprocess, third-party Go driver, or JSON-file fallback.
Building requires cgo, the system SQLite development headers, and a C compiler.

## File ownership and format

The caller chooses the database path under its exclusively owned profile. The
store additionally holds a nonblocking advisory lock on `<path>.lock`, preventing
two store instances from writing the same file. The database is mode `0600`, and
new parent directories are mode `0700`.
New runtime profiles use `chief-go-state-v1/state.sqlite`. If a profile has the
existing `mokusei-go-state-v1` directory, the runtime opens that database in place.

The Go store accepts application ID `0x4d4f4b53` (`MOKS`) and format versions
1 and 2. Only a completely empty, unversioned SQLite database can be initialized. Foreign versions, extra schema objects,
altered table definitions, malformed JSON, invalid lifecycle references, and
noncontiguous ordering are rejected at open.

The database contains the following tables.

| Table | Responsibility |
| --- | --- |
| `records` | Inline UTF-8 JSON records, including untouched Alpha v1 values |
| `record_chunks` (v2) | Ordered byte ranges of large JSON records |
| `entity_order` | Unique IDs and contiguous positions for each ordered entity kind |
| `store_meta` | Monotonically increasing committed revision |

SQLite runs in WAL mode with `synchronous=FULL`, an 8 KiB page size for new files,
and a 2-second busy timeout. macOS full fsync and checkpoint full fsync are
enabled. A successful update means that COMMIT has completed, including its
durability work. WAL checkpoint completion is not required for durability.

## Large records

A logical record has one key and up to 50 MiB of exact UTF-8 JSON. Values up
to 64 KiB live in `records`. The first changed value above that threshold
creates `record_chunks` and sets `user_version=2` in the transaction that
saves the value and its revision. Opening a v1 profile and writing smaller
records keep the v1 format. Existing large inline rows remain readable in place. Each moves to
chunks on its next large write. A v1-only executable rejects a v2 database.

Large values use consecutive 7,680-byte parts numbered from zero. The smaller
final part is empty for an exact multiple. A commit compares parts against the
last committed bytes, writes changed parts and deletes any surplus tail in the
same transaction as the revision and related records. Shrinking to 64 KiB or
less moves the value back inline. Opening checks key ownership, consecutive
positions, the final part, total size and the reassembled JSON. A key must
have exactly one representation.

Harness submissions still serialize complete logical snapshots. An edit near
the front that shifts subsequent byte offsets can change many parts. Updates
to a growing tail typically share earlier parts. These storage choices preserve
each existing admission, streaming and COMMIT boundary.

## Transactions and snapshots

```go
db, err := store.Open(path)
if err != nil { return err }

snapshot, err := db.Update(ctx, func(tx *store.Tx) error {
    var thread Thread
    found, err := tx.Get("thread:"+id, &thread)
    if err != nil { return err }
    if !found { return errNotFound }
    if thread.Revision != expectedRevision { return errConflict }
    thread.Revision++
    thread.Title = title
    return tx.Put("thread:"+id, thread)
})
```

`Update` admits requests into a single FIFO writer. Its callback reads the latest
committed state and must be synchronous; it must not call `Update` or `Close`
recursively. It may read the committed `Store.Snapshot()` without blocking.
Caller-owned slices are copied on write. The transaction becomes unusable when
the callback returns.

The callback can `Get`, `Raw`, `Has`, `Keys`, `Order`, `Put`, `PutRaw`, `Delete`,
and `SetOrder`. A callback error or panic discards every staged write. Validation
and cancellation checks happen before beginning the SQLite transaction. Record
writes, entity ordering, lifecycle events, consumer batches, receipts, outcomes,
and the new revision share one `BEGIN IMMEDIATE` / `COMMIT` boundary.
Lifecycle validation checks changed records against the complete staged view;
unchanged history retains its validation from the committed snapshot. Event-local
reverse indexes retain work and outcome references, so an event deletion checks
those references without scanning unrelated history. Opening a database still
validates all records.

Once SQLite starts the transaction, `Update` waits for a definite result even
if its context is cancelled. Successful COMMIT always publishes the new snapshot
and notifies subscribers. Failed SQL statements roll back the transaction and
publish nothing. An uncertain storage error or failed rollback fences further
updates until the store is reopened.

Snapshots are immutable views. `Raw`, `Order`, and JSON decoding provide owned
copies, including input passed to custom `UnmarshalJSON` implementations. Old
snapshots remain valid after later commits. Unchanged byte-identical writes and
unchanged ordering do not increment the revision.

Record and order indexes are persistent compressed radix trees. A transaction
snapshot copies only changed key paths and shares untouched branches and values;
one telemetry write does not copy every record or order. `Keys(prefix)` descends
directly to its range, and `Count(prefix)` reads the cached subtree count.
`ChangedKeys(previous, prefix)` compares shared branches and returns exact source
changes, including removals, in key order. Coalesced commits need no retained
revision journal. `PrefixEqual` and `OrderChanged` let consumers reject unrelated
updates before materializing a collection. A zero previous snapshot is the full
initial read; independently opened stores do not share the in-memory branches.
Collection caches can retain `RecordPrefix(prefix)`, an opaque `RecordSnapshot`
whose `ChangedKeys` baseline holds only that subtree. It does not retain a full
old store snapshot or unrelated record bodies.

`Subscribe` returns a channel of committed revisions, including the current
revision immediately. Notifications coalesce for slow readers; consumers reread
the snapshot. Durable lifecycle delivery uses persisted events and outcomes,
not this channel's delivery count.
`SubscribeLifecycle` uses scope/type/source routes, the consumer's own work and
outcomes, and an optional exact observed record. A local fact wakes matching
routes rather than enumerating all active scoped consumers. Its initial revision,
coalescing, unsubscribe and store-close behavior match `Subscribe`.
`Snapshot.EventRevision()` changes only for event writes or deletions;
`LifecycleRevision()` also includes work and outcome changes. Consumers can skip
unrelated commits by comparing these markers within the same open store. They
are initialized to the durable revision on reopen and are not persistent cursors.

`Flush` is a queue barrier. The store has no deferred non-durable publication or
automatic token-stream debounce: an owning runtime may collect observations
before submitting them, but it must pass a durable transaction boundary before
admitting native work which depends on those observations.

`Close` rejects new work, drains admitted requests, closes SQLite, and then
releases ownership. Repeated calls return the same result. On a storage/close
failure, the file lock remains held; the process owner must retain profile
ownership and surface the error instead of starting a replacement writer.

## Key layout and model ownership

The store has no dependency on the application model. Runtime code supplies its
typed domain validation and uses keys such as:

- `thread:<id>`, ordered under `threads`;
- `application:<collection>:<id>` and collection metadata;
- `private-session:<agent>:<key>` and its session-ID index;
- `settings`, `settings-revision`, `moku-applied-settings`, `tags`, and tag metadata;
- `event:<id>`, `lifecycle-work:<consumer>`, and
  `lifecycle-outcome:<consumer>:<event>`.

The store validates JSON and storage invariants, while the runtime validates
thread identity, expected revision, settings shape, collection schema, access
scope, lifecycle fact generation, and other product rules inside the transaction.
Order updates and referenced records must be submitted together. The generic
store deliberately does not infer record keys from an order kind.

## Lifecycle delivery and idempotent effects

`Tx.AppendEvent` appends a validated `store.Event` in the same transaction as the
business change. The event vocabulary includes `thread.title-changed` for actual
ordinary active Thread title changes, separate from generic entity updates.
Events use the registered lifecycle event names, millisecond
timestamps, subject `{kind, id, typeId}`, source, and JSON data. Event IDs cannot
be reused for different facts.

`Tx.SetWork(consumer, expectedBatchID, work)` starts a batch with an empty expected
ID or updates the matching active batch. Updates merge event IDs and preserve
existing receipts. Missing events, duplicate IDs, already acknowledged events,
stale batch IDs, and invalid retry fields are rejected.

`Tx.SettleWork` atomically removes active work and records `processed` or `failed`
for every event in the batch. Acknowledgements remain independently of active
work, including across application restarts.

`Tx.ApplyReceipt` checks the consumer/batch/key fence, returns an existing result
when present, or executes a business effect in an isolated child transaction.
Its result and business writes commit together. If the effect fails, none of its
staged writes enter the parent transaction. `ReadReceipt` and `RecordReceipt`
also support callers implementing their own domain transaction composition.
Receipts deduplicate transactional state changes; an irreversible external side
effect still requires its own idempotency mechanism.

`Snapshot.Events`, `Pending`, `Work`, and paged `History` support restart recovery
and consumer processing. Events sort by creation time and then ID. Scope, type
and source indexes select streams before reading event bodies; returned event
data remains detached from the immutable index. `NewEvents` compares selected
streams against a previous snapshot; long-lived live subscriptions use
`EventReader` to retain only those streams and seen identities.

Pending queries exclude acknowledged events. Long-lived consumers use
`PendingReader` to retain their unacknowledged selection and reconcile only
changes to those streams and their own outcomes. Already processed history does
not become recurring work on every notification. The reader serializes concurrent
calls, supports older snapshots, and copies its filter/exclusion inputs. Neither
reader retains a complete prior snapshot: idle scoped consumers do not pin old
unrelated thread or private-session bodies. Their retained event/outcome branches
belong to the selected lifecycle streams.

`QueryHistory` applies explicit event IDs and exclusions before pagination;
an empty non-nil ID list selects nothing. It joins outcomes only for returned
events, using the reverse outcome index. Batch reads therefore do not walk all
pages of history to find a handful of requested identities. `History` is the
filter-only convenience wrapper. Scope authorization remains the caller's job.
These indexes are derived from validated records and rebuilt on open; the
durable keys and logical values belong to the same store transaction.

## Source and verification

[store.go](store.go) owns admission and transactions, [sqlite.go](sqlite.go) owns
schema and durable writes, and [chunks.go](chunks.go) owns large-record reads and writes.
[snapshot.go](snapshot.go) and [index.go](index.go) own
immutable reads, and [lifecycle.go](lifecycle.go) owns events, work and receipts.
[lifecycle_index.go](lifecycle_index.go) owns query indexes and pending readers;
[lifecycle_subscriptions.go](lifecycle_subscriptions.go) owns routed notifications.

**PBT-STORE-SNAPSHOT** checks committed key/value histories. [The property](../../../tools/verification/pbt/store/snapshot_property_test.go)
uses Rapid to generate 1–80 transactions of 1–8 puts/deletes across overlapping
ASCII, Unicode and 1,010-byte prefixes, 20 key suffixes and integer values.
The independent model is a plain map of committed values. For each generated
transaction, `Keys`/`Count` must match exact prefix selection; `ChangedKeys` in
both directions must match value additions/removals/changes; `PrefixEqual` must
agree with an empty diff. A randomly selected retained snapshot must preserve its
old values despite subsequent writes. These are the immutable read/prefix/diff
contracts implemented by `snapshot.go` and the persistent index in `index.go`.

**PBT-STORE-LIFECYCLE** generates append, batch, receipt, settlement, rollback and
close/reopen sequences against real SQLite. An independent event/acknowledgement
model checks scoped pending selection, incremental readers, history outcomes and
transactional effect counts. Repeated receipt keys retain their first result;
failed child effects and failed outer transactions cannot leak writes. Stale
batch IDs cannot mutate work. Reopening retains pending work, receipts and outcomes.
The [property](../../../tools/verification/pbt/store/lifecycle_property_test.go)
uses 1–60 actions, three scopes/consumers, bounded receipt keys and generated
processed/failed outcomes; timestamp ties exercise deterministic event order.

**PBT-STORE-STREAM** starts with the [distributed Alpha v1 schema](https://github.com/hupao-creator/Chief/blob/df9ad830c3811d31759e110b5b0cd899969255ab/internal/core/store/sqlite.go).
The [property](../../../tools/verification/pbt/store/stream_property_test.go)
checks exact stream prefixes from 2–7 concurrent producers, duplicate retries,
rollback on a late SQLite statement failure, size changes, deletion and reopen.
It compares the recovered bytes and receipt after a child exits directly after
COMMIT. A copy cut inside that transaction’s WAL frames must recover the
preceding revision and its exact bytes. The cut follows the
[SQLite WAL format](https://www.sqlite.org/fileformat2.html#the_write_ahead_log).
Malformed physical chunk sequences must fail to open. These on-disk
transitions and crash boundaries are outside the integer snapshot property.

The [write benchmark](../../../tools/verification/runtime-performance/sqlite-writes/README.md)
attributes changes and file writes to an isolated workload with two session kinds.

Run `make pbt-go`. These properties do not cover power-loss/fsync faults,
multiple writers or allocation/performance bounds. See the [PBT guide](../../../tools/verification/pbt/README.md)
for seeds, sample budgets and minimized replay files.

The [Runtime benchmark](../../../tools/verification/runtime-performance/README.md)
measures selected production calls; timing and allocation observations do not
prove transaction, ownership or cancellation correctness.
