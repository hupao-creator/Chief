# Native reading lifecycle

The [native package guide](../app/macos/README.md) defines reader policy across
Codex, Claude, Pi and OpenCode. The [WindowNavigation guide](../app/macos/Sources/Host/WindowNavigation/README.md)
owns route and return admission; [PluginUI](../app/macos/Sources/Shared/PluginUI/README.md)
owns shared reading components. [E2E-READ-001](../tools/e2e/README.md#current-scenario-contract)
automates mounted reader/successor/history/return semantics on the declared Codex
boundary. It does not certify exact pixels, every reader/loader or physical input.
IME, historical-fork input and uncertain-receipt recovery remain outside these
scenarios. Actual runs and their fixed revisions are separate evidence.

## Content and execution identity

Agent detail displays settled assistant replies and compact live follow-up
text/time rows. Initial/internal user input, plans and ordinary info/warning
notices do not appear. Pending permissions/questions and independent errors remain
readable. Unfinished assistant bodies stay hidden until the message settles.
Running/waiting executions retain settled replies; terminal executions retain the
last non-error reply and an explicitly targeted reply outside work summaries.
Intermediate replies and failed tools remain execution work. The Agent reader shows reasoning and tool counts when work is visible.
The window shows a manual steer in the running execution as soon as the composer
captures it. Each local steer reserves its final row height and enters from
18pt below with the 420ms reading replacement curve. The capture time belongs
to the command, so subsequent steers can enter independently and transcript
refreshes retain each row's progress. Reduce Motion shows the settled row
immediately. The entrance leaves scrolling to the reader's existing follow or
manual position. When the result anchor moves to a new tail row, the preceding
reply stays mounted at its measured height. [Send identity and ownership](composer.md#send-identity-and-ownership)

Empty no-output bookkeeping does not create a visible execution summary.

Codex, Claude Code, Pi Agent and OpenCode each decode their own native protocol
and saved state into ordered transcript occurrences. The shared layout selects
replies by message identity. Adjacent text parts of one reply share one Markdown
document so headings, emphasis and links can cross a native part boundary.
Intervening reasoning or tool calls keep their position. Child-session messages
belong to execution work and an explicit visit can reveal the selected message.
Only a primary reply supplies the execution result and its directory preview.
Repeated native snapshots update their occurrence. Separate calls, messages or
diagnostics may legitimately have identical text.

The thread manifest carries a bounded preview, the turn resource supplies the
reading body, and an execution-detail resource carries deferred work. A terminal
turn retains message anchors, pending or independent diagnostics, and presence
for stripped bodies. The same layout selects visible rows after reopening.
Request forms use a common header and action layout. Each plugin owns its
native field types, permitted answers and response identity. [Adapter paths](../internal/plugins/harness/README.md#thread-markdown) · [Transcript layout](../app/macos/Sources/Shared/PluginUI/Conversation/ThreadTranscript.swift)

Current and historical documents resolve the title and author for their exact
execution. Missing historical titles use its instruction or timestamp, never the
mutable current Thread title. Outgoing and incoming title/author ink follows the
same vertical document ownership. Deferred data and optional detail loaders update
at one stable renderer site so loader availability does not replace the reader.

Source: [ThreadConversation](../app/macos/Sources/Shared/PluginUI/Conversation/ThreadConversation.swift),
[execution groups](../app/macos/Sources/Shared/PluginUI/Conversation/ThreadExecutionGroups.swift),
[Harness host](../app/macos/Sources/Host/HarnessHost/NativeHarnessThreadSurface.swift).

## Reading palette

Agent reading uses the shared thread palette: dark canvas `#232323`, surface
`#2b2b2a`, strong surface `#333331`, text `#d4d3cf` and strong text `#eeeeec`.
SwiftUI and AppKit/TextKit resolve the same palette; status, contrast and Reduce
Transparency keep their own rendering boundaries. Source: [NativePalette](../app/macos/Sources/Shared/PluginUI/Design/NativePalette.swift).

## Opening and return

The panel uses compositor-owned geometry and 420ms travel. Native animation-start
admits hidden preparation of an ordinary Agent reader while travel continues.
Drawing, input, accessibility, text entrance and secondary surfaces wait for
arrival and their own readiness. Report and Collection entries mount their
readers on arrival. The same Agent reader survives arrival. Both title anchors must exist;
coalesced native layout supplies the opening geometry. If reserving an Execution
Sidecard changes the horizontal landing during entry, the compositor can
redirect the flying title and emoji once from their presented positions to
the measured main-column anchors. Live window resizing admits the handoff
when panel travel finishes.

The history index uses row metadata. A scoped reader constructs the selected
body through its Harness renderer. For inline content, copies of a row share
its first materialized view within that projection. A new projection owns a
fresh body even when the execution ID stays the same.

Direct historical/result requests select their destination before the page stack
mounts. A never-visited current page need not acquire and construct its body
behind the historical page. Once visited, current/history scroll ownership stays
with that reader. Late anchors respect `userPositioned`; a new explicit request
starts a new positioning identity.

Closing retains the native return: reader ink fades over the first 80%, shell
travel reaches the refreshed source at 86%, and the final 14% crossfades to card
content. Closing before primary admission uses the opening-reversal path.
A mounted direct-input Dock closes its input gate, folds in the reading column,
and turns its Harness mark back to the eyes. Agent panel return prepares the
canvas immediately and travels while the Dock folds. A Report with a mounted
Harness mark waits for the turn before preparing its return.
A deleted/archived source supplies no stale return target. Route/generation
identity fences all preparation and completion callbacks.

The reading parent uses the window's existing material, without capturing the
Overview bitmap. It keeps the native Overview owner and hides its host after
entry. Hiding is deferred out of `updateNSView` so AppKit focus handoff does not
reenter SwiftUI layout. Showing is synchronous during return preparation.
Hidden display projection/layout coalesces dirty state while the authoritative
catalog, membership, selection, drafts and task work continue. Return installs
current content and viewport, waits for canvas preparation, then samples its frame.

Source: [page stack](../app/macos/Sources/Shared/PluginUI/Conversation/NativeReadingPageStack.swift),
[parent](../app/macos/Sources/Shared/PluginUI/Conversation/NativeReadingParentSurface.swift),
[return](../app/macos/Sources/Shared/PluginUI/Conversation/NativeReadingPanelReturn.swift).

## Data and native layout

Route prefetch uses the production manifest and at most one Harness-owned opaque
row scope. Host code does not parse a Harness timeline to invent that scope.
The Runtime client retains at most four ready idle live subscriptions for 30s,
with an 8MiB accounting budget. Idle wires continue processing patches. Pending,
failed, stale, gapped or oversized resources do not transfer. Releasing a consumer
retires its ID immediately; transfer gives the wire a fresh owner. The cache
owns data, never views, actions, scroll state, selection or Sidecards.

Changed opaque state validates/decodes off main. Same-thread prepared inputs and
state publish together; changing Thread starts a new admission. Native text and
AppKit mounting remain main-actor work. Read-only transcript views disable
Writing Tools. Finite parent width/height proposals are answered directly by
native carriers; unspecified proposals retain native sizing. Timeline geometry
has a narrow observation owner; precise scroll offsets are neither throttled nor
used to invalidate the entire parent timeline.

Source: [retention](../app/macos/Sources/Core/RuntimeReadingRetention.swift),
[timeline](../app/macos/Sources/Shared/PluginUI/Conversation/ThreadTimeline.swift),
[transition](../app/macos/Sources/Shared/PluginUI/Conversation/NativeReadingPanelTransition.swift).

## Report and execution Sidecards

Report commits folded layout, matching HTML query revision and WebKit main-frame
completion before related-card admission. Primary travel and layout must also
finish; a cancellable 200ms admission interval starts after readiness. WebKit
`didFinish` does not certify all later scripts/assets. Covering, replacing or
closing retires that visit. A body edit within an admitted visit uses the same
WebKit view. The previous page stays readable while the matching revision is
fetched. WebKit reloads the document at its existing address and the active
sidecard keeps its layout. The stable Report route remains exempt from composer
suppression during selected-execution handoff.

List state uses a 3:7 Sidecard-to-Report ratio; exact execution detail uses 5:5,
subject to shared width/stacking constraints. HTML stays mounted, anchored left,
and its viewport follows shell width continuously. A selected execution waits for
scoped content and Markdown readiness, then fades one retained host over 200ms.
Hidden controls/accessibility cannot act. Streaming/retry does not replay the
entrance; unavailable/error content admits as readable content.
The referenced execution timeline adds 20pt of top padding inside its scrolling
document. The floating Back control stays anchored to the sidecard viewport.

The Report visit owns the related list's prepared excerpts. An open related
sidecard prepares them even while showing an execution. List reveal waits for
the current excerpt sources, with a progress indicator while preparation is
pending. Back reuses ready text even when the list rows remount. Preparation is
cancellable on source changes, folding, coverage and exit. Unchanged source text
is reused within the visit, and a source with no eligible excerpt needs no parse.

Sending from a finished or historical execution immediately turns the Report
sidecard to the submitted page. The old viewport moves up as the new one enters
from below. The new page shows the submitted heading and the source Harness's
inline connection status. The receipt binds the accepted execution to this same
page. Its prepared reader takes over in place after landing. A same-execution
steer keeps the reader and scroll position.

The Report, sidecard column and open composer stay in place throughout the
handoff. The source draft accepts typing while the request is pending. The
destination owns actions only after its reader, exact input and column are ready.
Only an observed runtime cancellation target enables Stop. Rejection restores
the source run and draft. Folding, changing selection or leaving the Report
retires the submitted page's authority to navigate.

The Back button stays outside the
carrier and returns to the list. Exact forks and uncertain receipts retain the
[Runtime](../internal/core/runtime/README.md) and [client](../app/macos/Sources/Core/README.md)
authority boundaries. No guessed resend follows an uncertain outcome.

When an ordinary Agent opens with an eligible active execution, the selected
Sidecard reserves space for the previous execution in main during preparation.
The shell still fills the reader and the Sidecard aperture stays folded. Once
the main document and heading are ready, the first body fades in at its
prepared width while the main shell contracts and Execution unfolds from its
launcher. Later toggles use the current selection and retained document.

On ordinary execution completion, the active Sidecard folds to its real launcher
using the shared 380ms fold. Fold completion and destination-content readiness
are independent gates; only when both finish does the 420ms downward page turn
start. Late content keeps the old main reader visible with the Sidecard folded.
Outgoing width is retained; the incoming reader lays out at destination width.
Handoff/execution identity fences cancellation, coverage, replacement and resize.
These transitions do not request editor focus.

Source: [Report presentation](../app/macos/Sources/Shared/PluginUI/Conversation/NativeReportSidecardPresentation.swift),
[execution scroll](../app/macos/Sources/Shared/PluginUI/Conversation/NativeReportExecutionScroll.swift),
[Agent workspace](../app/macos/Sources/Host/Sidecards/NativeAgentThreadWorkspace.swift).
