# Resident input visual preview

```sh
python3 demos/moku-panel-transition/build.py --open
```

`--skip-build` reuses the current production build. The app path is written to
`.build/moku-panel-evidence/app-path.txt`. The preview mounts production Scene,
Dock, composer, native editor, eyes and capsule glass; the reading background and
business states are fixtures. An isolated app launched with `--capture` records
its own presentation PNGs and `samples.json`, without correctness assertions.

The main window accepts typing, Escape, outside click and resize. A separate
control window changes input state, running state, route, size and local animation
transaction. The production [composer contract](../../design/composer.md)
owns pinned Agent input and its single active-execution action seat; fixture
route toggles cannot establish real Runtime or receipt behavior.

## Joint workspace replay

Use a Chinese, dark macOS desktop with a 2× display large enough for an
1885×1125pt window, Accessibility and Screen Recording permission, Xcode and
the Codex CLI. From the repository root, capture a fresh campaign:

```sh
python3 demos/moku-panel-transition/workspace/capture.py /tmp/chief-bar-visit
```

The runner builds one Debug app and Runtime, links the mounted preview against
the same Swift modules and records binary digests. It uses a private profile
and a loopback peer. The workspace starts empty, creates its first Agent cards,
opens the dispatch row for editing, hovers the compact capsule and focuses its Stop button, reverses a
fold and presses Stop via its unique AX control. A second running Chief turn on the populated Overview
exercises click-to-open, Escape, outside click and a 120ms Compose reversal.
Two completed card visits use the reader's Close control. A held follow-up
then opens in the right-hand Execution sidecard. Its return recording starts
with the editor settled beneath that column and ends on Overview after Close.
The peer releases the same execution to finish after the return. The mounted preview
also drives narrow right-column visits with short and long titles. A separate
first-run profile measures the 780ms contraction and the focused editor.

The window driver records the exact app PID, nonce bundle, executable, focused
workspace window number, private profile and runtime PID/epoch in
`input-target.json`. It checks these before each event. Pointer and key events
are addressed to the test PID. AXPress resolves a unique enabled control in
the focused test window. The macOS-only helper uses the Accessibility window-ID
bridge and Quartz window-local event coordinates. These APIs are confined to the
replay executable. The run withdraws its own window and probes focus
loss, a different window number, runtime PID and bundle. Each must be rejected.
The onboarding driver checks its button, focused window and runtime identity
before each confirmation.

Inspect `first-card/window.mp4` and select one zero-based frame with the
pending dispatch label and a later frame with the started label. Run the joint
check with Python, OpenCV, NumPy, FFmpeg and ffprobe. For example, if the two
labels are visible at frames 189 and 213:

```sh
python3 demos/moku-panel-transition/workspace/check.py /tmp/chief-bar-visit 189 213
```

The frames supply the two text templates. All encoded frames, including the
start of each close, enter the measurements. The checker saves center and
width per Overview frame, flip positions, label and Stop samples, and all
native phase results. It checks the Stop execution identity and compares
workspace and onboarding build receipts. For first-card Stop insets it locates the square
and the bright outer rim on independent scanlines of the original 2× frame.
The sample file retains the dark-cap estimate alongside the rim positions.
Review unresolved mark frames
against the movie. The screen-recording variant accepts a vertical search
band in source pixels, for example `check_workspace_folds.py screen.mov
positions.csv --band 2180 2350` for a 4096×2514 recording. This locates
the silhouette within the window without trimming the time interval.

For one right-column return, run
`python3 demos/moku-panel-transition/check_workspace_folds.py window.mp4 positions.csv --column-return`.
The movie starts in the expanded editor and ends with the compact Dock at the
window center. On a full-display recording of a centered window, use `--band`
to select the Dock’s vertical range. The check requires intermediate widths at
the source and intermediate compact positions on the way to center. It checks
every frame for width jumps and rightward reversals. It locates the corner
at the workspace center, checks constant height up to that frame and constant
horizontal position through the lift, with a two-point optical tolerance.
The CSV includes the glass cap's top edge and horizontal center in pixels.
The [native-scale return recording](evidence/column-return/return.mp4) and
[frame coordinates](evidence/column-return/positions.csv) cover Close from an
active Agent column to Overview. Its [capture record](evidence/column-return/capture.json)
identifies the test window, builds, external peer and corner.

