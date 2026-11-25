# Chief presentation

[NativeMokuWorkspacePresentation](NativeMokuWorkspacePresentation.swift) derives the current Moku execution's display from public transcript operations. [NativeMokuSceneState](NativeMokuSceneState.swift) owns transient presentation and dismissal. The [Go coordinator](../../../../../internal/services/moku/README.md) owns task admission and tool results.

The composer uses the Chief name in
both interface languages, including their Accessibility labels.

Question choices use the full visible rounded rectangle as their button hit
shape, including padding and the empty space beside the answer text.

Settings uses the SwiftUI [reveal overlay](../Settings/NativeSettingsTransition.swift)
inside the persistent scene. Scene state retains Settings through return and
reports its transition lifetime; the overlay owns animation completion and
settling, without restoring the retired AppKit scene host.
The Settings content suppresses inherited animation only for changes to the
expanded state, so its final layout remains stable during the shell morph while
subsequent child-owned animations retain their own transactions.
A geometry group outside that transaction resolves the shell's animated page
placement first. Closing therefore carries the fixed-size page with the shell
instead of immediately centering its Map, title and form in the collapsed Dock's
width. Compositing alone does not provide this layout boundary.

Chief communicates through the Dock. Historical tool records stay in the audit. Current recognized operations drive the Bar. Talk links open ordinary Agent executions or the associated Super Thread. The current Chief Thread and retained coordinator sessions are unavailable as workspace readers.

## Dock and composer

### State and transition map

The [workspace](../Shell/NativeWorkspaceView.swift) supplies the route, draft,
execution and intervention. The [scene](NativeMokuScene.swift) owns
route visibility. The [Dock](NativeMokuDock.swift) measures the shell and
places its persistent seats. The following map lists the actual presentation
owners and their verification entries. Each replay exercises a subset.

