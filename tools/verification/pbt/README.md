# Property checks

The main boundary is the Go runtime: `core/runtime` owns admission and durable
application state; `services/moku` owns coordination, the admission queue and tool
lifetimes; `core/store` supplies atomic persistence and lifecycle consumption.
Composition connects these owners to Harnesses, applications and HTTP. “Moku
runtime” is this cooperating boundary, not every package or just Moku's prompt.

Properties call production implementations with generated domains and invariant
oracles. Scripted peers control native outcomes without implementing host rules.
No ordinary example/table tests are included. Reduced counterexamples are replay
corpus inside generated properties. UI interaction belongs to e2e and experience
timing to benchmarks. Process deadlines are hang guards, not experience targets.

## Contract map

Owning module docs define current semantics and detailed bounds. The executable
[inventory](properties.json) ties contracts to exact entry points; the runner
selects only these entries and requires evidence that they actually ran.

| Property ID | Contract and generated domain | Oracle / boundary |
| --- | --- | --- |
| PBT-RUNTIME-TAG-MEMBERSHIP | [Tag classification](../../../internal/core/runtime/README.md#tag-classification-state). Generate two to four existing assignments and create, rename or merge a semantic tag into the folder name. | Check the committed pool and assignment identities through the Runtime statusbar. Covers persisted multi-tag records that the current single-assignment API cannot create. |
| PBT-RUNTIME-ADMISSION | [Runtime](../../../internal/core/runtime/README.md) with 1–25 native accept/reject/end/failure/cancel actions followed by Moku stop requests and two public follow-up/Stop pairs | Exact retry permission, execution identity, one event per acknowledged input, acknowledged or stale stops, direct input source and terminal attribution before/after the native Stop response in real Runtime + SQLite |
| PBT-RUNTIME-SETTINGS | [Settings admission](../../../internal/core/runtime/README.md#settings). Initialize a missing profile, then generate 1–6 public routing saves, optional Claude model edits and default or pinned-profile reads, replying before commit, after commit or cancelling | A read accepts the same choices across Claude normalization and JSON key reordering, rejects a superseded source and can cancel independently. Each save alone advances the settings revision. The [HTTP measurements](../local-http/README.md) exercise the transport separately. |
| PBT-RUNTIME-ROLE-SETTINGS | [Settings admission](../../../internal/core/runtime/README.md#settings). Generate 1–4 Harness slots, a selected Harness, an optionally missing slot and retained independent choices. Preview both roles, race two same-revision saves, then retry the loser. | Preview uses the role workspace and correct retained or Chief source without writing. Save rejects unknown Harness IDs, performs no native snapshot calls, and publishes one winner with a usable conflict receipt. Retrying preserves both roles. A later cold initialization captures only the missing selected slot. |
| PBT-MODEL-FORM-PREFLIGHT | [Public form preflight](../../../internal/core/model/README.md). Generate hidden/required/default/answer combinations for one string question. | Hidden answers never leave the process or become active questions. A hidden field with no default validates without an answer; an active default still validates and is handed off to the Harness. Visible `required` without a value remains rejected. |
| PBT-MOKU-WORKTREE | [Workspace removal](../../../internal/services/workspaces/README.md#explicit-removal). Generated order of content, index, file type, conversion and lock cases, including equal-size edits with restored mtime | The injected Chief tool preserves private recovery commits, direct shared refs, the index and other workspace users. Git permission failures leave either the checkout or the registration behind. Retries across restart preserve sibling registrations. The domain includes committed cwd renames, empty directories with and without verifiable birth time, byte-identical and changed text, multi-row fetch history, SQLite and registry write faults and name reservation in disposable repositories and profiles. |
| PBT-MOKU-CLAUDE-TOOLS | [Chief tool schemas](../../../internal/plugins/harness/claude/README.md#chief-tool-schemas). Generate direct and deferred target inventories, valid, missing or malformed worktree choices, optional cwd and absent, blank or named worktree labels. | Every published Chief tool passes Claude's root keyword restriction. The advertised creation schema and the server parser both enforce the workspace choice on these inputs. |
| PBT-MOKU-OUTBOX | [Runtime](../../../internal/core/runtime/README.md): 1–12 rounds of 1–10 lazy/waking arrivals, attempts, rejection/acknowledgement, reopen/reconcile | Stable order, atomic uncertainty fences, exact-batch removal, late arrivals retained; not scheduler wake behavior |
| PBT-DISPATCH-ADMISSION | [Moku creation](../../../internal/services/moku/README.md), unavailable OpenCode directory and generated native outcome | Actual injected tool dispatches once, retains the created Thread identity and reports the destination result |
| PBT-DISPATCH-PUBLICATION | [Dispatch configuration](../../../internal/services/dispatchconfig/README.md), two-provider update/restart traces | Latest visible choices, successful empty, late completions, failed refresh, notifications and private-field exclusion |
| PBT-DISPATCH-OPTIONS | [Adapter dispatch](../../../internal/services/dispatchconfig/README.md), generated unpublished IDs and native selectors | Four production adapters encode the request with discovery offline and reject launch overrides |
| PBT-DISPATCH-LIFECYCLE | [Moku delivery](../../../internal/services/moku/README.md), active/idle/waiting transitions and changes to selected options | Natural input gets the latest publication. Live delivery targets only the matching capable execution |
| PBT-MOKU-SEND | [Follow-ups](../../../internal/services/moku/README.md#follow-ups-to-ordinary-threads): permuted running, terminal, waiting, missing, Chief and Chief history targets with repeated IDs, generated prompts and malformed calls | Injected binding and real Runtime + SQLite preserve first-occurrence order, one durable admission per successful ID, execution identity, partial outcomes in the transcript and the flat legacy acknowledgement. Invalid requests admit no input. The native provider and model's choice of tool arguments are outside this property. |
| PBT-MOKU-CONVERSATION | [Chief conversation](../../../internal/core/runtime/README.md#chief-conversation) and [Talk](../../../internal/services/moku/README.md#talk). Generate 1–90 historical rows with time ties, repeated and long Unicode text or file-only submissions. Reopen an Alpha SQLite record with a legacy note, then admit a user message and repeated and multi-link Talk replies. Exercise the exact code-point limit and one above it with Latin, Han, emoji or combining scalars, and two versus three explicit breaks with CRLF and generated Unicode separators. | Check the admitted user row’s command identity and compare dialogue pages across a retained session, SQLite reopen, another profile and explicit reset. The tool and schema agree on admission, rejected replies never enter dialogue, and the catalog keeps the latest successful Talk verbatim. A seeded historical reminder stays in the stored audit after reopening and remains outside the later-execution catalog preview and dialogue. |
| PBT-MOKU-SCOPE | [Moku](../../../internal/services/moku/README.md): two owners, 1–12 executions, permuted/duplicate callbacks and configuration installs | Highest observed owner revision controls tools; retired scopes cancel |
| PBT-MOKU-QUEUE | [Moku](../../../internal/services/moku/README.md): 1–8 cohorts of 1–12 waiters and cancellation subsets | Cancelled waiters release behind held owner; surviving admission is exclusive; queue reusable |
| PBT-STORE-SNAPSHOT | [Store](../../../internal/core/store/README.md): 1–80 transactions, overlapping ASCII/Unicode/long prefixes, puts/deletes | Independent map oracle for exact prefix/diff results and snapshot immutability |
| PBT-STORE-STREAM | [Large records](../../../internal/core/store/README.md#large-records), Alpha v1 fixtures, 2–7 concurrent appenders, variable-length edits, SQL failure, retry and child exit | Every acknowledged revision has the expected bytes, including whitespace and Unicode. Reopen recovers a stream fragment and its receipt together. A WAL cut before the complete commit frame recovers the prior revision. Malformed chunk sequences fail to open. |
| PBT-STORE-LIFECYCLE | [Store](../../../internal/core/store/README.md): 1–60 append/batch/receipt/settle/rollback/reopen actions, three scopes/consumers | Independent fact/acknowledgement model; effect idempotency, rollback isolation, pending/history and durable work |
| PBT-CODEX-TERMINAL | [Codex](../../../internal/plugins/harness/codex/README.md#property-boundary-pbt-codex-terminal) with generated execution histories and command output containing NUL | Durable state decodes after each step. Command details preserve text and exit status, the first terminal outcome persists and each rejected follow-up retains its notice. |
| PBT-OPENCODE-QUOTA | [Account binding](../../../internal/plugins/harness/opencode/README.md#permission-and-account-boundaries). Empty settings, generated non-Go defaults, native credential switches, late replies, logout, binding faults and failed or missing meters with API keys or OAuth | The contributor preserves the account's reported percentage and window ID across model choices, withholds the prior account immediately on a SQLite credential revision and accepts only the current reading. Scripted native RPC and remote HTTP isolate route and lease faults that a single live account cannot reproduce. |
| PBT-MOKU-MESSAGE-TELEMETRY | [Message context](../../../internal/services/moku/README.md#context). Generate account changes and logout between messages with the periodic context already collected | Each outgoing context contains exactly the current message-scoped contribution. A periodic refresh cannot leave a duplicate stale account block. |
| PBT-AA-VERSION | [AA evaluation context](../../../internal/plugins/contexts/artificialanalysis/README.md). Independently generate roster, release, configuration and historical version labels, including missing and conflicting detail declarations. | Exact per-row attribution through mixed-version caches, conditional 304, restart and compact routing. The generated combinations cover stale or incomplete version evidence unavailable from one live capture. |
| PBT-CODEX-CATALOG | [Codex](../../../internal/plugins/harness/codex/README.md): client version, valid/malformed timestamp and a write before/during/after acquisition | Counted native probes distinguish reuse, one re-enumeration and reuse of the new result |
| PBT-CODEX-TIER | [Codex import](../../../internal/plugins/harness/codex/README.md#settings-tools-and-execution). Vary model-specific tier IDs, their order, native configuration and retained choices with overlapping display names. | Imported Fast pins a supported catalog ID. Explicit choices round-trip and unsupported tiers fail even when another model advertises them. |
| PBT-OPENCODE-ROUTING-RECOVERY | [OpenCode discovery](../../../internal/plugins/harness/opencode/README.md). Generate a committed or rolled-back account switch, zero to two changes during acquisition and one 502, 503 or 504 from the native model GET. | Two SQLite connections exercise real lock contention with a scripted native model service. The routing entry returns only a complete catalog for the settled source, preserves the prior identity on rollback, honors caller timeout and stops after a second source change. |
| PBT-OPENCODE-EXECUTION-CATALOG | [OpenCode settings](../../../internal/plugins/harness/opencode/README.md). Permute native directory success, a paid route with missing credentials and a native read error for a retained Flash/max profile. | The execution editor receives settled model choices or a diagnostic. A retry can recover access. Scripted native replies exercise account exclusion and recovery without changing account credentials. |
| PBT-CODEX-REVIEWER | [Codex](../../../internal/plugins/harness/codex/README.md): native CLI versions around the support threshold, reviewer fields and generated managed reviewer lists or read failures | An unset native override gives the same capability as a recognized reviewer. Exclusions and unreadable requirements still block auto-review. Generated replies exercise managed policy combinations without changing the host's permissions. |
| PBT-REPORT-PREVIEW | [Report](../../../internal/plugins/applications/report/README.md): Go fuzz over bounded arbitrary HTML | Parser safety and preview code-point bound |
| PBT-OVERVIEW-GEOMETRY | [Overview](../../../app/macos/Sources/Host/Overview/README.md#property-boundaries): 0–18 cards, generated footprints and viewports with a height-limited projection | Top and bottom margins are 30pt each when the window is taller than 60pt and zero otherwise. Framing is invariant under independent tag filter and Chief Bar heights. Single rows at natural and half scale check the exact horizontal fit threshold and both scroll endpoints. Independent geometry constraints, regular-grid lower bound and exact area/fit of shuffled six-tile rectangles. Mixed five-card scenes vary width and span. Occupied cells expose any interior row gap that fits a single-row card below |
| PBT-OVERVIEW-COLLECTION | [Collection budget](../../../app/macos/Sources/Host/Overview/README.md#property-boundaries), 0–12 mixed-span ordinary cards and 1–2 types of 0–10 ranked reports in shuffled product order | At fractional viewport boundaries, score legal prefixes by production scroll distance and then member count. Before viewport admission, only default idle groups apply. Generated visits check length-adjusted foreground dwell, pauses, 30-minute aging and the 24-hour window for repeated short visits. |
| PBT-COLLECTION-REGROUP | [Member panel lifecycle](../../../app/macos/Sources/Host/Overview/README.md#property-boundaries), 9–12 Reports, 1–2 panels with 1–3 visits of 1–7 seconds each | Compare live group order before and after Back, at Close and after dismissal. Check saved reading evidence independently, including repeated short reads. |
| PBT-HARNESS-SETTINGS | [Settings](../../../app/macos/Sources/Host/Settings/README.md#mounted-harness-settings-property). Open a fresh, saved or Alpha profile. Permute discovery and visits across Codex, Claude, Pi and OpenCode, edit models and efforts or variants, optionally hold a cold publication, fail and retry detection or catalog reads, or race an overlapping save. | Mounted controls, draft and closed-page notices agree with complete choices. Check SQLite before close, after save/retry and on reopening. Scripted native replies expose orderings that one installed roster cannot reproduce. Failed refreshes retain the last published options. |
| PBT-OVERVIEW-STATE | [Overview](../../../app/macos/Sources/Host/Overview/README.md#property-boundaries): generated clearances, sparse and crowded starts, horizontal scroll, 18 event attempts plus reduced corpus | Mounted membership, scale, vertical containment and clamped horizontal position. Clearing the bars preserves geometry and the solve count. |
| PBT-SYSTEM-COMBINATION | [Runtime](../../../internal/core/runtime/README.md#property-boundaries) with 1–3 scopes, role-wise HTTP/SSE faults, action sequence and restart | Real Codex, composition and loopback provider. Checks ordered tool results for finished, missing and repeated stop targets, user Stop provenance in the Chief model request on generated interrupt actions, visibility immediately after each Report archive or restore, scoped effects and retained facts. |

The limited cross-boundary properties have distinct value: Codex's absorbing
terminal state supplies Runtime execution facts. Codex cache writes can occur
during enumeration and leave a fallback model list apparently fresh. Report parses untrusted agent
output; geometry has mathematical invariants. Collection membership has a finite set of legal prefixes with an independent scoring rule. Deferred regrouping spans multiple visits with different promotion times inside a single panel. Mounted Overview state has a
latest-wins convergence contract. Public form preflight owns a distinct adapter
boundary: hidden client answers are discarded before validation, so only a
generated hidden/default/answer combination can check that a required field is
never published without a satisfiable value. They do not justify expanding PBT
to every UI or plugin. The optional system property validates durable composition effects,
not user gestures. Power-loss recovery, all-Harness equivalence, live model
services, arbitrary concurrent clients and physical process crash recovery are
outside this inventory.

## Commands and budgets

From the repository root:

```sh
make pbt-go
make pbt-native
make pbt-native-state
CHIEF_SYSTEM_CODEX=/absolute/path/to/native/codex make pbt-system
make pbt-go PBT_ARGS='--seed 20261117 --cases 300'
python3 tools/verification/pbt/run.py --property PBT-MOKU-QUEUE --race --cases 300
python3 tools/verification/pbt/run.py --list
```

`make pbt` and `make check` use routine Go properties, native geometry, the collection budget and deferred regrouping.
Mounted state and system properties are opt-in. Run Swift builds/properties
serially. The system suite requires macOS, a native executable (not the npm
JavaScript launcher), `sandbox-exec` and loopback listeners. It uses isolated
profiles/configuration and a scripted model provider; it does not read user
conversations or contact a real model service.

Rapid defaults to seed 1 and 100 cases per property. Stream storage runs 30 cases, worktree removal runs 5 and the system property runs 3. Swift geometry and collection budgets
default to 480 seeds, deferred regrouping to 64, mounted Overview and Harness settings to 8 each plus corpus. `--cases` (1–10000),
`--seed` (nonzero UInt64), `CHIEF_PBT_CASES` and `CHIEF_PBT_SEED` control
generated budgets. `--timeout` defaults to 600s per property including compilation;
`--shrink-seconds` defaults to 30. Swift checks its shrinking deadline between
replays; one in-progress replay may finish afterward. Rapid has its own shrinking
bound plus Go's process timeout. The system scenario bounds execution at 90s,
with separate bounded native discovery/cleanup.

Report uses Go's native fuzz engine, 10s by default (`--fuzz-seconds`) and two
workers. Go exposes no deterministic mutation seed: replay the concrete corpus
input. A fixed corpus-only run is not the fuzz gate. `--cases`/`--seed` do not
control this engine.

`--go` selects the Go executable/wrapper (`scripts/go.sh` on macOS, `go` elsewhere).
`--swift-scratch` selects independent Swift build storage. On an offline machine
with all pinned dependencies cached there, `--swift-skip-update` uses resolved
versions without updating remotes; missing dependencies still fail. These options
do not modify global toolchain or package configuration.

## Replay and evidence

```sh
python3 tools/verification/pbt/run.py --property PBT-RUNTIME-ADMISSION --seed 20261117
python3 tools/verification/pbt/run.py --property PBT-RUNTIME-ADMISSION --failfile /absolute/counterexample.fail
python3 tools/verification/pbt/run.py --property PBT-OVERVIEW-STATE --replay /absolute/reduced.json
./scripts/go.sh test ./internal/plugins/applications/report -run FuzzReportHTMLProjections/CORPUS_HASH -count=1
```

The mounted settings property requires a macOS graphical session and the pinned
Go toolchain. It builds the settings peer in a temporary directory and creates
a new profile per trace and shrink attempt. Its [JSON corpus](settingspeer/testdata)
supports individual replay.

```sh
python3 tools/verification/pbt/run.py --property PBT-HARNESS-SETTINGS --seed 20261125 --cases 24
python3 tools/verification/pbt/run.py --property PBT-HARNESS-SETTINGS --replay tools/verification/pbt/settingspeer/testdata/alpha-reasoning.json
```

Rapid replays package `testdata/rapid` corpus before generated cases; ignored or
invalid corpus inputs make the runner exit 2. Explicit `--failfile` input is
snapshotted and hashed, decoded using Rapid v1.3.0's v0.4.8 format and executed
through `rapid.MakeFuzz` in a separate `explicit-replay` subtest. A completed pass
must be observed before generated checks run; malformed/version-mismatched or
out-of-domain input exits 2, a reproduced assertion exits 1. The summary records
the input identity and replay result separately from random counts. The
[test-only adapter](rapidcheck/check.go) is shared by all Rapid properties; it
does not enter product binaries. Failure emits a seed and minimized `.fail`.
Swift failures name the seed and input, save
`original.json` before shrinking, then `reduced.json`. Swift JSON replay executes
only that input and labels it as replay. Go fuzz writes failures to
`testdata/fuzz/FuzzReportHTMLProjections` with the concrete replay command.

Each invocation prints a new evidence directory, or accepts `--artifacts` naming
a directory that does not yet exist. `summary.json` records HEAD, dirty status,
tracked patch/untracked hashes, platform, commands, seed, budgets, elapsed time
and child exit codes. Each property has `output.log` and retained corpus; system
failures additionally retain provider/fault/convergence evidence and print
isolated profile paths. Evidence is diagnostic output, not production logging.
No production logging API is required. Business history, transcript and execution
results remain part of the property oracles.

Runner exits: `0` completed selected properties; `1` execution/assertion or missing
execution witness; `2` invalid configuration, missing declared capability, tool
launch/evidence error; `124` outer deadline; `130` interruption. Exact child exit
codes remain in the summary. Missing capability, skips, empty filters and timeouts
are never passes. Partial runs list only executed properties and cannot be
reported as a completed suite.

[Routine CI](../../../scripts/ci/README.md) runs the Go and headless native properties and uploads evidence.
Source/build success alone does not establish coverage. Record actual results
with the tested commit in the delivery record.

`python3 tools/verification/pbt/verify.py --output /tmp/replay-cli-evidence`
checks the real runner with generated malformed/version/word/exhausted inputs,
the Runtime admission corpus, and a temporary Go overlay that injects an oracle
failure after the real property. Removing the overlay proves that same input
passes the unchanged property. This CLI e2e verifies replay plumbing; it does not
add a Runtime property or ordinary example tests, nor certify every counterexample.
