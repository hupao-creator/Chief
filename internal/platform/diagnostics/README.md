# Development diagnostics

The macOS application and bundled Go Runtime emit local operational events to
the macOS unified log. Both require the development bundle identifier
`com.mokusei.native.dev` and the bundled
`Contents/Resources/build-provenance.json` channel `development`. The Runtime
checks the enclosing bundle of its resolved executable. Build configuration
and environment variables do not select logging. A standalone executable and
the production, Alpha and demo bundles leave this subsystem quiet. A
development client can still connect to an existing Runtime started elsewhere.
Events then reflect each process's own bundle.

```sh
/usr/bin/log stream --style compact --predicate 'subsystem == "com.mokusei.native.dev.diagnostics"'
/usr/bin/log show --last 30m --style compact --predicate 'subsystem == "com.mokusei.native.dev.diagnostics"'
```

The `native` and `runtime` categories share the same event format
`operation phase trace=<digest>`. To follow one operation, filter for its
`trace=` value. A renderer command, content subscription or voice attempt
can carry a fresh random UUID over authenticated loopback. The logger uses a
96-bit SHA-256 digest of that UUID. Runtime-only operations can generate an
independent trace. Background, recovery and UI boundaries without a shared
operation can have an empty trace or start a fresh one. Trace identity is
independent of command receipts, execution IDs and application state.

Events contain code-owned labels, with no error descriptions, command arguments,
user or model text, audio, URLs, filenames, filesystem paths, account metadata,
credentials or native tool output. The two backends write to the OS log,
where macOS controls access and retention. Business records, response envelopes
and startup-error files keep their own semantics. The diagnostic stream is
best-effort and does not establish audit completeness or performance results.
Per-frame, per-token, routine content-delta and successful polling events are
outside the instrumentation. Successful store commits do not emit log entries.

## Module boundaries

Depth here means that callers can accomplish something through a small
contract while the owner hides materially more policy or state. The
[Go import checker](../../tooling/architecture/check.go) and
[Swift package graph](../../../app/macos/Package.swift) describe dependency
boundaries. Depth is judged at the named operation and can vary inside a
package.