| Entry or change | Visible property and ownership | Verification entry |
| --- | --- | --- |
| First-run handoff, empty Landing, first or last eligible card | Onboarding prepares input under the contracting cover. Landing scales the shell and eye seat together and moves to the bottom on the first card. | [First-run and first-card workspace](../../../../../demos/moku-panel-transition/README.md#joint-workspace-replay) |
| Overview capsule, Compose command, Escape, outside click, send and rejection | The bottom-center shell folds on its geometry curve. Editor ink follows expansion. Focus, selection and cancellation belong to the native input. | [Overview window](../../../../../demos/moku-panel-transition/README.md#overview-dock-replay) · [Pending sends](../../../../../demos/moku-panel-transition/README.md#pending-send-replay) |
| Agent card, history, continuation, Super Thread related execution, Browser annotation, Git, unselected Report | Reader travel, identity flip and input admission have separate owners. Drag/resize fits the current column directly. Annotation uses the cancel seat. Git follows ordinary Chief routing. Unselected Report suppresses input. | [Reader and column visits](../../../../../demos/moku-panel-transition/README.md#agent-entrance-replay) · [Report workspace](../../../../../demos/moku-panel-transition/README.md#host-receipt-replay) |
| Idle, unread/read reply, active execution, tool/reasoning, permission, completion, failure and interruption | The character controller retargets expression, color, blink and orbit. Consecutive tool updates keep the orbit clock. Input suppresses outside ink. | [Orbit and projected tools](../../../../../demos/moku-panel-transition/remaining/README.md) |
| Compact pointer enter/leave, keyboard and accessibility focus | Hover shadow and Stop square ease locally. Focus can reveal Stop independently. Its target follows the live seat. | [Overview and system input](../../../../../demos/moku-panel-transition/README.md#overview-dock-replay) |
| Editing, whitespace, IME, file import, submit readiness, offline and receipt recovery | The trailing glyphs and enabled Send opacity change in place. Control ownership switches on the input event. Text, caret, marked range and selection update immediately. Chips, suggestions and recovery rows take their measured space. The selected directory row changes tint. | [Input and action replay](../../../../../demos/moku-panel-transition/README.md#chief-input-replay) · [Pending sends](../../../../../demos/moku-panel-transition/README.md#pending-send-replay) |
| Talk, replacement, expiry and Compose over a notice | The shell fits the message. Talk ink fades while native text layout and scrolling update at their reading width. Opening input consumes a presented notice. | [Overview window](../../../../../demos/moku-panel-transition/README.md#overview-dock-replay) |
| Dispatching, started, failed and superseding operation | The status seat fades through clear. The operation owns its deadline, configuration, Harness mark and 48-point trailing reservation. | [Control ink recording](../../../../../demos/moku-panel-transition/README.md#control-ink-recording) |
| Settings command, close, reopen, short viewport | Shell and face travel to the page header, glass yields to the system background and page ink fades. Settings owns the save gate. | [Settings](../Settings/README.md) |
| Permission or questionnaire, step, choice, other answer, submit | The panel fades at its own seat. Selection tint, borders, pressed and enabled states use local feedback. Answer text updates at native input speed. | [Mounted intervention controls](../../../../../demos/moku-panel-transition/remaining/README.md) |
| Collection, covered/absent route, return during withdrawal | Collection owns its page fade. The scene retains the native Dock through route opacity retirement and revokes interaction at withdrawal. A return redirects that opacity. | [Collection](../Overview/README.md) · [Route reversal](../../../../../demos/moku-panel-transition/remaining/README.md) |
| Reduce Motion, Reduce Transparency, hidden/inactive window | Reduced motion settles local ink, shell layout and Settings directly. Reduced transparency selects the opaque capsule. Hidden/inactive windows suspend character and travel work. | [Reduced-motion routes](../../../../../demos/moku-panel-transition/remaining/README.md) |

The resident Dock editor plays Apple keyboard clicks for printable keys and the
delete sound for Backspace and forward Delete. Each delivered key-down,
including auto-repeat, can request one sound. IME updates, pastes, draft
restoration and shortcut handling do not independently request sound.

On Apple Silicon macOS 26 or later, [the player](NativeMokuTypingSound.swift)
decodes the installed iOSSupport UIKitCore click and delete CAFs. The two
accepted SHA-256 digests match macOS 26.5.1 (25F80) and the iOS 17.2 and 26.5
simulators. A missing, changed or unreadable file silences its key category.
Chief ships no audio from iOSSupport.

A serial audio queue schedules the verified PCM buffers in key order on one
AVAudioPlayerNode. Each clip has a 4 ms silent tail so keys delivered together
still have distinct attacks. The engine pauses after 500 ms of inactivity
following playback. At each key the player reads the macOS interface-sound
switch and alert volume and selects the current system sound-effects device.
Audio setup and playback run off the input thread.

Dock composer placeholders stay on one line and truncate at the tail.
The native draft editor remains multiline.
The composer layout reserves attachment/action seats and the resident eye seat
(the actual Harness logo in Agent detail) before giving
the remaining width to the editor; long placeholder text cannot displace Stop.
Dispatch status remains a single line with tail truncation and retains the
Dock's separate trailing control inset. Its configuration adapts within that
reserved content seat as described below. During a phase change the outgoing
status fades through clear before the next label appears in the same seat.

Moku’s Dock (idle, landing, composer, conversation, Talk and dispatch) and its interaction
panel use a dark SwiftUI environment.
Settings inherits the Dock’s dark environment. Onboarding follows the system. Settings uses the
opaque native window background, including with Reduce Transparency. The
illustrations have their own [Liquid Glass panels](../Settings/README.md).
The resident eyes travel into the reserved header seat during expansion and
follow that seat when the Settings shell scrolls in a short viewport.

The collapsed Overview Dock is the original 168×44-point eye capsule. Its warm
capsule material and the conversation’s Regular glass share one persistent native glass node.
The character's state colors, expressions, blink timing and Settings/onboarding
handoff and target-gaze animations use the original vector renderer. No Harness
sphere artwork or palette is loaded. Agent detail retains its actual Harness
logo; Overview input reserves the eye seat. The Stop control remains
at the trailing edge with its existing cancellation and accessibility semantics.

The shared input row places the attachment plus immediately to the right of
the identity seat. Below 260pt the editor takes the upper row and the plus
stays beside the identity on the lower row. A primary click or accessibility press opens
the macOS chooser directly. The default Chief composer starts on the current
user's Desktop each time, including after navigating elsewhere in the previous
panel. Agent and related-execution composers pass their thread's explicit working
directory to the chooser. A single confirmation can select multiple files and
folders. Files enter attachment staging. Each selected folder adds one explicit
directory reference by path, including empty folders. The draft counts the two
kinds independently (20 files and 50 distinct directories) and rejects an
over-count selection before adding any of its items. For host-enabled drafts, the contextual
menu on the same button offers host files and host directory references.
The composer remains dark in both macOS appearances. A native chooser keeps
its Escape and Cancel behavior. Cancelling adds no chips and leaves the draft
available. The editor treats `@` as ordinary text. The send route appends
saved catalog directory chips to the message as plain paths. Explicit directory
selections from either chooser retain their structured form across draft restoration. An earlier run with no generated title uses its stored instruction, including literal directory mentions. Receipt lookup uses
the saved command ID. Chief's delegation tools take text prompts. When a
delegated Agent needs a file, its prompt can refer to the file by its managed path.

Agent entry sequences the compact Dock's travel, the eyes-to-Harness flip and
composer expansion. The reading entrance's actual arrival/layout admission
releases the flip; its removed animation completion releases input and the
existing focus path. A composer-generation fence and a view-local transition
generation reject replaced or detached completions without an elapsed-time task.
The small downward reading-seat shift uses the existing native travel host,
with a 420ms ease-in/ease-out curve rather than SwiftUI layout animation. Reader
preparation cannot stall submitted travel frames. Both axes share sampled
replacement geometry, completion fencing and moving-control hit protection;
shell sizing and composer expansion remain owned by SwiftUI.
Rapid replacement retains the current mark during travel. The same Harness
reuses a settled or in-flight flip. Reopening during a return waits for the
Harness mark to settle before the editor expands, even with the same draft.
Reduce Motion, an inactive scene or a hidden window settles the mark immediately,
while reading/content readiness still gates input. See the
[entrance contract](../../../../../design/reading.md).

[NativeMokuDock](NativeMokuDock.swift) uses one native glass capsule with a bottom-center anchor. Idle size is 168×44 points; expanded width is bounded to 560 points and the available viewport. [NativeMokuComposer](NativeMokuComposer.swift) lays out the Dock input row. Collapsing and reopening the Dock input restores the caret/selection saved while it was open. On Overview, the capsule and Compose command explicitly request editor focus. Landing can show the editor before the user focuses it. The native editor snapshots selection before becoming unavailable during collapse and restores it on a rapid reopen; the scene retains the selection and its exact UTF-16 text for a later editor remount. Unchanged multiline/Unicode text retains the native range. Changed text reopens at its end rather than reusing stale offsets. Selection restoration neither requests focus nor changes draft persistence; draft context changes clear the scene snapshot, and marked text remains owned by the input method. A normal click can acquire the native editor without being undone by a delayed SwiftUI focus report.

The Dock clears submitted text, directory references and ready attachment
chips in the mounted editor as soon as the draft captures the send. The
retiring Dock capsule also clears its sealed ink snapshot before collapse.
The same frame sizes the idle and running Chief row. If the runtime reports
that Chief has started while the glass is folding, the fold continues to its
compact size. A visible Talk or dispatch notice expands the row to fit its content.
The pinned Thread editor remains editable and keeps its native first responder
while the send awaits confirmation. A reopened ordinary Dock can also edit its
next draft. The draft blocks further submissions until the pending send settles.
Browser annotation retains its own read-only submission interval.
Admission still owns persistence consumption and staged-file release. Failure
reveals the retained draft, preserving any new text after the failed message;
no automatic retry occurs. **Check previous receipt** checks the saved command
ID. A missing receipt permits local review after checking the conversation.
Local recovery offers **Restore to draft** or **Keep next draft**. Both choices
are local and preserve the editable successor. Ready image chips use system Quick Look with the
shared strip's local managed-file URLs and independent preview/remove actions.
No current e2e evidence is supplied for Quick Look focus or pointer behavior.

The identity seat retains the last open editor position while the composer
retires. Each time the editor opens, it measures the reserved eye seat relative to its own bottom edge. The eyes stay level with the attachment button when the draft wraps or a send error appears and clears. In Agent input, directory completion stays above the same bottom-anchored native editor.
Its measured height changes the shell without replacing the editor or its
selection owner through entry, exit and rapid reversal. The pending-send replay
selects the same directory in two consecutive drafts using Return.

From the empty Landing through the first Thread card and ordinary Overview
folds, the eyes occupy one fixed-size seat inside the shell. Moving or scaling
the shell carries that seat with it.

The Overview editor reserves one 32-point trailing action seat. A submittable
draft shows Send, including ready attachments or directory references alone.
Otherwise a running Chief shows Stop and an idle Chief shows disabled Send.
Removing the last directory from an otherwise empty idle draft removes the
43-point strip above the editor. The bottom of the Overview capsule stays
anchored while the top moves. Send dims in place beside the editor. Attachment
and recovery rows contribute their fitted height directly to the Dock;
the action fade changes only glyph opacity.
Return in the editor only attempts submission. The ordinary Dock carries Stop
from 22 points inside the compact edge to the center of the editor’s action seat,
29 points inside the expanded edge. Hover or focus reveals it when folded. The editor uses its final
width throughout the 420ms motion. Its ink fades in during the last tenth
of expansion and fades out over the same part of the return. Closing ends
editing immediately. See the [Overview Dock replay](../../../../../demos/moku-panel-transition/README.md#overview-dock-replay).

The foreground workspace's Compose command (⌘⇧B) requests focus when it
admits an opening. The mounted editor can receive keystrokes during the ink
transition. Once the focused editor is visible, its insertion mark appears with
the input ink. The Overview capsule button also requests editor focus on activation. Closing the
input or replacing its draft invalidates an unfinished command request. An
open pinned editor uses Compose to request focus again. See the
[Chief shortcut replay](../../../../../tools/e2e/README.md#chief-compose-shortcut).

When an ordinary keyboard opening leaves the key window itself as responder
until the editor attaches, printable typing waits for that request's native
editor. The handoff sends those events in order to the same key window.
Pointer input, other key commands, loss of the key window and route retirement
end the handoff.

`inputLeaving` keeps the ordinary closing editor mounted for 420ms to retain
its selection. Returning from an Agent conversation to Overview closes the reading
panel's input gate while the workspace still owns the outgoing draft. The
composer and its directory suggestions hide at that point. The accepted close starts a 420ms ease-out fold in the reading column.
The Harness mark stays upright until the presented glass is compact and column travel
has settled. The stationary bar then flips to the eyes over 420ms. Agent panel
travel overlaps the fold. The Dock keeps its reading position through the
turn even if the Agent route has already closed. A Report returning to its card waits for its mounted
mark to finish or disappear before starting panel travel. A Report whose card has
left the current filter can dismiss while the Dock folds. Route release removes the row without a SwiftUI exit fade. Reopening
restores the active draft and its selection. Talk has independent presentation
and can become readable when input closes. The shell and the single identity
seat move in the same transaction. The editor overlay reserves its final width
and height before the editor mounts. In the wide layout, input ink appears to
the right of the Harness logo after the logo clears the final text seat. Below
260pt of capsule width, text and attachments occupy the row above the identity
and actions. The editor fades in during the last tenth of shell expansion.
The retiring shell keeps its bottom center in the reading column. With no
sidecard expanded, it folds and lifts on the workspace midline. The interpolated frame sizes the glass. The Dock retains the occupied column
through the fold and turn even when a Super Thread withdraws its execution marker. The compact Dock returns horizontally at
the reading height and lifts at the workspace center. If the same Agent reader
reopens during its fold, its input expands again under the selected execution.
An already compact, stationary bar can start its return flip immediately. Reduce Motion settles the
returning mark, fold and travel immediately. Resize preserves the native editor and the
shell fits the viewport.
The [Agent entrance replay](../../../../../demos/moku-panel-transition/README.md#agent-entrance-replay)
checks the settled text origin, focus and return. The
[Report replay](../../../../../demos/moku-panel-transition/README.md#collapse-replay)
covers the wide and narrow logo clearance and execution-list input gate.

An initialized workspace with no globally eligible, unarchived conversation cards
opens the same Dock at the visual center: 680×76 points, 16-point text and at least
24-point horizontal viewport margins. Moku and its archived history do not count
as ordinary cards. Membership is measured before tags and report coverage,
including documents exposed only inside a directory. Loading is not an empty
workspace. Archiving/deleting the last eligible conversation restores landing;
filtering to no results does not. Landing eligibility does not depend on the
separate [first-run onboarding](../Onboarding/README.md) completion marker.

Landing opens input once on entry. Submitting uses the ordinary sealed-draft
collapse; failure reopens the preserved draft. Escape keeps landing input open;
IME and native transient controls retain their cancellation
priority. Input reopening and Stop use the same paths as the bottom Dock.
Outside clicks keep landing input open, including clicks in another window or
app, without consuming the click or losing the draft. Bottom-Dock input still
collapses on outside clicks. Returning from a
covering route or remounting cannot reopen input over a resident or message.
Hydrating a running Moku or waiting message presents that state immediately.
Focus loss, native menus, attachment sheets, modal panels and visible child
windows also retain landing input. Cross-app observers belong only to presented
Talk notifications and retire when the notification hides or the Dock unmounts.

The same persistent capsule and character host own running, thinking, Talk and
dispatch. There is no separate landing notice. A manually opened editor defers
notifications until it closes, without losing its draft. The centered compact
resident eyes and running orbit scale together by 76/58. Expanded landing rows
retain the 680-point composer width and 76-point minimum height.

A durable first-task shell can precede native admission, so it remains behind
landing while `create_thread` is pending. A successful public result for an
eligible Thread returns the same Dock to its bottom seat. Failure without an
admitted conversation stays centered; an independently admitted conversation
also ends landing. Existing workspaces hydrate at the bottom. The same surface
owns the transition.


Agent directory completion opens above the editor within the same capsule. The editor stays seated at the bottom and scrolling suggestions are clipped to their own area. On macOS, native paste/drop imports files. The Dock has no Moku context menu on right-click or Control-click. An accepted send consumes only its submitted draft revision; failure retains it.

[NativeMokuSubmission](../Shell/NativeMokuSubmission.swift) retains one logical
Moku submission through admission, receipt recovery and persisted draft
consumption. An uncertain retry queries that same receipt;
changed input or a different Report/directory cannot consume the original
submission. Dock and Report capture the source when sending. A
successful response retains its receipt until the settled draft and its cleanup
ID are durable. An owner that reopens the draft can finish the matching
acknowledgement even if the original window closed.

Outside Overview, an empty or whitespace-only draft without attachments/directories mounts no Send
button or circular background, including in accessibility. Its empty layout seat
keeps the editor width stable. Attachment/directory-only input still exposes Send;
importing, submission and unavailable states retain their ordinary admission rules.
For an active Thread execution, that same seat shows Stop when the draft has no
sendable content and Send when it does. Other composer routes retain their existing
Stop and Send layout.
Moku editors always use the existing shortened, rounded 2.6-point
white core with a warm-yellow upper halo, cool-blue lower halo and blurred
gradient fringe, including on a light system.
The empty placeholder starts three points after the insertion origin.
Composer padding lives inside the native viewport so these halos are not cut at
the text line edges. A 2.4-second breathing cycle replaces native on/off
blinking; white ink uses 20–100% opacity, while its halos fade fully.
Same-line movement remains 120ms and interruptible. IME composition uses the
native caret; line changes stay immediate. Selection and focus/visibility loss
remove the layer and animations.

The empty message editor reads `Type a message…` (Chinese `输入消息…`) across
Overview, landing, Git, Agent details and Report execution details.
The placeholder also supplies the editor's accessibility label. Editor help
describes whether the message goes to Moku or directly to the current Thread.
Selected directories are shown as chips. Browser annotation mode supplies its
own editor instructions based on whether a page region is selected.

On macOS, clicking the collapsed Moku row opens input; when a message is visible, only the eyes are the input target so prose remains selectable and controls retain their actions. The eyes use the existing composer focus and draft-restoration path.

### Chief Bar conversation

In Overview and on Landing, a secondary click (including Control-click) on Chief Bar opens the conversation. Its regular Liquid Glass uses the Bar’s dark appearance, with an opaque Reduce Transparency fallback. The message list starts at the top of the capsule and the native composer stays at the bottom. Entry over the eyes also works with the compact editor already open. Editable text and overflowing native viewports keep their scroll input.

The panel fits the current page and its composer. Its maximum height is the smallest of 648 points, 96% of the visible workspace height and the space inside the Dock’s outer margins. In an 860 × 600-point Overview window, those margins reserve 24 points above the panel and 30 below, leaving 546 points for a long conversation. The composer takes its measured height first. The message list scrolls in the remaining space as a draft wraps or attachments are added. When a smaller viewport would hide the latest reply, a reader at the end stays with it. Scrolling back to earlier messages keeps that reading position through a height change.

An active window prepares the plain Overview editor at its destination width while the ordinary Bar is idle. The folded editor stays disabled, unfocused and hidden from accessibility. Drafts with attachments or directory chips mount on demand.

Each visit subscribes to the newest page when the secondary click opens the Bar. The timeline lays out every message on the loaded page at its reading width. The measured document height fits the panel up to its cap, and the inset below the final bubble anchors the end of even a reply taller than the window. The reader stays mounted through subsequent size changes until the visit ends.

The resident eyes stay on the bottom row as they move between the centered capsule and the editor seat. On dismissal to the centered capsule, message and editor ink retire together before the eyes cross the input seat. Expression changes and blinks retain their own clock. The [opening replay and benchmark](../../../../../demos/moku-landing/README.md#chief-bar-opening) measure the reading position, visible response, time to the latest line and pauses during expansion.

Blue user messages appear on the right and neutral Chief Talk messages on the left. Message text is 15 points. Within an exchange, adjacent balloons have 7 points between their bounds for one speaker and 14 points when the speaker changes. Only the last balloon in a run has a tail. A centered local day and time heads each page, each calendar day and each exchange after a gap of at least 15 minutes. A new date heading within a page has 20 points of space above it. The message list scrolls vertically. Each balloon exposes its date and time to accessibility and on hover. The visual reference is [Messages on iOS 27](https://support.apple.com/guide/iphone/send-and-reply-to-messages-iph82fb73ba3/27/ios/27).

On the newest page, a live running Chief execution shows a small incoming balloon with three gently rising dots below the messages. Reduce Motion keeps the dots still. The indicator leaves the layout when the execution stops running or the Runtime becomes unavailable. It belongs to the scroll document and uses the same end-following and reading-position rules as the message rows. It has its own accessibility label and no message ID, date or history entry.

Earlier and newer controls are at the top and bottom of the list. The [Runtime scope](../../../../../internal/core/runtime/README.md#chief-conversation) owns message identity, order and recovery. A mounted page receives live revisions and uses the profile’s existing reading cache when offline. The Dock keeps its draft, attachment picker, IME, Return, Send, Stop and receipt handling. Sending from the panel keeps it open. The latest page shows the window’s captured Chief input while admission is pending, including when opened from the compact Bar. Its command-derived row ID lets the persisted message take its place in either receipt/content order. Earlier pages keep their own position and contents. A rejected or uncertain send removes provisional ink and leaves recovery to the composer. Older services that return pages without command row identity continue to supply the visible rows themselves. Escape or an outside click dismisses it and preserves the draft. Landing returns to its input. Interventions, readers and Settings retain their existing priority.

Dispatch status is informational; clicking it does not open a detail sheet.

The compact Bar samples the five stages in [MokuRunningStory](../Moku/MokuRunningStory.swift)
on its visible display clock. The three 5-point dots pulse in turn for 2,800ms
at 8-point spacing beneath the glass. Over 616ms they gather on the contour.
One eased lap takes 3,000ms, with 3 points of clearance from the glass.
The dots return to their row over 644ms. During the final 616ms the eyes
briefly squint and reopen, then the 7,676ms cycle repeats. A fresh direct
Thread send starts at the lap. The eyes track the leading dot on the actual
capsule contour during travel.
[NativeMokuRunningGeometry](NativeMokuRunningGeometry.swift) retains the path
for the admitted capsule size and radius. Entry and retirement apply a 550ms
fade to the sampled ink. Reversing a fade or replacing a visible run preserves
the current phase. Retiring dots keep their last contour until fully hidden.
Pausing freezes both the eyes and the dots.

[NativeMokuCharacterMotion](NativeMokuCharacterMotion.swift) owns the logical clock for the persistent eye and decoration seats. Ordinary expression changes take 420ms and running/thinking handoffs take 550ms. Interrupted transitions inherit the sampled geometry and velocity. Same-segment text updates keep their current role. Inactive, hidden and occluded scenes pause the clock. The Dock and composer use the same [native blink layers](NativeMokuCapsuleBlink.swift). Each eye keeps its centre, tilt and rounded outline as its height follows the blink.

Static character targets are cached until their input changes. Core Animation plays the 320ms blink on the original 4.2-second wall-clock phase. Its path keyframes trace the original sine down to 9% height and back to open; corner radii use the original eye shape at each height. The display link stays asleep throughout an idle blink. The
[first-run handoff](../Onboarding/README.md) schedules a single blink on the
mounted face and sets its next idle blink one full period later. App activation,
scene state and the face's AppKit visibility govern that first blink.
Losing eligibility clears it immediately, including
while the display link sleeps. The next idle blink keeps its scheduled time.
Hidden or inactive faces remove the blink animation. A visible face rejoins its scheduled phase. A compact unread reply or intervention can submit the outline, position and tilt to those same layers between blinks. The logical clock samples the submitted leg when the destination changes. Overlapping blinks, coordinated shell or decoration movement, and changes of direction that require distinct component velocities use the display link through the final paint. Resuming starts a fresh wall-time interval. The native replay compares rendered phases, interrupted playback and the original responder in a window. [Chief Bar replay](../../../../../demos/moku-panel-transition/remaining/README.md)

Talk and live transcript prose use semibold, centered layout.
Symmetric 64-point insets reserve the eye seat without shifting text
away from the capsule center.

Overview derives its persistent bottom reservation from the same idle capsule
geometry. Expanding the composer or notification does not change that
reservation or trigger a card repack; those surfaces retain their existing
interaction/overlay ownership.

## Thinking feedback

The compact Chief Bar uses one three-dot running animation across reasoning,
ordinary tool calls and assistant text in the same execution. A new call or
return to reasoning keeps the current animation clock. The Dock reads the live
execution state and reserves operation-specific presentation for the active
Overview operation. Harness activity and tool audit records keep their original
names, call IDs and results. Completion, failure,
interruption, waiting for input and runtime disconnect retire loading through
the existing execution and surface ownership state.

The public Harness foreground still supplies
[MokuReasoningContent](../Moku/MokuReasoningContent.swift), identified by Thread,
Harness, execution and foreground sequence with its UTF-16 source offset.
Assistant/tool foreground changes, terminal states and disconnects retire that
live projection. The Arc model, painter and layout exist; the Dock does not
admit or paint their text. Ordinary Agent Thread readers own
their trace rendering.

## Talk and dispatch

Opening Chief input marks the Dock’s reply as read.

[NativeMokuTalk](NativeMokuTalk.swift) shows the latest valid `talk` or `create_thread` operation. Talk is selectable text. Each message opens at the top and grows to a 111-point text viewport (about six lines). Scroll down to read overflow, including execution links. The compact audit reader admits saved successful Talk text up to 1,024 code points for Alpha compatibility. The [submission limits](../../../../../internal/services/moku/README.md#talk) apply at the coordinator, and conversation history renders saved text in full.

The trailing control seat stays reserved for the whole message so retiring Stop does not shift centered text or change its wrapping. Talk does not edit the draft or grab focus. Clicking outside the capsule dismisses the presented notification without consuming the click, including clicks in another window or app. Clicks and scrolling inside retain it. Only windows accepting mouse input observe outside-window presses. The cross-app mouse observer is removed when the notification is hidden or the Dock unmounts. Dismissed/presented operation identity survives refresh and remount within its scene. A notification covered before presentation waits until it can actually be shown.

Talk uses symmetric 64-point insets around its centered selectable text viewport,
reserving the persistent eye/control seats without shifting prose. The
[mounted link replay](../../../../../demos/moku-landing/README.md#talk-execution-links)
checks that a short multiline Chinese notice and its final link fit, and that
scrolling a longer saved notice reveals a clickable link below the fold.

The
capsule height uses the same width; changing the scrollbar preference updates
both without replacing the scroll view. The production selectable text uses
the native clip/scroller boundary for mixed Unicode and overflowing content.
The native viewport also stays inside its promised host bounds: the prose width
is a maximum inside a flexible, leading-aligned document, so persistent scrollers
cannot expand it past the control row.


The compact Talk shell adds 9 points above and below its measured content.
Inline links include their own clearance within the text line. Short messages
are vertically centered at the row's minimum height (58 points in Overview,
76 on Landing).
The Dock's Stop
square is revealed by pointer hover, keyboard focus or VoiceOver focus. A scoped 120ms SwiftUI ease-in/out animation fades the square.
The surrounding Button owns cancellation and stays in the accessibility tree, while pointer
hit testing follows the visual state so an invisible square cannot be clicked.
Running messages reserve a 48-point trailing inset even before hover/focus,
keeping text and dispatch content clear of the 30-point Stop target and its
7-point edge inset. Revealing the square therefore does not rewrap the message.
See the [mounted Stop replay](../../../../../demos/moku-panel-transition/README.md#overview-dock-replay).
This is cancellation (`moku:cancel`), with no pause/resume action. Composer Stop
shares the Send seat in Overview and for an active Thread execution. Blink/cloud clock pauses are animation lifecycle state,
not message-bar controls.

Dispatch notifications (pending, started or failed) expire 10 seconds after their
first actual presentation; ordinary Talk notifications retain their 60-second
timeout. Both use a monotonic deadline retained by the scene. Refreshes and
in-place operation updates do not extend it; a replacement operation gets its
own full interval. The Dock's
deadline task is cancelled on replacement, dismissal or unmount and checks the
captured operation identity before expiry.

[NativeMokuDispatch](NativeMokuDispatch.swift) projects the same operation while pending and settled. Success requires `completedAt`, no error, `ok:true` and a nonempty `threadId`; it confirms dispatch, not task completion. The 400×58-point layout contracts for narrow viewports. Configuration comes from that call's arguments. The notification is informational and does not open a detail sheet.

The notification first fits the complete status and configuration on one line.
When their intrinsic width exceeds the available content seat, configuration
moves below status inside a 32-point row, without changing capsule dimensions,
eye placement or the 48-point trailing control reservation. Model and thinking
use 11-point text with no fixed configuration width. The model keeps its exact
identifier across Codex, Claude, Pi and OpenCode; there are no display aliases
or provider-prefix stripping. Thinking retains the requested effort or mode
(`on`, `off`, `fixed`), with no inferred defaults. Only an overlong model on the
second line truncates in the middle; thinking has higher layout priority, and
extreme widths can still truncate either field. Hover help and accessibility
retain the complete configuration. Provider remains separate from model identity
in the stored operation; the notification has no clickable detail sheet.

The selected Harness is the single key in `arguments.target`, with its native
fields nested under that key. Empty, ambiguous or non-object selections do not
produce a dispatch projection. Empty native option objects remain visible so
rejected requests can still show their outcome. Catalog audit previews preserve that identity
and only `model`, `provider`, `thinking.mode` and `thinking.effort`, with each
display string capped at 256 code points; oversized target keys are omitted
instead of changing their identity. Other native options are not forwarded to
the catalog. The full stored operation retains the caller's original request.

Switching the coordinating Harness retains the previous conversation as a read-only Chief history session. The conversation shows successful Talk messages across these sessions until an explicit history reset.

### Talk execution links

The compact notification and incoming Chief conversation bubbles render the same selectable text. Each execution link occupies an inline glass capsule with its Harness logo and an arrow. It displays the supplied label or the public task title for a bare URL. A missing title or Harness uses the localized Execution label or terminal icon. Surrounding text, newlines and malformed links stay literal. Only links accepted by `ApplicationExecutionLink` invoke the workspace’s typed navigation action. Opening a link retires the notification or folds the conversation while preserving its draft. After notification expiry the stored message remains available in the conversation.

The workspace locates the exact run in an ordinary Agent reader or its owning Super Thread. Closing either reader returns to Overview. See [window navigation](../WindowNavigation/README.md) and the [mounted Talk link replay](../../../../../demos/moku-landing/README.md#talk-execution-links).

## Settings expansion

Settings expands from the resident Dock's existing capsule, with a stable
viewport-bounded centered surface with a 780-point preferred width and a
900-point minimum preferred height that grows with its active form. Its full
panel uses the opaque adaptive Settings fill and a subtle border, without Liquid
Glass. The resident eyes move into the header's reserved leading seat and track
the Settings scroll offset.
The scene blurs and disables Overview, while the capsule and retained input
visit stay mounted. Closing uses the Settings draft gate and restores the
previous valid surface; pending interventions resume only after Settings exits.
Only loaded Overview admits Settings, including menu and semantic entry points.

## Reading-panel Dock

Browser annotation mode temporarily lends the resident composer to the selected
Browser card. The same native destination marker and travel host center it below that
card, fitting its column. Page focus remains with selection until an element or
region is chosen, then the text editor receives focus. A separate ephemeral text
draft describes that selection; normal Thread and Moku drafts remain retained.
Return/Send captures and submits the annotation through Browser's existing
attachment/send route. Escape, the accessible Cancel annotation control and the
Browser toolbar cancel only this mode. Switching/folding cards, page navigation,
covering or closing returns to the ordinary draft and send route. Annotation
input admits text without file or directory controls. Failed capture
keeps the description; failed sends keep the captured batch for the existing
retry/text-only controls. See the
[annotation input contract](../../../../../design/composer.md).

While the selected Sidecard owns the current running/waiting execution, the
resident input is centered below that panel and fits its width with the ordinary
24pt horizontal insets and 560pt cap. Its reading baseline stays fixed. The
Sidecard host publishes destination bounds through passive native layout markers;
the bridge converts across the reading panel's separate `NSHostingView` into
scene coordinates. Publications wait for layout and carry Thread identity, so a
retiring reader cannot position another Thread's input. The native marker stays
at the workspace origin and carries the target's local rectangle explicitly;
equal-width column switches therefore do not depend on a native frame-change
notification from a SwiftUI ancestor transform. The same editor, draft,
selection and input actions remain mounted.
Selecting Browser (or another non-owning activity) instead centers input
below the main reading panel and fits that panel's width, including when the
Thread's latest execution has finished. Input still sends to the same Thread;
opening an activity does not make that activity its target. Folding the selected
card, suppression, losing the selected card's eligibility or starting completion
promotion restores the workspace-centered input. A first execution in main with
no expanded activity does not move it. When the target column changes, the
Dock glides horizontally for 470ms, including on its return to the workspace
center. It uses the same ease-in/ease-out curve as the compact Dock's vertical
travel. The compositor moves directly from the current
presentation position to the target, without overshoot or a settling rebound.
On return to Overview, the native host holds the reading height through
horizontal arrival. Route release and that arrival both have to occur before
the compact Dock rises at the fixed workspace center. Reopening during
either leg retargets from the displayed position. Shell sizing retains the
Sidecard's 380ms curve. Divider dragging and window resizing settle without
travel. Stacked layouts share the
panels' full column width and keep the same bottom reading baseline. Composer
expansion retains its separate entrance timing.

The Scene keeps the complete Dock in one persistent native hosting tree. Its
native outer layer owns horizontal travel. The native host moves to the target
column in the same transaction that starts compositor travel. The source
correction holds through the first compositor sample. Its editor,
controls and glass travel together even while the main thread prepares content.
Reversal starts at the current presentation position. Completion is fenced to
the current native animation, placement revision and composer generation;
resizing settles immediately. Keyboard focus survives travel,
while coordinate-based pointer hits wait for arrival so they cannot activate a
control at its invisible destination.

Switching columns can also change input width. The editor adopts that width
once, inside its own geometry group, while the shell retains its existing size
and vertical animation. The eyes and Harness mark flip in a single shell-local seat.
The live glass, mark and editor share the shell's bottom-anchored SwiftUI
layout through Landing, Overview and reader transitions. A busy main thread
can delay shell layout. The complete Dock owns its
state and geometry within one hosting tree, including Settings height
preferences and input hit regions.
The hosting root stays fixed while observable content carries outer updates;
replacing the root can settle the shell before its content finishes moving.

Native compositor travel is distinct from full-workspace frame pacing, GPU
or energy measurements.

Primary reading entry lowers the collapsed Dock with its native 420ms
ease-in/ease-out curve. Its composer stays unmounted until the reading panel/title handoff
finishes and the main document is ready, then the folded Agent workspace
commits. That visit-scoped boundary admits the Sidecard reveal (380ms). If its
execution column owns the Dock, the compact Moku travels there first; the actual
horizontal animation's final completion then admits the
420ms Harness flip and subsequent 420ms input expansion.
The native geometry bridge fences completion to the current destination revision,
and the workspace retains the existing route-visit admission check. A folded,
ineligible or absent execution Sidecard releases the identity stage at layout commit without
a travel wait. Once input is admitted, later card choices move the retained editor
without folding it. Direct resizing settles without a delay.
Scene-level input admission also gates interaction restoration,
input controls and focus; navigation cannot bypass it by reconfiguring the draft.
Within an admitted Agent reader, TOC selection and Back replace the editor's
draft without folding the pinned shell or readmitting its settled Harness mark.
Input readiness still follows the selected document.
Automatic focus follows the current composer visit's ink reveal. The Dock
requests focus when the reveal reaches 10% opacity. Admitted click and Tab
focus remain available during opening. Cmd+Shift+B explicitly focuses a pinned Agent editor after TOC navigation,
without changing its draft, send generation or suppressed automatic-focus policy;
accepted Close suspends input hit testing/focus as the shell folds. The fitted Dock
bottom moves down by up to 16pt, keeping at least
12pt below it; Super Thread admits the expanded composer only for a selected
associated Thread; Git retains its normal input policy in that same lower seat.
Landing and Settings keep their existing positions. The bottom-anchored editor,
reasoning envelope and hit regions still use the fitted surface. See the
[reading choreography](../../../../../design/reading.md).

The same resident Dock remains mounted and interactive while an ordinary Agent
Thread, Report or Git detail is presented in a reading panel. `dockRouteVisible` combines Overview and
reading-panel eligibility without admitting Settings on a reading route.
The composer, Talk and pending interventions use that shared eligibility; other
application pages and covering routes still hide the Dock. Returning to Overview publishes eligibility in an order that retains native
input/hit-region ownership. Agent detail keeps its input expanded. Its leading
identity seat reveals the actual Harness plugin's native logo, which remains
visible while typing.
The host resolves the current target's `harnessID` on each render, including target
changes; unknown/empty IDs use a neutral terminal mark, never Moku's Harness.
Registered custom Harnesses supply their own mark through the same registry.
The passive logo occupies a 34×25pt seat only in Agent input and ignores pointer
and accessibility hit testing. Both directions of the horizontal-axis turn use the
420ms reading opening curve (cubic Bézier with control points (0.76, 0) and
(0.24, 1)). The turn is fastest as the mark passes edge-on. It retires the old mark
in its first half and reveals the new mark in its second half. Changing Harness
flips to the new mark; changing Threads within the same Harness keeps it steady.
Overview and Report/Git restore Moku's theme. Settings uses the resident eyes.
Both marks share one animated angle. Reopening during the fold retains the Harness mark. Reopening during the
turn reverses the angle, so only the side facing the viewer can draw. A hidden side uses an
identity transform to keep its coordinate space invertible. If a third Harness
is requested mid-turn, its artwork takes the hidden seat once the turn lands.
The current visit alone can admit the editor when its mark has settled.
The logo is separate from placeholder/draft text and never replaces the editor.
The window owns persisted drafts (text, directory mentions and attachments) per
Thread for ordinary current input and per exact Thread/execution for fixed
history/result input, separately from the Overview Chief draft. Agent and Report
readers share `NativeExecutionContinuation`: latest input follows up on its
original Thread, while historical input forks at the native checkpoint before
following up on the admitted branch. The source identity is captured before
the first suspension. Runtime chooses steer or a successor execution for a
latest follow-up. Stop uses the viewed current execution's cancellation identity.
Unavailable Threads and read-only Moku histories cannot send. Ordinary Thread
archive only changes list visibility and does not disable sends. Failed sends keep their draft and error;
late receipts consume only their original draft and cannot reopen another visit.
Retiring composer callbacks may refresh the capsule's retained text, directories
and attachment ink only while they still own its selected draft. A Thread title
or execution change keeps that Thread's unsent draft. See the
[draft and attachment contract](../../../../../design/composer.md)
for the distinction between restored input and cross-Thread routing defects.
A direct send to the current running execution publishes its captured user input
to that reader on the same main-actor turn. Agent and Report readers share the
[send identity contract](../../../../../design/composer.md#send-identity-and-ownership).
Sending from the latest finished result opens Conversation on local capture,
before the command or catalog returns. Its pending column places the pinned
composer beneath the card. The receipt identifies the accepted execution and
the catalog and index determine where its live reader belongs. Failure retires
the provisional opening. A later card choice or reading visit owns its selection.
Navigation resets retained editor ink, selection and completion ownership before
admitting the replacement draft. Returning to Overview or Git restores the existing Moku send route.
An unselected Super Thread keeps the resident Moku capsule compact and denies
input expansion. No Overview card send entrance is added.

Agent detail pins the composer open: Escape, outside clicks, the input toggle
and successful sends cannot fold it. The editor's Escape callback closes the
current detail through its existing reading motion, fenced to that route/target;
the Dock's native fallback uses the same callback after focus moves to its controls.
Reading/document/Sidecard Escape skips resident-input folding and retains its own
nested cancellation order. An ordinary click in the blank panel margin closes
that detail on the first completed press; clicking inside the reader, Sidecards,
capsule or directory candidates retains their normal interaction.

IME marked text, directory completion, native menus, sheets, popovers and explicit
control cancellation retain priority. Escape closes directory completion first;
in Agent detail an outside press also dismisses completion first without folding
the editor or closing the reader. Native transient/IME-owned presses are recorded
before delivery so mouse-up cannot close the reading panel after AppKit commits a
mark or removes a popup. The window-sharing indicator can stay visible while
the reader handles a blank-margin click or the composer handles Escape. Only
child windows that can take keyboard focus claim those actions.
Existing Moku interventions/covering routes keep their surface priority and release
the Agent editor afterward; its draft remains owned by the same Thread.
Execution Sidecards stay usable
beside the open composer and own no text/attachment input.

Overview, landing and Git retain their existing input and
cancellation policies. Closing detail or changing targets retains unsent text,
attachments and directories through the window-owned persisted Thread draft.
Sending still consumes only the accepted revision; failed sends retain the draft
and error, and late receipts cannot alter another target's presentation.
See the [composer routing contract](../../../../../design/composer.md).

Report execution details borrow that same Agent composer and native column
placement. Exact-execution drafts are shared with Agent history/result readers
for the same Thread/execution pair. The editor opens after its horizontal travel
settles. Returning to the list, folding, Browser selection or departure
restores Moku and retains the draft;
editor Escape follows Report's auxiliary Back. Only the viewed current active
execution exposes Stop; historical input cannot stop a newer execution. The shared sender uses the existing expected-execution admission fence. An
explicit pre-admission `EXECUTION_CHANGED` rejection takes the historical fork
path once; uncertain writes are never automatically resent. A failed follow-up
retains both the exact draft and its admitted fork for review across these readers. Successful exact sends open the accepted Agent execution
after catalog admission, fenced to the owning route/composer visit. Ordinary
current sends keep their existing visit-scoped execution reveal. TOC selection changes drafts without acquiring editor focus. Initial input,
explicit Browser annotation mode and Moku retain their existing autofocus. Pending focus requests wait for editor eligibility and are applied once, so an
unavailable first render cannot lose the request and later availability cannot
repeatedly steal the reader's focus. See the
[focus ownership contract](../../../../../design/composer.md). Execution completion lends input publication only to the current native reader
seat. The retained outgoing reader cannot overwrite or clear that target, and
canceling a handoff republishes the restored reader's target. The workspace
withdraws its input owner when it leaves, independently of either reader's
teardown. Each continuation phase retains its original source, input, destination and
command ID. During Send, a confirmed fork transfers its durable receipt to
the first follow-up in one journal transaction before dispatch. After a lost
response, Check previous receipt only reads the identified command. If the
fork exists and its input was never accepted, the composer keeps its protected
receipt until the user chooses Restore to draft or Keep next draft. Either
decision releases the barrier and lets the user continue in the created branch.
A confirmed final send consumes its own draft and leaves the successor intact.
The saved successor records the receipt until journal cleanup has completed,
including when the original owner closes. This policy is
shared by Report and Agent input; there is no force-resend button. See [Execution continuation](../../../../../design/reading.md)
for native constraints and evidence limits.

Direct Thread sends admit three-dot orbit feedback as soon as the Dock captures
the submission. Open input hides the orbit, including retiring dot ink; closing
input reveals applicable pending/running feedback without waiting for the
retained editor to unmount. The pinned editor keeps its own Send/Stop controls.
Agent detail's persistent input suppresses this feedback for its whole ownership
lifetime, including reading travel and the Harness flip before input opens.
Entry, replacement and return therefore cannot mistake delayed editor admission
for a user-closed input or reveal retained orbit ink. Ordinary closed-input
running/submission feedback and the running story remain unchanged. See the
[composer admission contract](../../../../../design/composer.md).
The direct-send gaze follows the leading dot from the first lap. Submission feedback does not grant Stop
authority, consume a draft or navigate before a confirmed receipt. Failure or
an unresolved receipt retires submission feedback and leaves the existing draft
and error/recovery path intact. Accepted continuation keeps its pending feedback
while waiting for a new Thread's catalog event. Confirmed execution activity can continue the
same orbit clock; unrelated Moku execution updates cannot restart it.

An accepted exact-execution continuation retains the previous Dock column,
expanded shell and Harness logo seat while its new reading visit prepares. Native column
markers belong to a route and publish only after auxiliary layout admission;
retained outgoing Report markers cannot overwrite the destination. The Dock
travels directly to that committed column with monotone easing, without
adding an intermediate layout destination. Replacements use
the currently presented horizontal position; resize, dragging and deactivation
settle travel directly. This preserves the existing draft,
receipt, input-readiness and late-callback fences. See the
[composer geometry contract](../../../../../design/composer.md).

The [Host receipt replay](../../../../../demos/moku-panel-transition/README.md#host-receipt-replay)
exercises the production client transport and journal with fixture outcomes.
The [composer ownership guide](../../../../../design/composer.md) describes
the implemented admission and cancellation boundaries.

Settings starts with a 900-point preferred height and grows to the active tab's
natural document height (including header and form insets). The shared Dock shell
keeps its 780-point preferred width and caps both dimensions to the workspace
viewport with 24-point margins. General, Moku, Tag and Report use this same sizing,
including inherited and independent Harness forms. Smaller windows,
expanded editors and notices retain native scrolling; short viewports also scroll
the whole shell so navigation remains accessible. No scrollbar is hidden to fit
content.

Super Thread document/list state does not admit Moku input. The shared scene
admission gate blocks capsule clicks, Compose menu/shortcut actions, scripted
toggles and direct open requests; its compact capsule exposes no input launcher
or hint. Selecting an associated execution still borrows and pins the ordinary
Agent composer after reading/content admission. During a follow-up the submitted
page holds the expanded composer's source column and draft until the destination
reader and exact input are admitted. A ready-to-ready handoff at the same frame
changes input ownership in place, including when a fork changes Thread. Returning to the list, folding
or replacing the associated reader immediately retires input, including pending
focus work. Escape retains the report's auxiliary Back or normal close; IME,
completions and covering routes keep their existing precedence. Overview and
exact-execution drafts retain their existing storage identities. No associated
Agent receives unselected input.


## E2E contract

[`E2E-COMPOSER-001`](../../../../../tools/e2e/README.md#composer-system-input-boundary)
uses real system text input and the mounted `moku-send` / `moku-stop` controls in
an isolated ordinary Agent Thread. The operator observes the selected Thread,
typed draft, Send, consumed draft and visible completed reply. A second typed
input holds the real Codex execution at the external model-service boundary;
its empty composer must expose Stop in the same reader visit. Clicking Stop
interrupts that exact execution, removes the Stop action and leaves the editor
usable. This is cancellation, with no pause/resume contract.

The Dock retains its selected Thread as an observable snapshot, refreshed by
normal catalog/presence events. Its running/finished action seat therefore updates
without requiring a route change; unrelated indexed catalog reads remain quiet.
The current Thread's empty input shows Stop while active, and nonempty input
shows Send in that same seat. Existing source/draft ownership and exact-execution
admission still govern the action.

Preconditions are an exclusively scheduled desktop, current checked production
artifacts, a unique test App/profile, real native Codex discovery and a system
input operator with Accessibility access. The runner checks exact persisted user
prompts, completed output, mounted execution identity and `interrupted` public
state; `operator-send/stop.json` records actual AX observations and confirmation
of the clicks. Those receipts are operator attestations, not unattended AX
capture. Missing receipts or controls cannot pass. Report/source/manifest and
cleanup records bind every attempt to its implementation and retained evidence.

This scenario is operator-assisted and is not run by the hosted workflow. It
covers ordinary current-Thread text submission and cancellation only. It does
not certify IME, attachments, historical forks, Report input, Moku-wide cancel,
uncertain receipts, restart recovery or real external-provider behavior. Runtime
invariants remain PBT's responsibility; latency and animation quality belong to
benchmarks. A scenario definition is not evidence that a particular commit ran.
