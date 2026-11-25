# Moku landing 原生 demo

复用生产 `NativeMokuScene`、`NativeMokuDock`、原生 composer、Overview 和窗口材质，
以内存 fixture 展示空工作区、首次派发、失败、归档和窄窗口状态。

```sh
python3 demos/moku-landing/build.py --open
```

已有当前生产 Swift build 可加 `--skip-build`。按 Command-D 打开演示控制，
Command-1/2/3/4 分别重置、演示成功、失败及归档。
独立 app 路径写入 `.build/moku-landing/app-path.txt`。
预览不配置自动断言、截图验收或验证报告，也不启动 Runtime 或真实模型。

## Untagged running work and tag visibility

Build the current Debug package, then run the mounted production workspace with an isolated catalog.

```sh
python3 demos/moku-landing/verify_header.py --tag-states --output .build/tag-states
```

The replay reads the empty Inbox message from a window capture, adds an untagged project run and checks that the first card and its folder arrive together. It then assigns the folder’s name as a semantic tag. It clicks the folder and its sole child, then selects six tags with equal and nested member sets. The evidence directory contains the three state screenshots and `tag-states.json`.

## Nested workspace header replay

Build the current Debug package and use a new output directory. The optional
`--keyboard` check uses the shell's macOS Accessibility permission to focus a card in the isolated app.

```sh
xcrun swift build --package-path app/macos
python3 demos/moku-landing/verify_header.py --capture --keyboard --output .build/nested-header-replay
```

The replay mounts the production workspace and its nested reading host with
a temporary fixture catalog. It checks 1100pt and 600pt windows at actual size.
The JSON records rendered filter bounds, native window button centers and
hit tests, and whether a window-local click in the upper part of the
Settings button opens Settings in both actual-size windows. It also records
header exclusion, precise diagonal input, vertical-only input, native momentum
phases, mouse wheel bounds and Settings input ownership. Before posting a synthetic scroll, the replay checks that AppKit
decodes the intended window, backing pixel, hit view and scroll precision. An 18-task fixture
also exercises blank-space drags and clicks, a mouse click on a newly reached
card, reader return, insertion and deletion. The drags start in the blank area
beyond the trailing and bottom card edges. The receipt `overview-scroll.json`
records the input point and the card frames. A directory selection reduces a
scrolled grid to four columns totaling 1328pt. At 1360pt window width the grid stays
centered through wheel, trackpad and momentum input. At 1359pt the trailing
edge is reachable. Widening to 1376pt clears the offset again. The replay
writes the window widths and offsets to `overview-fit.json`. With eight fresh
cover reports it records the mounted members and travel in `collection-fit.json`
while a task enters and leaves a wide viewport, as the viewport crosses the
three-column boundary, when scrolling remains necessary, and when it grows again.
Those Collection checks set the mounted workspace’s layout size directly so a
2064×1212pt viewport can be measured on a smaller display.
With `--keyboard`, the replay scrolls a column with each arrow key and opens the
focused card with Return. It records both distances and the card identity in
`overview-keyboard.json`. Optional captures show the isolated workspace.

### Mark a tag as read

After building the Debug package, run the pointer replay in a fresh directory.

```sh
python3 demos/moku-landing/verify_header.py --tag-read --output .build/tag-read
```

The mounted project has two tags sharing a completed task, a Super Thread in
Development and a separate completed task in Review. Window-local AppKit input
exercises clicks, scrolling over a tag, a drag out and back, Escape, a wheel
contact during a press and a hold on the unselected tag. The replay checks the
selection and unread counts, reads the mounted tag accessibility values, samples bookmark pixels on both visible cards and
reopens the receipt store from the isolated profile. A new completed execution
must reappear in both tag counts, and a document revision must relight its own tag. `tag-read.json` records the observed counts
and selection. `source.json` identifies the checkout and platform.

### Unread preset

Build the current Debug package and run the mounted workspace with a fresh profile.

```sh
python3 demos/moku-landing/verify_header.py --unread-filter --output .build/unread-filter
```