## Overview Dock replay

Build the preview as below and run its executable under the shared desktop
verification lease with `--capture-overview`. A small isolated panel mounts
the running Chief's production Dock over a plain backdrop. It opens and folds
the editor, reverses another fold after 120ms, then opens from a dispatch notification. Use `--english` for English (the default
is Chinese). The replay writes `overview-*/window.mp4` and
`observations.json` next to the temporary bundle. Use a fresh output directory.

Add `--system-input` to drive the panel externally. Once `ready.json` identifies
its PID and window, click the eyes, click the blank area inside the panel,
activate **Open Chief input** via AXPress, then click or AXPress **Stop Chief**.
The replay checks the open/closed/open sequence and the
fixture's cancellation callback. Run
`python3 demos/moku-panel-transition/check_overview.py <capture-directory>`
on either movie using FFmpeg, ffprobe, NumPy and OpenCV. The checker measures
every encoded frame against the fixed center and detects width steps of at
least half the full travel. It looks for both eye cores across the entire Dock
band, including outside the glass during a fold. In the scene-driven movie it
requires an intermediate reversal and independently matches the settled model
name and input placeholder to catch simultaneous ink. It also checks for text
in the reserved Stop seat and measures the square’s clearance from the rim.
When a blink or partially visible Stop cannot be located at one pixel per
point, it repeats the measurement on that frame's original 2× pixels with
the same size and fill criteria. The result identifies recovered frame indices.
On the system-input movie, with the pointer over the
compact eyes before each opening, the square must remain visible as the
capsule widens. Its measured distance from the right edge stays between
the compact and open seats, including while it fades on outside click.
Review the input ink as the capsule folds.
The fixture uses an in-memory draft and a simulated running task.

### First card in the full workspace

Use a fresh dark, Chinese workspace at 1885×1125 points (2× capture). Start
the full-window recording on empty Landing before submitting to Chief. Have a
deterministic peer create two Threads and hold the Chief turn open. Keep
recording through the first card, pending and started dispatch, opening the
editor, normal folds, rapid reversal and Stop. Click the displayed Stop and
check that the same execution changes from running to interrupted.

Inspect the two settled labels to select a pending and a started reference
frame with readable text at the ordinary Dock scale. Frame numbers are
zero-based. With OpenCV, NumPy and ffprobe, run:

```sh
python3 demos/moku-panel-transition/check_landing_handoff.py running.mp4 PENDING_FRAME STARTED_FRAME samples.json
```

The reference indices select glyphs. The checker searches **every encoded
frame** for both labels at the same origin, and independently searches the
whole window for eye pairs. It checks signed eye clearance, a centered shell,
and the 22–29pt trailing Stop seats with 2pt optical tolerance. It requires
the Landing descent and observations of both Stop positions and both labels.
The JSON lists every frame, including unresolved eye pairs. Review these
frames for blinks or occlusion before reporting containment. Use the smaller
system-input replay above to check continuous hover ink and accessible clicks.

## Collapse replay

Build the preview without `--open`, then run the printed app's executable directly.
The replay needs the repository macOS/Xcode toolchain and a WindowServer session
with ScreenCaptureKit current-process capture. Use the shared verification lease
when running alongside other native verification.

```sh
python3 demos/moku-panel-transition/build.py
replay_app="$(cat .build/moku-panel-evidence/app-path.txt)"
"$replay_app/Contents/MacOS/MokuPanelPreview" --capture-collapse
```

