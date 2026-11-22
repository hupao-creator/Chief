# Lazy loading measurements on macOS

The largest avoided cost in this workload is opening the directory picker on a
populated catalog. The reader also reaches both the current and historical
document sooner. Plugin registration and OpenCode manifest projection can skip
work that their consumers never request.

Baseline `3c704bca318ed9a9ab8435f70e1beaa2987b6d9d`, measured product
`dac48e309cf248957564b1f10810a5081161a590`. Apple M1 Pro, macOS 26.5.1,
Swift 6.3.2 debug products, Go 1.27.3 with `GOMAXPROCS=2`. The native sample
set uses five fresh processes on each side, baseline group first. Go uses
fresh adjacent pairs in alternating order, four pairs for directories and six
for OpenCode. Builds and observations used the project's exclusive leases.
The tables give medians. No sample was discarded. These are component timings
with no calibrated UX budget. [Reproduction commands](README.md) ·
[Source, collector and executable hashes](evidence/subjects.json)

## Registration and reading

| Operation | Baseline | Measured product |
| --- | ---: | ---: |
| Register all four Harnesses and compose plugins | 19.433 ms | 0.669 ms |
| Construct their four native logo views | 0.037 ms | 0.042 ms |
| First explicit request for encoded Codex logo | <0.001 ms | 16.364 ms |
| First explicit request for encoded Claude logo | <0.001 ms | 2.894 ms |
| Build manifest metadata for 256 rows | 0.271 ms | 0.225 ms |
| Inline fallback builders called while building this directory | 256 | 0 |
| Mount current body and reach settled selection | 550.394 ms | 179.428 ms |
| Select first historical body and reach settled selection | 1139.733 ms | 643.187 ms |
| First inline read after scoped visits | 0.001 ms | 0.017 ms |
| Builders called across two reads of the same inline row | 0 (prepaid) | 1 |

All four encoded logos matched by SHA-256 (26,035 bytes of data URLs in
total). Both versions exposed 199 translation entries. The first translation
read per Harness took 0.042–0.126 ms on the measured product, and the combined
repeat logo/catalog read took less than 0.001 ms per Harness. The PNG cost is
real on first explicit access. The native Codex and Claude Overview cards and
reader headers draw their vector logos directly. The measurements exclude font
registration, runtime launch, transport and display scanout. [Native samples](evidence/native.jsonl)

Both versions mounted precisely the latest and requested historical fixture
bodies. The reader now computes the history-ID set once per filter and reads
the selected row directly. These changes remove repeated scans from rendering
and input-target evaluation. The timings above cover this change together with
lazy inline bodies. They include layout, transition and semantic polling with
simple synchronous text. The builder counts isolate the work avoided by the
lazy bodies. [Reading contract](../../../design/reading.md)

## Runtime directory picker

Each process opened a fresh SQLite fixture and performed normal runtime catalog
initialization before the first timed call. Its 256 Codex Threads each had 16
executions, a 576,733-byte record and the same cwd. The prior independent SQL
audit reported 207 ms and about 283 MiB at this size. The controlled workload
below disables optional native workspace discovery on both sides. The same
audit separately measured opening its populated store at 231–244 ms with
about 295 MiB allocated. Opening the store and publishing the first catalog
remain eager. The picker result below counts only the subsequent lookup.

| Lookup | Baseline ms | Product ms | Baseline allocated bytes | Product allocated bytes |
| --- | ---: | ---: | ---: | ---: |
| First after catalog publication | 216.754 | 0.223 | 298,061,048 | 160,368 |
| Repeat, five calls per process | 209.358 | 0.176 | 298,060,680 | 160,368 |
| After inserting an unlisted Thread | 211.589 | 1.049 | 301,895,440 | 1,311,232 |
| After deleting that Thread | 211.079 | 0.185 | 298,136,748 | 160,368 |

The snapshot-matched catalog already owns each decoded record for publication.
The picker reads its cwd and resolves each distinct cleaned path once per call.
Fresh snapshot hashes fence concurrent updates. The first, insert and delete
results contained 1, 2 and 1 directories respectively. Discovery and policy
callbacks still run per request. The amounts measure cumulative process
allocation during each call and include concurrent publication where applicable.
The workload does not time SQLite open, catalog publication or a real Harness
CLI scan. [Runtime samples](evidence/runtime.jsonl) · [Catalog ownership](../../../internal/core/runtime/README.md)

Four additional pairs exercised replacement under the same Thread ID using
the extended directory collector. Moving one Thread produced two directories
in 0.985 ms (baseline 203.556 ms). Replacing its record with invalid data
returned an error on both sides. Repair restored one directory in 0.972 ms
(baseline 204.457 ms). Every process also checked pre-cancelled discovery.
The source hashes distinguish this collector from the first directory series.
[Refresh samples](evidence/directory-refresh.jsonl)

## OpenCode projections

One 1,096,447-byte saved state supplied 128 executions with 8 KiB tool results.
Projection-local indexes decode original fields on demand. The manifest uses
the validated message previews and skips the raw message index. Other scopes
still pay for any original tool fields they consume.

| Request in visit order | Baseline ms | Product ms | Baseline allocated bytes | Product allocated bytes |
| --- | ---: | ---: | ---: | ---: |
| Overview | 8.055 | 7.837 | 5,398,056 | 5,397,592 |
| Manifest | 7.641 | 4.338 | 5,579,376 | 2,891,048 |
| Current turn | 7.120 | 7.224 | 5,271,000 | 5,265,496 |
| First historical turn | 7.096 | 6.982 | 5,265,456 | 5,267,924 |
| First full historical execution | 7.027 | 7.033 | 5,286,256 | 5,285,784 |
| Manifest again | 7.478 | 4.266 | 5,579,376 | 2,885,584 |

