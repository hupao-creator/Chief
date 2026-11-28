# Runtime authority

[runtime.go](runtime.go) constructs the state owner from injected Harnesses, store, workspace, attachment and service capabilities. [composition](../composition/bootstrap.go) supplies concrete plugins and attaches the Application host and Moku coordinator. Runtime does not discover plugins through global mutable registration.

## Threads and content

Archive is a persisted **display-hidden** flag, independent of execution state.
Ordinary Thread archive never deletes content/history, releases attachments,
ends native sessions, interrupts foreground/background work, or revokes
send, interaction, configuration, fork and explicit reading capabilities. New
work on a hidden Thread leaves it hidden; a fork creates a new visible Thread.
Normal inventory/Overview filters omit archives, while explicit reads and search
with archive inclusion continue to use retained records. Moku conversation
history has a separate `MokuHistory` read-only policy; it is not inferred from
archive. Existing tag decoration freeze/reclassification on restore is unchanged.

Application archive resolves persisted associated Thread identities within the
same store writer transaction as the document flag. Super Thread references to
older executions still hide the whole source Thread, including a newer active
execution. Duplicate sources and already-hidden sources are idempotent; deleted
sources stay absent. Invalid sources or storage failures roll back the whole
change. No associated Super Thread/Collection is recursively archived, no links
are removed, and restoring a report does not restore its sources.

[threads.go](threads.go) owns thread identity, execution admission and serialized session access. Harness session data remains opaque; each Harness validates it and produces its public observation and renderer projection. Accepted work belongs to the service and survives client disconnection.