The replay uses window-local AppKit input to open Unread and find an untagged
completed result. After a tag arrives, it holds the tag to mark the result as
read. It checks the persisted receipt, the empty canvas with Unread still
selected, and the accessible button name and visible empty message in English
and Chinese. A catalog patch publishes a new completed execution of the same Thread.
The replay also switches between folder Running, a custom tag named Unread and
folder Unread with both Agent and Super Thread cards. A second catalog has one
unread task in Chief and one in the top-level stock research tag. Both badges
start at one. The replay switches between them in Unread, clears the folder’s
tag, adds a second tag to the research task and checks both tags after its
version is acknowledged. It also checks a Report covering the Chief task and a
catalog with no top-row space. The output contains `unread-filter.json`, the empty-state captures and `source.json`.
This uses the production native workspace and fixture snapshots and mutations.

### Talk execution links

Run the mounted workspace replay with the current Debug package.

```sh
python3 demos/moku-landing/verify_header.py --talk-link --output .build/talk-link-replay
```

The compact layout visit captures a one-line Chinese notice and a multiline
notice ending with a run link. It checks that the short notice fits the
58-point Overview row, the complete multiline document is visible, and the
button has 8–16 points of clearance to the shell's bottom edge. The two
window captures and `notification-layout.json` record the mounted result.

The replay clicks the native glass execution capsules in the compact notification and the Chief conversation with AppKit mouse events. It captures each surface before navigating. The message contains labeled and bare links to different runs, a deleted Thread and a malformed URL. The replay checks the destination filter, historical row, loaded content and top scroll position, plus the unavailable page for a missing run. During the one-minute expiry observation the window ignores physical desktop clicks. Pointer input is enabled again before the replay follows the saved link into a Super Thread that cites a newer run. `talk-links.json` identifies the source surface and execution for each visit. The catalog and reading data are fixtures in a private profile.

### Overview Bar swipe at actual size

```sh
python3 demos/moku-landing/verify_header.py --bar-swipe --output .build/overview-bar-swipe
```

This scenario keeps the workspace at 1× throughout, including its first frame.
It checks the empty Overview with folded input as well as the populated canvas.
The replay posts AppKit events to the window. A right-click opens the conversation in Overview, and a Control-click opens it on Landing. The replay checks filter swipes, native tag scrolling, camera travel, the return of the conversation draft to Compose, and gesture ownership while the editor or Settings is open. The replay installs a historical reminder operation and checks that Bar gestures stay available. The results are in `overview-bar-swipe.json` and `landing-bar-swipe.json`.

The [live conversation replay](verify_conversation.py) uses the same production window with the real Runtime, SQLite, Codex CLI and an isolated loopback model peer. Build the current artifacts and choose a new evidence directory.

```sh
python3 tools/e2e/build.py --go ./scripts/go.sh --with-app
python3 demos/moku-landing/verify_conversation.py --output .build/chief-conversation
```

Run the same command with `--send-refresh` and a fresh output directory to exercise delayed sends. The replay holds its private Runtime during Return and during a compact send followed immediately by a right-click. The window checks outgoing accessibility rows with admission held, after receipt, and after the loopback peer releases Talk. A temporarily unavailable staged file exercises draft restoration and an explicit retry. After Escape the replay waits for the folded Compose button to settle under the pointer, then opens it with one click. The window measures bottom following as the first user bubble appears, then scrolls back and compares the reading offset across the delayed replies. The final public page checks the persisted row count, text, attachment names and identities.

The first native visit of the layout and restart replay checks previously submitted messages and keyboard focus, types a Chinese message that wraps in the mounted editor, stages a PNG from disk and sends with Return. It observes the accepted text and filename, two consecutive Talk replies, and the unsent draft after closing and reopening. A second App and Runtime process reopen the same profile. Both visits compare ordered accessibility labels, individual dates and public content reads. Window screenshots show the resting bubbles and the transcript during a held left swipe in dark and light appearances. The replay checks the reading position and inspects the right edge for individual times. Escape dismisses the panel with its draft intact.

