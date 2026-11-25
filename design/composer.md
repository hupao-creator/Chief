# Resident composer ownership

The [MokuScene guide](../app/macos/Sources/Host/MokuScene/README.md) owns Dock,
Talk, input and draft behavior. [Core](../app/macos/Sources/Core/README.md)
owns durable receipt and attachment handoff.
[E2E-COMPOSER-001](../tools/e2e/README.md#composer-system-input-boundary) uses
operator-assisted system Accessibility input with independent public persisted
results; it is excluded from unattended hosted CI. OVERVIEW/READ/SETTINGS use automated
semantic controls. These scenarios do not cover IME, historical forks or uncertain
receipt recovery; demo fixtures do not establish Runtime delivery.

## Route, input and focus

Ordinary Agent detail selects its Thread draft and pins input open. Exact
history/result readers use a separate Thread/execution draft shared with Report's
selected-execution reader. Thread title/status changes do not replace an unsent
draft. A callback may consume only the submitted draft revision and captured
source; a late result cannot reopen another visit.

The input pin exists before the editor opens, through reading preparation and
the Harness identity flip. It suppresses closed-input running/submission orbit
ink throughout that ownership. Current active Thread input uses one trailing
action seat: Stop for an empty draft, Send for sendable text/attachments/directory
mentions. Import/submission/unavailable gates still apply. Historical input has
no authority to stop a newer execution. The Overview editor gives Send priority whenever its draft can submit. Its single
trailing seat otherwise shows Stop for a running Chief or disabled Send when idle. Stop is cancellation, without pause/resume semantics.

Escape and outside click do not fold a pinned Agent editor. Escape first lets
IME, completion, menus/sheets/popovers and explicit control cancellation act;
otherwise the bound current route closes through normal reading motion. A blank
panel-margin click closes detail only after a completed press. Reader,
Sidecards, capsule and directory candidates keep their normal actions. Press
ownership survives AppKit committing marked text or dismissing a popup.
TOC selection changes drafts without stealing focus. Opening Overview or showing
its empty-workspace input leaves the editor available for a click or Tab. The
Chief capsule and Compose command explicitly focus it. Initial Agent input and
explicit Browser annotation retain autofocus. The Dock requests automatic focus as the
current editor's text becomes visible. Explicit focus can acquire the admitted
editor earlier. Incoming-reader publication cannot be cleared by its outgoing owner.

In Overview, swiping up on Chief Bar opens its conversation around the same
editor. Opening from the collapsed Bar requests keyboard focus. The panel keeps
the Chief draft and stays open through admission and the reply. See the
[Chief Bar conversation contract](../app/macos/Sources/Host/MokuScene/README.md#chief-bar-conversation).

An unselected Super Thread document/list denies input expansion through the
shared scene gate, including capsule, shortcut/menu and automation requests.
Its associated execution borrows the pinned Agent composer after content/column
admission. Folding, Back, Browser replacement or departure retires that input.
Browser annotation uses the resident composer beneath its actual Browser column;
its attachment/send ownership remains independent of Conversation Sidecards.

Source: [workspace](../app/macos/Sources/Host/Shell/NativeWorkspaceView.swift),
[scene state](../app/macos/Sources/Host/MokuScene/NativeMokuSceneState.swift),
[Dock](../app/macos/Sources/Host/MokuScene/NativeMokuDock.swift).

## Geometry and surfaces

The Dock uses one persistent character/eyes owner and one glass shell. The
168×44pt resident capsule, expanded editor, Agent directory suggestions and
actions share production layout. Below 260pt available width, the editor gets the top
row and the identity, attachment and action seats share the bottom row without
replacing the NSTextView. The editor remains
scrollable and the shell stays within the viewport. Closing the bottom Overview
input fades the draft as the capsule starts to fold. The native editor stays
mounted for the 420ms return and keeps its selection for reopening.
Returning to Overview hides the Agent composer as soon as the reading panel
blocks input. The eyes flip to the Harness logo on entry and the logo flips
back to the eyes on return. Both turns use the 420ms reading opening curve.
Reduce Motion settles either direction immediately.
The shell contracts around the bottom center of its reading column with the Harness logo upright.
Agent panel travel overlaps the fold. The turn runs in the stationary compact
shell. Once the eyes settle, the bar glides horizontally at the reading height until
centered in the workspace, then rises vertically to its Overview seat.
A centered reader only needs the lift. A Super Thread with an execution
selected waits for the eyes to settle before starting panel travel.
The editor reveals its input ink at its settled position during expansion.
See the [Dock contract](../app/macos/Sources/Host/MokuScene/README.md#dock-and-composer).

Native horizontal travel retains the current position on retargeting and moves
directly to the committed destination column. A route owns column markers;
outgoing markers cannot overwrite incoming geometry. Resize, dragging and
inactivity settle the admitted destination. Selecting a different run in the
same admitted Agent reader keeps the pinned shell expanded and the settled
Harness mark in place. The replacement editor uses the selected run's draft
and admission state. If the selection changes the owning column, the expanded
shell travels directly there. See the
[history navigation replay](../tools/e2e/README.md#agent-history-composer).

Submission orbit begins on captured
input, but grants neither Stop authority nor navigation before confirmed
execution admission. Receipt uncertainty preserves draft/recovery state.

The compact Talk viewport supports selection, scrolling and execution links. Its one-minute lease begins on presentation. Chief’s conversation keeps each successful Talk message after the viewport closes.

Source: [Dock](../app/macos/Sources/Host/MokuScene/NativeMokuDock.swift),
[capsule](../app/macos/Sources/Host/MokuScene/NativeMokuCapsule.swift),
[Talk](../app/macos/Sources/Host/MokuScene/NativeMokuTalk.swift),
[horizontal travel](../app/macos/Sources/Host/MokuScene/NativeMokuHorizontalTravel.swift).

## Send identity and ownership

A persistent Composer keeps the submitted payload and the editable next draft
under the same scope before dispatch. A receipt resolves the captured send ID.
The initial command and draft handoff share a timestamped Runtime command ID
before dispatch. Historical phases append their phase suffix to the captured ID. Check previous
receipt follows that identity while the next draft stays editable. A confirmed
final command consumes the handoff. A definite rejection restores the original.
The settled draft retains the receipt ID until acknowledgement completes.
Checking a receipt cannot create a fork or deliver a follow-up. An existing
fork with unsent input requires an explicit decision to restore or keep the draft.
With no retained receipt, local review can restore the original above the next
draft or keep just the next draft.

For a manual send targeting the current running execution, the sending window
captures a normal user row before its first suspension. This applies to the
Agent composer, a Super Thread’s selected Agent run and a message to a running Chief. The HTTP executor carries
the draft's command identity to the Harness as a reader occurrence ID. The
window keys captured rows by Thread, execution and occurrence. Until the
execution ends it keeps the submitted text, attachment names and capture time
in that row. The Harness transcript determines its recorded position. Repeated
text with distinct command IDs keeps separate rows. A receipt for a successor,
a rejection or an uncertain outcome withdraws the local copy. The composer owns
recovery, and any retained Harness occurrence remains readable under the
normal live-execution policy. Native admission, execution status and model
output continue to come from Runtime.

Latest sends follow up on their original Thread. Exact historical continuation
forks at a verified native execution checkpoint before following up on the
accepted branch. Runtime's `expectedExecutionId` rejects a changed target before
reservation/dispatch. Only a proven pre-admission change can enter the historical
fork path once; uncertain outcomes query their original durable receipt.

Codex removes only a positively unadmitted input identity from the captured
execution; generic transport failures retain it. OpenCode keeps private submitted
message/session/execution associations until a prompt receipt or matching native
inbox/history fact produces one canonical message. Late evidence cannot borrow a
successor's current execution identity. Persistence precedes inbox deletion.
Full details live with the [Codex](../internal/plugins/harness/codex/README.md) and
[OpenCode](../internal/plugins/harness/opencode/README.md) adapters.

Attachments retain independent Thread, saved-draft, command-receipt, live-process
and active-writer owners. A visual chip in an unsent draft is not transcript
ownership. Native staging and collection use shared profile lifetime and atomic
handoff rules; see [attachment storage](../internal/services/attachments/README.md).