| Boundary | Interface and complexity it owns | Diagnostic events |
| --- | --- | --- |
| [Daemon and profile](../daemon/service.go) · [Profile](../profile/profile.go) | `Serve` and `Acquire` own canonical-profile exclusivity, launch and publication ordering, cooperative revocation and joined cleanup. | Ownership failure, bootstrap, ready, drain and exit. |
| [Transport and receipts](../transport/executor.go) · [Receipt lookup](../transport/receipt_query.go) · [Content](../transport/content.go) | Invoking a channel hides HTTP admission, detached durable write execution, deduplication and outcome lookup. Content subscriptions hide revisioned publication and bounded delivery. Depends on the host port and profile. | Known command received/invoked/outcome, traced receipt lookups and asynchronous content failures. |
| [Store](../../core/store/store.go) · [SQLite commit](../../core/store/sqlite.go) · [Lifecycle index](../../core/store/lifecycle_index.go) | `Update` and `Snapshot` hide serialized durable commits, immutable published snapshots and lifecycle indexing. System SQLite is the persistence dependency. | Lifecycle validation and SQLite commit failures. |
| [Runtime](../../core/runtime/threads.go) · [Projection](../../core/runtime/publisher_incremental.go) · [Settings](../../core/runtime/settings.go) | Command callers receive execution admission and public projections. Runtime owns concurrency fences, workspace and attachment ownership, execution acknowledgements, settings CAS and incremental projection. Its operating contract spans multiple capabilities. | Send admission/native dispatch, missing acknowledgements, projection failures, settings transitions and semantic-tag changes. |
| [Chief coordinator](../../services/moku/coordinator.go) · [Thread search](../../services/threadsearch/grep.go) | `Submit` hides serialized Chief ownership, resolved context, configuration admission and native handoff. `Grep` hides bounded retrieval across authoritative Harness text. | Chief input admission and context failure, and a retrieval outcome. |
| [Harness port](../../core/plugin/harness.go) · [Codex](../../plugins/harness/codex/adapter.go) · [Claude](../../plugins/harness/claude/harness.go) · [Pi](../../plugins/harness/pi/adapter.go) · [OpenCode](../../plugins/harness/opencode/thread.go) | The common `Open` and `Handle.Send` operations hide four native protocols, state translation, process ownership and recovery. Native engines own their provider authentication, models and execution. | Shared dispatch/admission and discovery boundaries, outside native payloads. |
| [Workspaces](../../services/workspaces/manager.go) · [Attachments](../../services/attachments/repository.go) · [Dispatch configuration](../../services/dispatchconfig/configuration.go) | Prepare or retain calls hide Git worktree proofs/rollback, attachment staging/ownership and versioned provider acquisition. Dependencies are Git, the profile filesystem and Store respectively. | Worktree validation/rollback, file staging/retention and publication/fallback. |
| [Application Host](../../hosts/applicationhost/operations.go) · [Background Runner](../../plugins/applications/background/runner.go) · [Report](../../plugins/applications/report/domain.go) · [Tag](../../core/runtime/tags.go) · [Git](../../plugins/applications/git/monitor.go) | Domain commands and background behaviors hide scoped capability checks, transaction receipts, batch recovery, references or tag effects. Git owns bounded external process reconciliation. | Traced domain commands, admitted batches, Tag mutation, and Git polling failure transitions. |
| [Context Host](../../hosts/contexthost/collect.go) · [Artificial Analysis](../../plugins/contexts/artificialanalysis/source.go) · [Discovery](../discovery/cache.go) | Collection and cache reads hide contribution policy, timeout/fallback, bounded coalescing and stale publications. Artificial Analysis is an external evaluation data source. | Collection/fallback, traced acquisition and actual discovery probe results. |
| [ChiefCore client](../../../app/macos/Sources/Core/RuntimeClient.swift) · [Composer](../../../app/macos/Sources/Shared/PluginUI/Composer/NativeComposerDraft.swift) · [Settings](../../../app/macos/Sources/Host/Settings/NativeSettingsDraft.swift) · [Onboarding](../../../app/macos/Sources/Host/Onboarding/NativeOnboardingState.swift) | The app owns profile connection, offline reconciliation, durable draft handoff, save conflict/rebase and first-run admission. Calls cross to Go through authenticated local transport. | Connection/stream, command delivery and settlement, draft handling, save and setup transitions. |
| [Overview](../../../app/macos/Sources/Host/Overview/NativeOverviewCanvas.swift) · [Reader](../../../app/macos/Sources/Host/HarnessHost/NativeHarnessThreadSurface.swift) · [Report](../../../app/macos/Sources/Plugins/Applications/Report/NativeReportApplication.swift) · [Browser](../../../app/macos/Sources/Plugins/Sidecards/Browser/BrowserWebSession.swift) | Native layout, reader resources and WebKit navigation each hide state ownership beyond their initiating action. Harness reader plugins translate their own state into the shared UI. | Scene geometry admission/errors, reader binding and subscription failure, Report reference failures, browser navigation outcomes. |
| [ChiefVoice](../../../app/macos/Sources/Voice/GlobalVoiceSession.swift) · [Codex voice relay](../../plugins/harness/codex/voice/relay.go) | Start, stop and mute hide permission, media leases, signaling and native V3 session handling. LiveKit WebRTC and the native Codex service sit at the media/provider boundary. | Call/media transitions, relay admission, handoff and failure. |

Public DTOs, [plugin declarations](../../core/plugin/application.go),
[static registration](../../../app/macos/Sources/Composition/NativePlugins.swift)
and presentation leaf views are thinner boundaries. The workspace shell and
the plugin UI target aggregate several distinct boundaries. Their routing and
rendering contracts expose more detail to callers than the narrower
`RuntimeClient`, composer and storage operations. Shared UI algorithms
such as the [Overview packing solver](../../../app/macos/Sources/Host/Overview/NativeOverviewLayout.swift)
or the [Markdown parser](../../../app/macos/Sources/Shared/PluginUI/Reading/NativeMarkdownParser.swift)
can be deep in isolation, with diagnostics at their owning interaction boundary.
[Build and signing](../../../app/macos/build/README.md),
[architecture validation](../../tooling/architecture/check.go) and
[benchmark judgment](../../../tools/benchmarks/gate/README.md) have substantive
complexity in their own interfaces. They run outside the packaged application
and retain their own CLI and evidence outputs.

The platform's [bounded process runner](../processgroup/run.go) and
[work pool](../workpool/pool.go) are deep at their own operation boundaries
because they own cancellation, cleanup and resource limits. Diagnostic ownership
sits with the features that call them and can distinguish a user operation
from recurring maintenance.

## Local verification

Build a development package with `make dev ARGS='--no-open'`. A headless
check can use an isolated Runtime profile and a Swift client linked against
ChiefCore. Match native and Runtime trace digests for a request and verify
that the log contains only the documented event fields. Check channel gating
with a production identity, a mismatched channel and a standalone executable.