Output lengths and SHA-256 matched for every request in all six pairs.
The repeated manifest still saves work after full detail was read, as each
request has its own source. The current-turn median rose by 0.104 ms and the
full-detail median by 0.006 ms in this sample. [Runtime samples](evidence/runtime.jsonl) ·
[Renderer contract](../../../internal/plugins/harness/opencode/README.md)

## Other boundaries examined

| Candidate | Reason for retaining current behavior |
| --- | --- |
| Delay profile opening, recovery or first catalog publication | The app acquires the profile lease before its runtime and loads preferences before creating the workspace. The first complete catalog establishes Overview membership. Sharing the already materialized records eliminates the second history decode without adding a store schema or postponing the first card. [Launch](../../../app/macos/Sources/App/Chief.swift) · [Runtime](../../../internal/core/runtime/README.md) |
| Mount Overview cards only when visible | Stable slots already route content-only deltas to changed cards. Exit animations and return targets use retained structural identities, and the canvas owns accessibility and hit targets. The component measurements do not establish an offscreen-scroll benefit that justifies changing those lifetimes. [Overview](../../../app/macos/Sources/Host/Overview/README.md) |
| Defer the reader or every history mark until interaction | Reader preparation overlaps the 420 ms panel travel. Prefetch requests the manifest and at most one row. Four ready subscriptions can transfer for 30 s within an 8 MiB budget, with separate speculative and foreground cancellation. Fixed-height sidebar marks already mount a viewport plus 17 rows. Their metadata supports preview, keyboard and accessibility without acquiring bodies. [Reading lifecycle](../../../design/reading.md) · [Sidebar](../../../app/macos/Sources/Shared/PluginUI/Conversation/ThreadHistorySidebar.swift) |
| Delay Browser setup, Report covers, bundled typography or Settings probes | Browser creates a WebKit session on open. Report cover documents are fetched for mounted covers, cached by content revision and appearance (16 entries), and pause offscreen playback. Deferring visible covers or font registration into first layout risks an extra first-paint dependency. Settings prefetch already filters installed/enabled Harnesses, cancels superseded work and revalidates at five minutes. The workloads above do not measure a benefit for further deferral here. [Browser](../../../app/macos/Sources/Plugins/Sidecards/Browser/NativeBrowserSidecard.swift) · [Covers](../../../app/macos/Sources/Plugins/Applications/Report/NativeReportCover.swift) · [Fonts](../../../app/macos/Sources/Shared/PluginUI/Design/NativeTypography.swift) · [Settings](../../../app/macos/Sources/Host/Shell/NativeWorkspaceSettingsPrefetch.swift) |

## Interaction and verification scope

- The [product e2e](../../e2e/README.md) ran with the clean product revision,
  twelve prepared tasks, native Codex CLI 0.171.0 and a deterministic loopback
  provider. Overview scroll limits and position on return, first reading,
  settled follow-up, historical selection, Back, close, and Settings edit and
  reopen passed. The runner independently verified the retained report.
- The [four-Harness replay](../../e2e/thread-transcript/run.py) passed all 77
  samples on the clean revision. It covered streaming, waiting for permission,
  error, completion, detail expansion, remount and archive in Agent and Chief
  readers. The Codex case exercised focus, selection and Return.
- A supplementary system AX client performed three successful presses in a
  256-row native reader. The buttons exposed their localized labels and
  historical/current values. The selected body went from turn 255 to 254,
  back to 255, then to 254 again, with zero fallback constructions. The
  isolated foreground window and its child AX client were launched directly
  under the authorized terminal. Initial nonactivating-panel probes could
  read semantic state but exposed no usable AX tree to the probe. A
  LaunchServices attempt produced no action receipt. Only the direct
  foreground-window run contributed AX observations.
- The Store snapshot property passed 100 generated cases at seed 20261122.
  It exercises the immutable snapshot and its prefix/diff queries. The
  directory workload separately checks the Runtime cache hit and miss path.
  [Property inventory](../pbt/README.md)
- The commit hook ran architecture and registration checks, gofmt and
  `go vet ./...`. The project e2e builder produced the Runtime and Swift
  debug App with warnings as errors. Initial sandboxed preparation hit
  SwiftPM's nested sandbox and Go build-cache permissions. Authorized
  builds completed before taking samples.
- The optical collector's no-prompt preflight reported accessibility, input
  and capture available. A paired, calibrated signed Release App campaign,
  physical input latency, VoiceOver speech and IME composition were outside
  this collection. The results support component-level decisions only.
  [Verification receipts](evidence/verification.json) · [Signed UX scenarios](../../benchmarks/gate/UX.md)

The verification commands used fresh output directories and serialized
heavy runs with the project's performance and desktop leases.

```sh
python3 tools/e2e/thread-transcript/run.py --output "$RUN/transcript"
python3 tools/e2e/build.py --go ./scripts/go.sh --with-app
python3 tools/e2e/run.py run --runtime .build/e2e/chief-runtime \
  --app app/macos/.build/debug/Chief --desktop-owner "$OWNER" \
  --desktop-lease /private/tmp/mokusei-ui-verification.lock --output "$RUN/desktop"
python3 tools/e2e/run.py verify "$RUN/desktop"
python3 tools/verification/pbt/run.py --property PBT-STORE-SNAPSHOT \
  --seed 20261122 --cases 100 --artifacts "$RUN/pbt"
```