A nonactivating panel starts with the Report list's input gate closed. Selecting
a fixture execution publishes the right column through the production native
marker and waits for Dock travel and the Codex identity flip before expanding
the composer. The replay checks that the list and moving Dock have no editor,
that the selected column admits one editor, and that returning to the list
and reselecting releases and restores input. Pass `--narrow` to exercise the
two-row layout in a 480-point window. Build a fresh bundle for each capture.

The replay then switches to a separate in-memory Overview draft with continuous
Dock eligibility, closes and reopens the Overview editor during its
420ms retention window. It marks and commits text through the mounted
`NSTextInputClient`, then types into the same editor. It checks the exact multiline
draft and UTF-16 selection after reopening and checks that closing again
presents queued Talk without consuming the draft. The harness calls AppKit's
input-client methods directly. A system IME candidate UI needs separate
system-input verification. See the
[Dock contract](../../app/macos/Sources/Host/MokuScene/README.md#dock-and-composer).

The app exits and saves `collapse/window.mp4` and `collapse/observations.json`
next to its temporary bundle. Inspect intermediate opening frames. The first
visible placeholder glyph and the attachment button must clear the Codex logo.
The compact editor must enter above the logo. Check that outgoing ink disappears
at the start of closing and that the reopened draft and Talk reply are readable.
The replay uses real rendering and native editor state with synthetic routes
and no Runtime or system input. Pixel review is manual. A reused output
directory, missing window capture or failed semantic check cannot establish a pass.

### Capture diagnostics

The movie records the replay's own borderless window. This keeps AppKit's
title-bar sharing indicator outside the measured layout. ScreenCaptureKit
attaches the movie output off the main actor because that call can perform
trust checks. The recorder keeps the native display timestamps and waits for
the movie to finish before closing the stream.

For a Fault investigation, record the executable, PID and launch-to-exit
interval for each run. Query the macOS unified log for that PID and interval,
confirm it contains process events and retain every Fault with its backtrace.
Compare the recorded route with a Release workspace in a temporary profile
opening the same kind of Agent from Overview and returning without recording.
An empty AppKit panel can isolate the recorder by varying only the title bar,
the stream or its recording output. Use the mounted events and frame checker
to verify that the recorded route still performs each interaction.

## Agent entrance replay

Use the same isolated preview build and the shared verification lease.

```sh
replay_app="$(cat .build/moku-panel-evidence/app-path.txt)"
"$replay_app/Contents/MacOS/MokuPanelPreview" --capture-agent-entrance
```

A nonactivating panel uses an in-memory Agent draft and a separate Overview
draft. It opens a short Chinese title and a long title in the same narrow
right column on successive visits. The production reading panel, column
marker and Codex identity drive Dock travel and input admission. The fixture
suppresses the column during panel return, as the workspace does. A two-point
click-through strip at the screen edge keeps the window rendering during
current-process capture. The replay checks the 168×44pt idle target after
each return. All four short/long Agent visits use production-default autofocus. The replay
interrupts an Overview entrance at 80ms and reopens it after another 80ms.
In a separate Compose opening, it sends the first key to the non-key fixture
window during a rapid reopen and checks that the draft receives it. It then
moves the responder out of the editor and checks that it stays away through
the rest of the ink transition.
It also reopens a populated editor during its 420ms retention window. It marks
and commits text through the mounted `NSTextInputClient`, then types into
the same editor. It checks the exact multiline
draft and UTF-16 selection after reopening and checks that closing again
presents queued Talk without consuming the draft. Both titles then open again on
the ordinary reading clock to check autofocus at production speed. A separate pinned Agent
visit drives the explicit Compose command at admission. The harness calls AppKit's
input-client methods directly. A system IME candidate UI needs separate
system-input verification. See the
[Dock contract](../../app/macos/Sources/Host/MokuScene/README.md#dock-and-composer).

The app saves `agent-entrance/window.mp4` and `agent-entrance/observations.json` beside
its temporary bundle. Run the frame check with Python, NumPy, OpenCV and
`ffprobe` against this 2×, 1024pt-wide Chinese-language fixture.

```sh
python3 demos/moku-panel-transition/check_frames.py "$(dirname "$replay_app")/agent-entrance"
```

A blue tile beside the responder marker identifies the fixture phase. Each
numbered phase in the native receipt has its own horizontal position in the
recording. The checker reads every frame in presentation order and requires
one unambiguous tile and every phase in sequence. Its JSON pairs each phase's
first frame and movie PTS with the native elapsed time for diagnosis. All
frame ranges use the recorded markers. For each Agent, the template comes
from the middle frame of the marked settled hold before Close. The return
includes every frame from the Close marker up to the next visit. Recordings
need phase markers to run this checker.

The first two Agent entrances measure geometry. For admitted input in these
visits the native Dock evaluates its production opening animation at every
1/60s of source time, holding each step for 100ms of replay time. This gives
the recorder several refreshes to see ink while the shell is still moving.
The fixture installs the clock before admission. The responder, editor,
glass and glyphs are rendered together. Return, rapid reversals and the
subsequent real-time Agent visits use their ordinary animation clocks.
The held frames describe geometry at the sampled source times. Use the
real-time visits for focus timing at normal speed.

On all four returns the checker measures from the Close marker to the first
frame showing 10% of the width change from expanded to idle. That frame must
fall within the first half of the 420ms panel return. Until the shell reaches
idle width, its center must stay at the source column within two points. The compact shell must then
reach the workspace center at the reading height, then show intermediate
heights at that fixed center. It finishes at the initial height and width.
The checker retains movie PTS, center
x, top y and width for compact frames. At 2× the two-point edge tolerance is four pixels.

Two additional real-time visits use a centered Agent editor without an
Execution column. The checker measures the visible Codex mark against the glass
edges throughout each return, with a two-point tolerance. It requires the mark
in the expanded editor and during intermediate widths, and verifies the compact
Overview endpoint after the mark retires. On the second visit the fixture occupies the main thread for
120ms during expansion and again during folding. The marker changes before and
after each hold. During each marked hold the checker measures shell and mark progress separately.
The SwiftUI shell can hold its last layout while the main thread is occupied.
The mark must stay inside the shell through the hold and subsequent fold. During the
fold it also requires at least three positions of the reading panel’s visible
left edge. The result includes per-frame width, mark and panel position, and
the largest interval between recorded frames. This controlled workload measures
already-submitted motion. Attributing a stall to a particular reader operation
requires a trace of that session.

Two further visits reopen the reader from an observed intermediate presentation
position, once on each return axis. Each must restore one editable, focused
editor in the right column beyond the previous return's completion.

For each geometry visit the check matches the first placeholder glyphs against their
settled pixels and measures each returning glass silhouette against both the
open width and the narrowest frame so far. The placeholder must disappear during
contraction and the shell must reach its initial idle width. The check allows one point of glyph displacement and
two points of silhouette variation for rasterization, compression and the changing glass backdrop.
Each direction must supply intermediate widths. The JSON result reports the
largest displacement, width and regrowth with their movie times. It also
reports the count, distinct widths and first/last PTS of readable frames
strictly more than four pixels short of the open width. Missing that window
fails the visit even when its settled reference is readable.

The capture panel paints a red or green marker when AppKit changes the actual
first responder. For default Agent focus and both Overview reversals, each
green frame during acquisition must show the settled placeholder or draft
strokes at 10% or more of their settled contrast. Focus must arrive by the
next recorded frame after visible ink and persist through the hold. The
explicit Compose visit must acquire focus before ink appears. The marker
and glyphs share a movie frame and presentation timestamp. Inspect the movie
for partial glyphs crossing the Harness mark, tail truncation, immediate ink
retirement on Close and readable draft and Talk after rapid reversal. The
mouse-transparent capture panel must retain queued Talk through a click
posted to a second, hidden window in the same replay process.
Missing or fully occluded motion cannot establish a visual pass. These frames
exercise synthetic routes and in-memory drafts without a Runtime or system input.
After capture, the focused Agent editor sends via Return and commits a new
draft through AppKit marked text. The fixture returns to Overview and rejects
the earlier send. It checks the exact restored Agent draft and that Overview
keeps its own draft and focus.

### Report identity flip

Build the private runtime and native modules with `tools/e2e/build.py --go ./scripts/go.sh --with-app`.
Run the Report workspace with its deterministic peer and the current-process window recorder.
The replay selects the related execution, presses the mounted Report close button and reopens
the same Report during its return. A separate process sets Reduce Motion in the workspace
environment. Both windows keep the system setting and the user's Chief profile untouched.

```sh
python3 demos/moku-panel-transition/workspace/report_followup.py --identity /private/tmp/report-identity
python3 demos/moku-panel-transition/workspace/check_report_identity.py /private/tmp/report-identity/identity
python3 demos/moku-panel-transition/workspace/check_report_identity.py /private/tmp/report-identity/identity-reduced --reduced
```

The checker measures the ink at native 2× resolution against each encoded frame's
timestamp. For each half turn it uses the nearby full height of that face and
requires thin and intermediate projections.
At 45° and 135° the visible face projects to about 71%
of its upright height. The checker brackets each crossing with samples at most two
60 Hz frames apart. The [420ms reading curve](../../app/macos/Sources/Host/MokuScene/README.md#dock-and-composer)
spends 64ms between these angles. The movie allows one frame per crossing for
sampling and rasterization. The fully expanded bar must hold the logo at full height.
Corresponding legs must agree within 85ms. The return must cross the edge during
contraction, and reopening must show the partially revealed eyes narrowing back toward the logo.
The reduced-motion visit checks endpoint widths and a full logo in either direction.

The [window recordings and frame evidence](evidence/bar-motion/README.md) include the baseline and the two measured directions.

### Right-column identity return

This offscreen replay mounts the production workspace with a completed Codex
result in the reader and a running follow-up in its Execution sidecard. It
clicks the mounted **Close thread** button with mouse events confined to that
window. A second visit reopens the same Agent during the fold, checks that the
editor waits for the Harness mark and regains its draft, then presses Close again.
The peer releases the same follow-up after both returns.

Record into a new directory on macOS with a 2× display, native Codex CLI,
Python, OpenCV and ffprobe.

```sh
python3 demos/moku-panel-transition/workspace/identity_return.py /tmp/chief-identity-return
python3 demos/moku-panel-transition/workspace/check_identity_return.py /tmp/chief-identity-return/close/window.mp4 /tmp/chief-identity-return/close
python3 demos/moku-panel-transition/workspace/check_identity_return.py /tmp/chief-identity-return/reverse/window.mp4 /tmp/chief-identity-return/reverse --reverse
```

ScreenCaptureKit records only the nonactivating panel in the replay process.
The 4096×2450 framing preserves the reference's workspace bounds and 1.8 movie
pixels per point. The window renders at native layout scale on a 2× display.
The checks measure the capsule on every encoded frame. Both a foreshortened
Codex logo and the incoming eyes must be visible during the in-column fold.
The compact bar must reach center at reading height before it lifts.
The interrupted visit must stay in its reading column and show the logo,
eyes and logo again before the final close. Per-frame measurements retain unresolved frames for visual inspection.
The [close recording](evidence/identity-return/close.mp4) and
[interrupted return](evidence/identity-return/reverse.mp4) are untrimmed.
The [capture record](evidence/identity-return/capture.json) identifies their
production sources, input events, first visible eyes and measured turn into the lift.

### Production centered return

To verify centered entry and return in the production workspace, use an
[isolated desktop session](../../tools/native-interaction/README.md) with a
completed Codex Thread. Start recording the entire window on Overview and
open its card. Keep the Execution sidecard folded and wait for the centered
editor to expand. Click the reader's upper-left Close button or activate it
through AXPress. Inspect the full window during the initial descent and after
the reading surface releases its route. Visible eyes must stay in the capsule.
Inspect the intermediate widths in both directions. The visible Harness mark
must stay within the glass as the editor expands and folds. The return must
finish at the compact Overview capsule with the resident eyes.
For a single completed Codex card visit from the compact Dock in a dark
1885×1125pt workspace at 2×, run the whole-window pixel check on its recording.

```sh
python3 demos/moku-panel-transition/check_centered_handoff.py window.mp4 positions.csv
```

The checker measures both directions independently on either side of the widest
reader frame. It requires intermediate glass widths, the eyes and logo in
sequence, and a visibly tilted logo on each leg. Across both legs the center
of the visible glass must stay within 2pt of the window midline. It reports any localized ink
more than 2pt outside the capsule and saves all frame positions. Inspect the
listed unresolved frames for an edge-on flip, blink or occlusion.

Repeat with the workspace already mounted when Chief starts a new Codex Thread.
Keep the new Thread running. Confirm the **Thread started** notification in
the wide Overview capsule, then click the visible card before the notification
expires. Verify the centered reader exposes the editor and Stop. Check the
first frames of expansion as the editor reports its vertical inset. Also click
Close during expansion, reopen the card and check the mark on both legs.

Keep the executable digest, revision, displayed layout, input backend and movie.

## Control ink recording

Run the preview executable with `--capture-overview --english --control-ink`
under the shared desktop and performance leases. A nonactivating panel records
its own production Dock. The fixture inserts ten characters through the native
editor, clears the draft, reverses a Send reveal after 55 ms, folds the editor
and delivers pending, started and failed dispatch projections. The movie and
event times are written to `control-ink` beside the disposable bundle.
The replay checks the native draft, responder and foreground owner. The
[frame checker](check_control_ink.py) reads each encoded frame. It checks
action ink against the settled Stop and Send seats, measures reversal and
compares status ink with the settled labels. Run it with the capture directory
and a JSON output path. Add `--reduced-motion` to record the same events with
the local SwiftUI accessibility setting enabled. The checker then requires
direct glyph and label changes. These fixture operations do not call a Harness.
The [recordings and frame measurements](evidence/state-ink/README.md) include
both motion settings, an interrupted fold, and receipts from the mounted routes.

For the directory-removal regression, run the same preview under the shared
leases with `--capture-overview --english --directory-removal`. The idle Dock
starts with a directory-only draft. The fixture invokes the directory chip's
draft removal action and checks that the same editor retains focus and the
draft can no longer submit. With normal motion, run
`python3 demos/moku-panel-transition/check_directory_removal.py <directory-removal>`.
The checker tracks the arrow and plus in every recorded frame, requires their
positions to stay within one point, and checks the 43-point shell contraction
and the dimmed arrow at rest. The fixture uses an in-memory directory.

## Chief input replay

Add `--verify-actions` to `--replay-chief-input` to check the single 32pt Send/Stop seat in the mounted
Overview editor, including control labels, enabled state, mouse clicks, AXPress
and Return with whitespace, text and attachments. This option needs
macOS Accessibility permission. A child process reads and presses only the
buttons in its own replay parent.

Run `--replay-chief-input` under the same shared desktop verification lease to
check the [Chief composer contract](../../app/macos/Sources/Host/MokuScene/README.md#dock-and-composer).
The 1× nonactivating panel mounts the production Overview Dock outside all displays. In a separate process with read access denied to both keyboard CAFs, add `--expect-unavailable-sounds` to confirm the missing-resource precondition and run the same input checks. It counts and forwards
the editor's keyboard sound requests for typing, auto-repeat and both delete keys.
It delivers an input key while marked text is active, updates and commits the marked
range through AppKit, and checks that composing callbacks, navigation and draft
restoration add no requests. This exercises the native client callbacks without
selecting a system IME or measuring speaker output. It delivers local AppKit key events, pastes through a private
pasteboard, edits the text and submits through Return. The replay checks that
typing `@` opens no completion UI and that bare `@` and messages with and without
`@` reach the submission callback as exact text parts. A reopened draft sends a saved catalog path as plain text. The replay
feeds host metadata to the draft action used by the directory picker's
**Choose** button and checks that the explicit selection stays structured.
The replay checks the production macOS panel's selection settings, then exercises
the mounted plus with fixture selections. It checks cancellation, a folder-only
send and a mixed selection with two files against the submitted parts.
The app prints the covered cases and exits nonzero on a failed assertion.
The isolated callback captures the payload without starting a Runtime.
The [Chief file picker procedure](../../tools/e2e/README.md#chief-file-picker)
covers system interaction with the picker UI.

### Typing audio output

With interface sounds enabled and a nonzero effects volume, add
`--replay-typing-cadence` to `--replay-chief-input`. The replay sends keys to
the panel's first responder. ScreenCaptureKit captures mono 48 kHz PCM from the
preview's own window. Each group checks the draft and counts signal onsets
above 0.0005 amplitude separated by over 3 ms of quiet. The log includes onset
offsets and the number of frames collected during each group.

The workload includes 12 printable keys each at 120, 40 and 20 ms, six keys in
one event-loop turn, focus away and back, rapid Backspace, auto-repeat, forward
Delete and a composing key followed by marked-text updates and a Chinese
commit. Paste, navigation, the newline shortcut and draft restoration add zero
clicks. Composition uses the native text client without switching the Mac's
input source. Capture measures the process output before the speakers.

Use `--expect-silent-typing -com.apple.sound.uiaudio.enabled NO` or
`--expect-silent-typing -com.apple.sound.beep.volume 0` to repeat the waveform
and draft checks with process-local Sound preferences. Denying access to the
two CAFs with `--expect-unavailable-sounds` also requires silence throughout.

## Pending send replay

Build the preview as above and run the executable with `--replay-send` under
the shared desktop verification lease. Its panel cannot become key or main and ignores system pointer input. It mounts the pinned
Thread composer with the editor's normal text input settings. The fixture
delivers local AppKit mouse events to Send, Return to the native editor, and
marked text and commits through the NSTextInputClient interface. It supplies
the admission result. It never opens a Runtime connection.

Send, the next insertion, rejection and another insertion can all occur on the
same event stack. Assertions compare the native text, the saved draft and the
peer's captured payloads, including duplicate presses, equal successive text,
composition and reselecting the same directory through `@` completion. For
delayed receipts the fixture waits only for the send operation to settle.
Two mounted native editors share a saved scope. While the first holds marked
`pin`, the second inherits it and adds only a directory, adds only a fixture
attachment, or selects the body and replaces it with `B` or the same `pin`.
Each case runs with acceptance and rejection. The first editor commits `拼`
and inserts `C` on the same event stack. Assertions cover native text, model,
reopened draft, chips and the exact payload of the next explicit Return. An
additional acceptance case finishes composition with AppKit’s `unmarkText`.
Separate writer and reader processes share a temporary draft scope: the writer
exits before admission, and each local recovery choice must yield the expected
text with zero deliveries in the reader.

The executable prints the results and exits nonzero on a failed condition.
System input-source candidate selection, system-wide mouse routing and actual
Runtime delivery require separate verification. The
[operator-assisted Composer journey](../../tools/e2e/README.md#composer-system-input-boundary)
covers system input and persisted Runtime results.


## Host receipt replay

With the debug production build available, run
`python3 demos/moku-panel-transition/receipt_replay.py` under the shared
verification lease. The replay attaches the production RuntimeClient
through a loopback fault proxy to the production Go transport in a temporary,
exclusively owned profile. The proxy disconnects after the Go ReceiptStore
reports pending. The Go Host fixture counts actual handler entries. A baseline
bare UUID must fail admission, and a duplicate of an admitted ID must return
the recorded result with no additional handler entry. The execution-change
path checks both derived fork and follow-up IDs. Both the live and reconstructed Host check the captured ID.

The ordinary Agent result scenario holds the Go response, submits a local draft,
and checks the production workspace's selected card and execution ownership
before delivering a receipt or index. It checks both receipt/catalog orders, a terminal run, rejection with a
successor draft, folding, Browser selection and replacing the reading target. The scenario
drives the native presentation and selection model without measuring screen timing.

The [Super Thread follow-up scenario](ReportSendReplay.swift) mounts the Report
sidecard and native editor, presses Return on a finished execution, and holds
the Go response for at least 900ms. The new heading and a single inline
connection label must land before the receipt. OCR locates the label below the
submitted heading. The accepted reader must take over in the same visit. The
replay also checks duplicate Return, continued typing, rejection and restoration,
and leaving before the reply. The document and source are fixtures. The accepted
reader uses a Go-reduced Codex turn. Set `CHIEF_REPORT_REPLAY_EVIDENCE` to an
existing absolute directory to keep the AppKit bitmap samples.

To capture the complete workspace, build the Debug Chief Swift product and the
Go `./cmd/chief-runtime` binary at `.build/e2e/chief-runtime` (or pass
`--runtime`). Run
`python3 demos/moku-panel-transition/workspace/report_followup.py /private/tmp/chief-report-followup`
with a new output directory and the shared verification leases available.
The replay creates its own profile and mounts a nonactivating 1280 × 820 point
window at native scale. ScreenCaptureKit records only that window.

The [whole-window Report recording](evidence/report-send/send.mp4) covers a
native Return in a finished execution beside a mounted Super Thread. The
[screen coordinates](evidence/report-send/positions.csv) cover every encoded
frame from the settled source through the completed successor. Recompute them
with `python3 demos/moku-panel-transition/check_workspace_folds.py send.mp4 positions.csv --report-send`.
The expanded right-column glass must keep its center and top within one pixel
and its width within two pixels. The [capture record](evidence/report-send/capture.json)
identifies the window geometry, peer, submission and readiness observations.
These recordings measure native composition with deterministic responses.
Live service latency is outside their scope.

The live steer scenario holds the HTTP handler and reads pixels from a mounted
Codex turn. It compares the settled row across receipt and content updates.
The receipt-first case takes the initial sample with Reduce Motion enabled.
The replay covers both receipt/content orders, identical consecutive inputs,
first-run and sidecard ownership, direct
rejection, explicit retry, switching Threads with the same execution ID and
receipt recovery after disconnect. The navigation checks restore saved current
and archived Chief identifiers to Overview and reject their execution links
from an ordinary reader. The peer supplies the Codex transcript and controls
event timing. The run measures neither model processing nor latency.

The Chief case begins with a saved send that carried a structured catalog
mention and checks the receipt under its original command ID.
Assertions cover a pending result, final acceptance and rejection, a different
draft with identical text, and a subsequent explicit send. The replay also
makes the temporary draft directory read-only for one edit, restores its
permissions and checks the durable successor and acknowledgement. A fresh process
finishes cleanup after a disk error on either side of journal acknowledgement.
Historical fork and follow-up phases cover explicit local recovery, with the
peer counting each mutation. A new send from the same historical checkpoint
must fork from that checkpoint again after late acceptance. A competing process tests the scope lock. The Go
attachment repository stages two real files, contends for the ownership lock,
and collects again after the editors exit. A mixed picker selection sends a folder and both staged files through the Chief
submission route. The Go handler log must contain the folder mention and the
two repository file IDs. The replay checks the surviving bytes
and the released file's removal. The fixture supplies service bootstrap and
command outcomes.