The replay uses a 1100×800-point window and the application minimum of 860×600. Before sending, it measures the space above the date and below the last bubble in a two-message conversation at both sizes. Each visit then measures a longer exchange with one-line and four-line drafts in both windows. In the smaller window it scrolls the messages above the draft. The send and restart JSON receipts record the window margins, panel, list and editor heights, the attachment bubble’s height and the gaps for both a speaker change and consecutive replies. The `conversation-small-*.png` captures show the compact window with each draft. Text recognition checks that the latest reply and the draft’s last line are both visible in the four-line capture.

The Bar swipe scenario also opens cached conversation pages in the production Dock. It crosses midnight and a 15-minute gap, captures the three centered date headings in `conversation-periods.png` and clicks both page controls. On the longer page it scrolls up, holds a left swipe and checks that the transcript stays in place and the right edge shows no individual times. The vertical reading position must hold both through the gesture and when the window becomes shorter. These replays use window-addressed AppKit events. Physical trackpad hardware and a remote model service have separate evidence boundaries.

Use `--status-only` in place of `--bar-swipe` to run the mixed catalog scenario
independently. It mounts the [production Overview](../../app/macos/Sources/Host/Overview/README.md)
with ordinary tasks, running interactions, completed work and eight reports.
`overview-status.json` records the selected scope, tag and status, card area,
mounted Agent cards and individual or collected report members at each step.

Window-addressed AppKit gestures from both halves traverse one left column.
The mixed-catalog replay steps through the folder's semantic tags and the final
Running tag, including a switch from a tag with no running tasks to running
work elsewhere in the folder. On the three-choice rail (Development, Shipping,
Running), a finger swipe down from Development selects Running, a swipe up
returns to Development, and another swipe up selects Shipping. The replay
posts non-inverted events to the window and delivers inverted samples to its
mounted scroll monitor. Each `rail-swipe` entry records finger direction,
inversion, signed recognition delta, rail order and observed start and end IDs. It also records the signed vertical travel of
entering and retiring cards from their mounted canvas motion endpoints.
The replay checks that further contact and momentum events keep the same selection, and
swipes between a folder’s sole semantic tag and Running, and checks an empty rail. It also checks
cross-center contacts, inverted device deltas, horizontal camera travel, live
status changes, and reentry to a folder with an empty Running selection.
A replayed catalog delta moves a semantic tag into first place while a semantic
tag named Running and the built-in choice retain distinct identities. A live
update to that replayed Thread preserves Running. A newly created Thread with
the same tag selects its semantic filter.
In macOS full screen it swipes on both empty margins and a running card.

Selecting a top-row Inbox tag mounts Running, All statuses and Completed on the
left. The replay checks their order, wheel wraparound in both directions, window positions, tag-scoped cards and
state on entry. It distinguishes an Inbox tag named Inbox from a real directory
of the same name. It removes and assigns tags while checking retained reader
and catalog state. With the fixture catalog visible while the workspace model
is still synchronizing, the replay checks that the Runtime status banner is
absent from the window's accessibility tree and clicks the top-row Inbox tag.
The fixture supplies catalog data directly and exercises mounted presentation
and input without a live Runtime reconnect.

At the 860 × 600 pt minimum, five semantic tags and the built-in Running button
fit in one column. The replay measures their accessible frames, clicks a button
over a card and opens a card through a gap. It checks the long semantic label's
hover, truncation, tint and pointer exit, then clicks the expanded hourglass title
and verifies that only Running is selected. With `--capture`, the run writes
`folder-running-zh.png`, full-screen window captures, and a movie of filter changes.

Window captures show [Running below five folder tags](evidence/overview-left-filters/folder-running.png),
[a folder with no running work](evidence/overview-left-filters/folder-running-empty.png),
[Completed for an Inbox tag](evidence/overview-left-filters/inbox-completed.png), and
[Running after a swipe from the right edge in full screen](evidence/overview-left-filters/fullscreen-running.png).

The Inbox portion checks both empty illustrations, their text, and the 195 × 85 pt
image bounds and bowl alignment. It compares the completed card's model, excerpt,
duration, usage, completion badge and vertical spacing in All statuses and
Completed in English and Chinese. The fixtures use the production workspace with
an isolated catalog. Physical trackpad hardware and model services are outside
this replay.

To exercise the completed card layout and write `overview-completed-card.json`,
run the status replay through both localized card comparisons:

```sh
python3 demos/moku-landing/verify_header.py --completed-card --output .build/completed-card-layout
```

### Chief Bar opening

```sh
xcrun swift build --package-path app/macos
python3 demos/moku-landing/verify_header.py --conversation-opening --output .build/chief-bar-opening
```

The replay opens the production Chief Bar with phased AppKit scroll events
and momentum. It checks the first visit with cached history, reopening after
the first nonempty page arrives late, and right-clicking the compact bar.
The last bubble is longer than the viewport. The replay measures the native
clip against the document bottom and saves its window-relative bounds with
each capture. Vision checks the final line against those bounds after recording,
outside the input and animation sequence. A new contact scrolls back, then a
content revision and window shrink must preserve the native vertical offset.
Scrolling to the beginning must reveal the first message. The earlier and newer
page controls must reach the preceding page and return to the newest reply.

`conversation-opening.mp4` records the opening and outside-click dismissal.
The compact-editor visit includes a two-second reading pause before dismissal.
Inspect consecutive frames for both eyes staying inside the bottom row as they
blink and travel between the center and editor seats. The replay also interrupts an opening with an outside click and swipes again
as soon as the editor finishes folding. Check intermediate eye positions and a clear composer on
each visit. The reopened viewport must show the final line.
`source.json` binds the run to the source and `conversation-opening.json`
records the scroll measurements. The fixture uses cached pages and delivers
deterministic revisions through the client event stream. The event and
recording checks cover the mounted workspace on macOS.

For the opening measurements, use a fresh output directory for each run.
The runner builds the current Release modules with testable imports under the
shared performance and desktop leases before linking the collector.

```sh
python3 demos/moku-landing/verify_header.py --conversation-performance --output .build/bar-timings
python3 demos/moku-landing/verify_header.py --conversation-performance --profile-opening --output .build/bar-profile
```

Each run opens a full cached page five times from the collapsed Bar in one
isolated workspace. ScreenCaptureKit timestamps the displayed window frames.
The clock starts before the first upward scroll event. The collector compares
each frame with the resting Bar and the final line of the settled reply, which
Vision locates after capture. It records the longest visible pause in the
sampled area and intervals between main run-loop ticks. The separate profile
samples the first visit at 1 ms intervals. The [same-machine comparison](evidence/conversation-opening/measurements.md)
includes the workload, per-visit results and retained samples.

The header replay mounts the 46.2-point production filters at the top of a
real window in Aqua and Dark Aqua. The initial selection is the Chief folder
with an unread count of 8. Beside it is the Inbox tag **🔵 Blue** with an
unread count of 3.

```sh
python3 demos/moku-landing/verify_header.py --header-glass --output .build/overview-header-glass
```

Each appearance produces a 618 × 174-pixel crop at 2× and a second crop with
3-point stripes behind the controls. The replay checks the mounted filter heights and single-line labels. It reads the folder and tag labels and both badge
numerals, checks the unread badge color, and compares
texture variation inside the glass with the exposed backdrop. It samples
adjacent pixels at the lower and trailing edges of the header viewport to
catch a hard cut through the shadow. `header-glass.json` records those
measurements, the title's luminance difference from the chip face and the
spacing between adjacent controls. On fixed neutral backgrounds it clicks
each top and side control and compares the same part of its glass face across
selections, away from the glyph, badge and rim. The top folder shifts toward
the muted gold accent. The selected top-level Inbox tag takes its blue tint
from 🔵. The folder rail checks warm, blue and green semantic emoji tints
and the hourglass. The Inbox rail checks warm tints for the hourglass and file
dividers and a neutral tint for the checkered flag. The selected controls must retain the
same emoji ink as their unselected counterparts.

`--rail-hover` mounts three Chinese semantic tags on a neutral gray
background in an active, isolated window. The replay requests 60 Hz and
retains every complete WindowServer frame delivered through hover,
transfer and reversal. It tracks the red badge and glass edge as the capsule moves, checks the two four-character titles against native
CJK text width and checks truncation of a longer title. The captured
intervals bound the observed transition without measuring hardware
refresh rate. This option can run alongside `--header-glass` in one command.