[Explicit worktree removal](worktree.go) requires an idle ordinary Thread.
The command lease, native admission and cancellation gates fence foreground,
background and pending input during retirement. The base cwd continues to own
directory scope. The Thread retains native history with an empty execution
`worktree.cwd` and its previous directory in `worktree.removedCwd`. Further
execution requires a new Thread. Git unregistration retires execution even when files remain. A retry on that Thread can complete pending ownership cleanup. [Workspace contract](../../services/workspaces/README.md#explicit-removal)

Attachment cleanup follows durable owner removal. Thread deletion releases its
attachment references after the database commit; startup and history reset first
reconcile surviving Thread/private-session owners and then collect. The attachment
service protects native drafts and live import processes independently, so failed
admission does not consume a draft. Unreadable client ownership stops collection
without preventing startup. See the
[attachment ownership contract](../../services/attachments/README.md).

Ordinary Threads retain `executionTitles`, keyed by exact execution ID. A
successful metadata completion commits its title and ownership atomically with
its metadata revision; input retention alone never copies the current Thread
title onto a new execution. Later naming changes only the covered execution.
The map survives reload and accompanies catalog envelopes, independently of lazy
conversation bodies. Forks retain matching inherited execution identities.

[execution_titles.go](execution_titles.go) performs one transactional startup
backfill for older records. Lifecycle title changes prove naming commits;
`thread.input-accepted` facts identify possible owners since the previous commit.
A change is restored only when exactly one execution could own it. Input
admission alone cannot exclude an older pending result, because metadata
retention failures are nonfatal. Repeated tag/settings snapshots do not prove
naming completion. Equal-millisecond input/execution boundaries, conflicting
facts, missing history and an unknown initial title leave gaps. Existing
explicit entries take precedence.
The migration neither consults the mutable current title nor runs a model;
unknown titles remain absent so the reader uses the execution timestamp.

Catalog snapshots contain bounded overview projections. [projection_cache.go](projection_cache.go) and [publisher.go](publisher.go) provide revisioned catalog/content publication. Full conversation, turn and execution bodies use independent content subscriptions.
Publication reconciles structurally changed store keys into private identity maps;
an activity-only wake or telemetry commit does not enumerate the catalog. Only
changed Thread/application records are projected and compared. Private session
updates decode their own record and publish the active-run list only when its
facts change. Explicit snapshots still materialize the complete public state,
and structural ordering patches carry their complete required order. Failed
Thread renderers retain the existing null projection and retry only that identity.
`Snapshot` and `Publish` serialize catalog projection and overview-cache updates
under `projectionMu`. `Snapshot` returns detached state; replays attached to a live
Runtime use that public read boundary so the background publisher retains the
same cache ownership.
The Moku catalog carries a bounded audit preview of the latest execution.
The stored transcript retains tool operations as audit history.
Loading a reading page does not reopen a native execution process. A coordinating-Harness change retains the prior Moku record as an archived, read-only `mokuHistory` conversation, including its native state and attachment ownership. These histories cannot be unarchived, forked, reconfigured or executed; native history questions and automatic admission also reject them. An explicit Moku history reset removes them and releases their attachments. Settled execution details are fetched on disclosure; live turns retain the information needed for output and interactions.

The composer's known-directory lookup takes one store snapshot and reads each
cwd from the matching immutable Thread record in the catalog cache. A changed
record is decoded on demand. Each lookup repeats Harness discovery and policy
checks and resolves each distinct cleaned path once, preserving the first
eligible spelling for a canonical directory.

Thread enumeration preserves stored order and appends unlisted records with
linear identity reconciliation. Committed-thread subscribers receive owned
records: native state, settings, metadata and transcript bytes are copied without
re-encoding the complete history; the public observation remains deeply detached.

Interaction replies claim their execution/interaction identity durably before
native I/O. Only an explicit adapter guarantee that no I/O began releases that
claim; an uncertain acknowledgement never permits duplicate submission. Public
form preflight passes typed native values through the internal response handoff.

Commands validate their execution/interaction identity before mutation. A follow-up whose reserved execution ended before input was retained may reserve a successor once. A dispatched failure is not automatically resent or used to rewrite an already terminal execution. Cancellation is fenced to its admitted execution, so a late interrupt cannot cancel a successor.

Direct execution readers can supply `expectedExecutionId` on follow-up. The
Runtime compares it with the authoritative latest execution after native-owner
recovery, under the existing cancellation/admission gate. A mismatch returns
`EXECUTION_CHANGED` before dispatch/reservation; ordinary follow-ups omit the
field and keep their existing behavior. Historical continuation uses the same
`ForkThread` ownership, native-work and revision gates, with an opaque
Harness-owned `executionId` selector. Busy sources remain unavailable for fork;
the caller retains its draft instead of steering the source or truncating it.

Ordinary Threads retain optional `mokuInterruptedExecutionId` only after the
`interrupt_thread` capability successfully stops the captured execution and its
committed outcome is `interrupted`. The dedicated capability captures execution
identity under the same cancellation gate as user Stop; it never infers source
from a terminal status. It rejects Moku/history targets, fences successors and
holds admission closed through provenance retention. User Stop and lifecycle
teardown cannot supply tool provenance. A background-only stop does not relabel
an older foreground outcome; reopening a session may settle abandoned work and
that recovery is not attributed to the tool.

The gate returns `stale` when the requested cancellation identity has changed,
there is no active foreground execution, pending input or background work to stop, or
a stop already owns the gate. A successful stop request returns `cancelled`.
Both user Stop and Moku receive this decision. The committed execution outcome
and its interruption source are separate facts.

The field survives catalog projection, refresh and restart. Missing historical
or unknown provenance stays absent, with no status-based backfill. Forks clear
it. Native failure or uncertain acknowledgement does not add it, even if a
cancelled input happens to settle. A crash or failed store write between native
stop and provenance retention conservatively leaves the interruption visible.
A successful native stop must already have committed the matching interrupted
outcome; a future asynchronous/uncertain outcome is not retroactively attributed.
The field records the successful host cancellation request, not native forensic
evidence of which event physically stopped a process if an external native stop
races that request. It changes presentation only, never status or archive state.

User Stop retains `userInterruptedExecutionId` through the same cancellation gate
and acknowledged terminal-outcome checks as tool provenance. Successful retention
clears the other source marker. Lifecycle teardown, recovery settlement, failed or
uncertain stops and background-only cancellation supply no user marker. Forks
clear both markers; a later execution cannot reuse an earlier marker for archive
eligibility. The acknowledgement transaction records the ordinary Thread's
`thread.interrupt-acknowledged` lifecycle fact with source `user` and attaches
it to the matching terminal outbox entry. The coordinator defers that execution's
interrupted delivery while the user Stop is in flight. An error releases the
original terminal without attribution. A process exit before acknowledgement
also leaves the original terminal available on restart. The native Overview offers quick archive only for this exact user
interruption with no pending input or background work, using the existing
`thread:set-archived` command and normal catalog invalidation.

### Chief conversation

The `moku-conversation` content scope belongs to the current Chief Thread. On demand, Runtime reads one profile snapshot and merges that Thread’s full coordinator transcript with its retained, read-only Chief sessions. The compact catalog preview is limited to recent operations and truncated text. The [conversation projection](moku_conversation.go) reads the stored audit rows directly.

Existing SQLite records may contain a legacy `note` field. Typed Thread reads ignore it and preserve the owner, session state and transcript. Loading a profile requires no rewrite. Historical tool operations stay in the audit. A successful Talk contributes its public text to the conversation.

The coordinator records the original user input after admission. The reader takes complete user messages, their attachment names, completed successful `talk` arguments, and the coordinator’s `chief-failure` rows. The failure projection exposes a public reason code, receipt state and command target. The original resend payload stays in the owning transcript. Archived failures are readable. The [Talk submission limits](../../services/moku/README.md#talk) apply at tool invocation. Saved replies keep their full text, including those beyond the current submission limits. Directories retain their submitted mention text. Native Harness turns can include injected context and are ineligible as a dialogue source. Assistant reasoning, diagnostics, dispatches, timers, failed or pending Talk calls, and private tool arguments have no dialogue row.

Rows use the owning Thread and audit ID for identity. For a transported user submission the audit ID is `steer:<commandId>`. Internal submissions without a transport command use a generated ID. Pages advertise this admission contract with `commandRowIds: true` and retain all stored row identities, including earlier opaque IDs. Equal text from distinct records appears twice. Pages follow audit creation time, breaking ties by saved session order and transcript position. Each page returns up to 64 messages within a 1 MiB source budget, allowing a single larger message on its own. Its optional `before` cursor identifies the earliest returned source row. A fresh subscription without a cursor follows the newest page. A history reset replaces the owner and removes retained sessions. The [SQLite store](../store/README.md#file-ownership-and-format) owns recovery across restarts, including profiles using the legacy database directory. Cleared or missing audit rows cannot be reconstructed from the catalog or from a model prompt.

The [global voice call](../../services/moku/README.md#global-voice) counts as service activity through native teardown. A competing request fails while the current media lease is live. After the runtime observes cancellation, a new request can wait for the previous relay to finish cleanup. Cancelling the waiting request drops it. Releasing the media lease leaves accepted Chief executions under the same runtime cancellation and persistence rules as typed input.

## Settings

[settings.go](settings.go) separates saved settings revision from streaming thread revisions. `app:update-settings` checks the DTO, application schema and local Harness settings shapes, preserves retained execution profiles and compares `expectedSettingsRevision` in the store transaction. The save performs no native snapshot or catalog acquisition. A conflict returns the latest settings; invalid writes leave state unchanged. An unchanged save does not advance the revision.

The [Settings DTO](../model/state.go) contains ordinary Harness defaults, Moku's separate concrete execution profiles, plugin settings and desired plugin enablement. Ordinary thread settings are saved session configuration, not a live reference to global defaults. Thread configuration has its own CAS revision. Moku and background agents retain the configuration of already admitted work; newer saved settings apply at their next admission boundary.

Changing Moku's Harness preference requires idle ordinary Agent Threads and
Moku: running or waiting executions, native background work and pending inputs
reject the save without changing settings. Actual cross-Harness replacement
checks again and reserves the native admission boundary through old-owner
cleanup and durable replacement. Its triggering queued Moku input may proceed
on the new owner afterward. Private Report/Tag executions do not themselves
block switching; every in-flight native service admission still does. The
replacement gate has no per-command admission exemption. Unrelated settings
retain their existing save behavior.

Every new Moku execution crosses the same `admitMokuExecution` guard in
[threads.go](threads.go): initial Send, successor renewal after a proven
unconsumed end, and native Accept. Configuration admission covers direct Runtime
SendMokuThread callers as well as coordinator callers. Background work does not
exempt a new foreground execution. The guard uses an in-process callback captured
in the prepared injection, installed before native Open; missing authority blocks.
Native new work during Open is rejected before reentrant locking or projection.
All three host execution-ID reservation sites precede native input/project with
this guard; Commit still rejects unreserved execution IDs.

Exact configuration-pending results permit one coordinator reprepare. Other
Core pre-consumption rejections use `MokuAdmissionRejectedError`, preserving the
reason and allowing durable outbox release after completed rejection. Exact native
`ErrExecutionEnded` is the only native result that enters successor renewal;
wrapped/uncertain native outcomes never gain this retry/release permission.
Background configuration discovery also fences reuse of an existing idle
session. A settings-save race re-resolves the configuration without spending a
batch execution attempt; admitted batches and their retries retain their profile.

Configuration admission uses a cancellable gate. A settings presentation that
leaves its page releases its waiting HTTP request even when another native
discovery still owns the gate; a cancelled waiter never enters the operation.
Nested preparation shares the owning admission context.

Settings presentation and startup recovery discover missing execution profiles
outside that gate. Their short commit merges only changed execution fields,
checking the selected Harness's source rather than unrelated Harness defaults.
An initialize-only read of a pinned profile with a concrete host preference
uses committed settings without entering the configuration gate or writer queue.
A disabled background binding also has no capture to commit. Presentation still
loads current Harness facts and rechecks the selected source and workspace
before replying. Global reads compare the JSON values of that profile. A save that
only changes object-key order leaves the pending read valid. Selecting a host for an automatic preference or capturing a
missing profile requires the normal gated merge. Concurrent initializers reuse
an already saved profile and preserve the selected host, even when a late native
reply differs; captures of different Harnesses retain both profiles. A changed
source with no saved execution profile still invalidates discovery. Prompt,
plugin enablement and retained independent edits remain authoritative. An
initialized presentation preserves the stored application JSON when no execution field changes; reordering
JSON keys must not advance the settings CAS revision. User settings saves
use their original CAS revision and real execution admission keeps the gate
until native acknowledgment.

An independent role editor may request `previewIndependent` with its global
application binding. It loads the selected Harness in the role's own workspace
using the retained independent profile or, on first use, Chief's saved profile.
The preview is read-only with respect to saved configuration. A missing profile
can be filled in the editor, and cold execution can capture a missing slot when
it needs one. A preview rechecks its source and workspace after the native read.
Each actual execution continues to resolve its saved configuration at admission.

[configuration.go](configuration.go) initializes missing internal execution profiles from actual native facts. It persists complete choices before use and fences late discovery against newer saves. Background settings select inheritance from Moku or an independent profile. Native credentials and context budgets remain Harness-owned. Moku and background agents use their built-in system instructions; execution profiles do not contain a system-prompt replacement.

Report and Tag execution settings have independent optional `enabled` switches,
with omission meaning enabled. These switches take effect live, independently of
plugin registration. After committing settings, Runtime synchronously revokes
current background attempts through the Application host before releasing
configuration admission. Native configuration, sends and spontaneous starts
check saved enablement; semantic-tag writes check it inside the store transaction.
Disabling does not clear data, execution profiles, lifecycle work or receipts.

Plugin enablement is captured by the composition at startup. Saving desired `harness:`, `extension:`, `context:` or `sidecard:` keys does not change active registrations until the service restarts. Built-in Git has no switch. Client appearance, language, selection and drafts belong to the [native client](../../../app/macos/Sources/Core/README.md).

## Lifecycle and directory scopes

[lifecycle.go](lifecycle.go) records facts in the same transaction as their business change. Subject identity/type and event source are distinct. Retired Moku histories retain their `moku` subject type and are excluded from ordinary-task capabilities, semantic-tag mutation and directory-scope discovery. Durable consumers retain batches, retries, receipts and outcomes; live subscriptions observe new commits without replaying old events. Moku receives ordinary terminal notifications through its durable outbox and direct user-input facts through live subscriptions. Background agents own their own processing queues.

Lifecycle subscriptions route commits by scope, event type/source, consumer work
and outcomes, and the exact observed private-session record. An unrelated scope
does not wake its runners. Live readers reconcile added matching facts; durable
readers retain pending identities and reconcile only their streams and outcomes,
without repeatedly decoding acknowledged history. Both retain selected lifecycle
index branches rather than complete old snapshots. Private-session observations
still wake their runner independently of new lifecycle facts. Batch history reads
select requested event identities before pagination and join only their outcomes.

[scope_agents.go](scope_agents.go), [background_scope.go](background_scope.go) and [lifecycle_capability.go](lifecycle_capability.go) bind background instances to explicit directory scopes. Inbox is a valid scope, distinct from global authority. Task reads, events and private-session access intersect the owner's binding. Report and Tag use per-directory instances; their native sessions initialize lazily and are disposed when idle.

The title-only ordinary-task inventory snapshot in [capabilities.go](capabilities.go)
reads the host-captured immutable snapshot, filters by the explicitly bound
directory and excludes archived Threads, Moku and retained Moku history. Report
joins those identities with its binding index before each actual background send
to list unclassified Threads; inventory does not expose execution status or
history and cannot substitute for successful-execution evidence.

## Coordination state lifetime

Command locks count both holders and waiters. Only the final lease release
removes a lock, so deleting a thread cannot split concurrent callers across two
command gates. Cancellation gates retain live-session identity and pending send claims;
a deleted session's gate is reclaimed after its final reference is released. History reset prunes unreferenced gates after removing durable session records. Unknown-ID requests do not retain gates.

History questions share one 90-second deadline across waiting for the source command lock, opening the Harness and reading its history. An earlier caller deadline wins. Expiry cancels the read and returns an error after native cleanup. An independent Harness failure during opening or retirement remains observable alongside the deadline. Queued readers can leave independently while the current owner retains its lease.

## Shutdown and history reset

[service.go](service.go) revokes admission and drains participants and native owners before storage ownership is released. A protocol disconnect alone is not proof that a child process exited. Cleanup errors remain observable and prevent a replacement owner.

History clearing stops participants, restores sessions that require cleanup, drains native owners and rechecks public/private background observations before replacing history in one SQLite transaction. Settings survive a full clear. Failed cleanup preserves history and fences the generation; it does not silently erase uncertain native work or start another owner.

Factory reset uses the zero-argument `history:prepare-reset` write to perform
the same native owner recovery, cancellation, drain and background-work
recheck. A successful preparation keeps the generation fenced until shutdown.
Workspace cleanup and the history replacement transaction belong only to
`history:clear`. The [profile owner](../../platform/profile/README.md#factory-reset)
commits the native confirmation after the daemon drains receipts and closes storage.

The [property boundaries](#property-boundaries) define Runtime admission, outbox
and optional system coverage. [E2E observation](#e2e-observation) describes the
selected mounted Settings/read journeys. The [verification index](../../../tools/verification/facts.md)
separates implemented contracts, generated domains and actual run evidence.

Automatic installation discovery uses `harness:detect-installation` with one
Harness ID. Each response is independent and does not refresh the login shell.
Explicit `harness:detect-installations` recovery still refreshes the environment
once before the parallel batch. Neither endpoint interprets installed as
account authentication. The [isolated HTTP benchmark](../../../tools/verification/local-http/README.md)
times these public reads. Its diagnostic build measures configuration gate wait
and native presentation time inside the handler. Production requests do not
emit per-stage timing samples.

## Lazy Moku notifications

[moku_delivery.go](moku_delivery.go) owns a durable system-notification outbox.
Direct user follow-up admission writes its lifecycle event and lazy notification
in one transaction. Terminal facts keep their wake-producing behavior. A stable
transaction sequence orders facts; source deletion and full history reset retire
pending deliveries. Moku Harness replacement does not discard pending work.

`SendMokuThread` bundles pending lazy notifications into system context and fences
the selected identities immediately before native I/O. Admission removes exactly
that batch. `sendLockedAdmitted` rejects an idle lazy-only admission and does not
renew it after an exact `ErrExecutionEnded` or `ErrFollowUpUnavailable`, so finishing races cannot start a
run. Confirmed unconsumed idle/configuration results release their attempt fence;
other uncertain native outcomes require the existing operator reconciliation.
An admission receipt does not prove model processing or task completion.

Moku's `GrepThreads` reads the current profile's committed ordinary-thread cache,
including archives and busy owners, excluding Moku/history and deleting owners.
It supplies Harness-owned public passages to threadsearch without a derived
index, then fences returned hits by source hash. Directory Scope filters
reuse the existing scope resolver. No native history is opened. See the
[grep contract](../../services/threadsearch/README.md#moku-deterministic-grep).

Overview browsing does not apply agent-authored hidden-card markers. Retired visibility and reading-evidence records are left untouched; ordinary archive, execution eligibility and Report coverage still determine browsing membership.

## Moku recovery-only handles

Stopping a restored Moku execution may open its native session before model
catalog preparation, without any injection. Such an owner is marked
`recoveryOnly`; it can restore/settle/interrupt but cannot admit new native work,
receive user sends or interaction responses.
Ordinary Thread recovery and existing fully prepared Moku handles are unchanged.

A later Open/Send with injection does not retrofit the callback onto this owner.
Under the thread lock, Runtime checks cancellation, native admission, pending
sends and the latest foreground/background state. An idle recovery owner is
fenced closed, then all admission/state gates are released before native Close
and callback draining. Only successful cleanup removes that exact cached owner;
Runtime rereads durable state and opens a new native handle with the complete
injection, including tools, instructions, context and AdmitNewExecution.

Concurrent Stop is fenced by the cancellation gate. Active/background recovery
reports busy instead of being replaced; cancellation remains available. Native
Accept on a recovery owner rejects before the configuration lock, so a Close
performed by normal preparation cannot deadlock on such a callback. Early send
rejection remains explicitly unconsumed; interaction replies reject before
claiming an answer. Cleanup failure leaves the owner fenced and prevents a new
native owner from overlapping it. No new execution ID or input is reserved merely
by replacing the idle recovery handle.

## Tag classification state

[tag_statusbar.go](tag_statusbar.go) captures one scope's active title-only Threads,
stable-ID tags and assignments from one immutable snapshot. Its content revision
fences atomic mutations without reacting to unrelated stream writes. The writer
checks revision, active membership and scope in the receipt transaction and returns
current status on conflicts. A pool may contain a semantic tag named after the directory. Pool edits preserve distinct surviving assignments on existing Threads. [tags.go](tags.go) keeps public name/emoji projections
and report source decoration synchronized while preserving stable tag identity.
Archived Threads retain frozen decoration and do not consume active membership;
restoration clears assignment before emitting `thread.restored`. Clearing
labels retains the [Thread's classification history](../model/README.md).
Actual title
changes emit `thread.title-changed`, independently of execution terminal facts.

Moku model routing presets are validated settings fields, participate in
configuration equality, and are captured at execution
admission. Missing/custom keeps existing manual routing guidance. Selecting a
preset preserves that guidance for later restoration; the Moku service owns
general routing priorities and instruction generation.

## Property boundaries

**PBT-RUNTIME-SETTINGS** orders a pinned execution or ordinary defaults
presentation around public saves of routing guidance and optional Claude model edits.
The native capture and the real Claude save normalizer can serialize the same
fields in different orders. Completions before commit, after commit or
through cancellation check which source may be returned and which operation may
advance the revision. **PBT-RUNTIME-ROLE-SETTINGS** checks read-only independent
previews, conflicting saves and retention across retry. It also checks that cold
initialization captures only the missing slot. The
[properties](../../../tools/verification/pbt/runtime/settings_property_test.go)
use a real Runtime and isolated SQLite with controlled Harness adapters.

**PBT-MOKU-OUTBOX** drives the production delivery queue and attempt/admission
transactions against SQLite. Generated lazy/waking deliveries, repeated IDs,
captures, late arrivals, acknowledgements, confirmed rejections, uncertain
errors and close/reopen schedules check stable sequence ordering, atomic attempt
fences, exact-batch removal and restart-only reconciliation. A stale capture
cannot claim an already attempted delivery. Uncertain outcomes stay fenced;
only exact pre-consumption rejections release a live attempt. This property
isolates the durable outbox; it does not establish native admission or scheduler
wake behavior. See [the property](moku_delivery_property_test.go).

**PBT-RUNTIME-ADMISSION.** The send worker retries only an exact
`plugin.ErrExecutionEnded` for an unadmitted follow-up. `renewSendAdmission`
requires the captured execution's durable terminal result before reserving one
successor. Joined errors, rejection, cancellation, missing terminal evidence and
post-admission failures do not authorize replay. `Admitted` is the acknowledgement
boundary; each accepted input emits exactly one `thread.input-accepted` fact.
A post-admission dispatch error may fail a newly reserved running execution but
must preserve an existing terminal's identity, outcome and start time.

The [generated admission schedule](../../../tools/verification/pbt/runtime/send_property_test.go)
drives real Runtime and SQLite with a scripted native peer. Each case has 1–25
accept/reject/end/end-reject/end-failure/end-cancel/invalid-retry/admitted-failure
actions and generated completed/failed/interrupted native outcomes. The oracle
checks acknowledgements, execution identity/status, native attempt count and
event count after every action. After each history, a Moku stop must either
interrupt the still-running execution with exact provenance or report a stale
target and preserve the settled record revision. An immediate repeat is stale.
Two subsequent public follow-ups exercise a rejected and a successful user Stop.
A poll between native settlement and acknowledgement checks that the terminal
is withheld. After the command returns, the property checks the direct input's
source and content, a single waking terminal and exact acknowledgement attribution
across the queued executions.
Closing the scripted owner joins send workers before observation. The property
covers the send-return/terminal/cancellation seam, not real
native processes, arbitrary concurrent clients or physical input.

**PBT-SYSTEM-COMBINATION.** Composition connects Runtime, authenticated HTTP,
Moku, Report, Tag and SQLite. The retained native system property exercises
idempotent command receipts, scoped consumer effects, exact execution references,
settings CAS, source-preserving reads/forks, interrupt fencing, deletion/clear and
restart retention through these production boundaries. Archive is display-only:
reads, follow-up and fork remain available. Generated archive/restore actions
read public state after each report command and before issuing any individual
Thread command. Archiving hides the report and its cited Threads. Restoring
only shows the requested report. Other records keep their visibility and all
identities remain present. After reading the first completed child, Moku requests
a batch stop for that child, a missing target and the same child again. The peer
checks aggregate failure, ordered identities, both stale acknowledgements and
the missing-target error on the actual tool result. The scenario checks native history content from an assistant reply,
not merely a token in user input. A scripted loopback model provider is the
external peer; it does not implement admission, tool handlers or domain writes.

The [system property](../../../tools/verification/pbt/system/system_property_test.go)
generates 1–3 scopes, independent no-fault/429/500/truncated-SSE choices for Moku,
child, Report, Tag and read roles, 0–6 read/archive/unarchive/settings/followup/fork/
interrupt actions, then optional delete and clear. Its oracle checks terminal
convergence, empty delivery work, report ownership/exact execution evidence,
scope/tag isolation, source preservation and unchanged retained facts after
reopening the profile. These expectations correspond to the lifecycle/settings
contracts above and the [Report](../../plugins/applications/report/README.md),
[Tag](../../plugins/applications/tag/README.md) and [Moku](../../services/moku/README.md)
module contracts. Active-delete/active-clear/recreate actions are outside this
generator even though its scenario helper supports them. No Context acquisition,
real model service, all Harness matrix or crash recovery is claimed.
The model peer reads Report's lifecycle batch separately from its appended
Statusbar. Tag discovery uses `read_statusbar`; `create_tag`/`assign_threads`
carry the current revision and stable IDs from actual scoped tool results.
Foreign-scope probes must be rejected. The fixture does not synthesize tag
membership or bypass the production CAS/receipt path.

Run `make pbt-go` for admission; `CHIEF_SYSTEM_CODEX=/absolute/path/to/codex
make pbt-system` for the opt-in macOS system property. Missing CLI capability
fails instead of skipping. The system scenario has a 90s total execution budget,
30s convergence waits and bounded native discovery/cleanup; runner timeouts also
bound generation/shrinking. See the [PBT guide](../../../tools/verification/pbt/README.md)
for budgets, failure evidence and replay. System coverage requires an actual run;
its source or successful compilation alone is not a pass.

## E2E observation

The [desktop interaction runner](../../../tools/e2e/README.md) uses authenticated
`state:load` and scoped content subscriptions as independent observations.
`E2E-READ-001` supplies an ordinary `thread:follow-up` while a real reader is
mounted, then checks the successor and historical mounted execution identities.
The follow-up receipt and exact scoped reply remain evidence; this input is
external setup, not a composer UI action. `E2E-SETTINGS-001` changes a mounted
preset control and closes Settings through its production gate before checking
`settings.moku.routingPreset` and the reopened selection. The runner neither
reads/writes SQLite directly nor uses private diagnostics. Runtime cancellation,
restart/reconnect, race and admission invariants are outside these interaction
scenarios; their ownership is PBT. Actual coverage is the selected scenario's
run receipt, not the existence of these public commands.
