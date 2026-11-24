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

### Chief Note execution links

After building the current Debug package, run the mounted workspace replay.

```sh
python3 demos/moku-landing/verify_header.py --note-link --output .build/note-link-replay
```

A window-local mouse click on a Note citation opens an ordinary Thread from
another directory, switches between sibling tags in one directory, repeats
the visit from the matching tag, reveals a completed result from that folder’s
empty Running tag, and opens the owning Super Thread in a different directory. The Report cites a later
run of the same task. `note-links.json` records the filter during dismissal,
location and reading, the mounted reader, and the requested execution and entry
position. For ordinary Threads it also checks the loaded historical row and
its scroll position against an offline two-run fixture. System-wide accessibility
activation and live Report content use the [product replay](../../tools/e2e/README.md#chief-note-execution-link).

### Overview Note click at actual size

```sh
python3 demos/moku-landing/verify_header.py --note-click --output .build/overview-note-click
```

This scenario keeps the workspace at 1× throughout, including its first frame.
It checks the empty Overview with folded input as well as the populated canvas.
The replay posts window-addressed AppKit mouse events to the mounted workspace. It checks that right-click opens Chief Note once in Overview and that Control-click opens it on Landing. A click on the canvas leaves Note closed, an outside primary click dismisses an open Note, and a primary click on Chief Bar opens Compose. Phased pixel scrolls verify that a subthreshold contact stays on the Bar, an upward swipe opens the conversation with its editor, and its momentum leaves the filter and Note alone. A draft typed in the panel reappears in the compact editor. They also exercise filter swipes, native tag and Note scrolling, camera travel, composer and Settings ownership, and inverted device deltas. The reminder fixture checks native scrolling and acknowledgment. See `overview-note-click.json`, `landing-note-click.json` and `reminder-note-ownership.json`. The posted events cover AppKit delivery to the window. Physical trackpad configuration remains a system-input check.

The [live conversation replay](verify_conversation.py) uses the same production window with the real Runtime, SQLite, Codex CLI and an isolated loopback model peer. Build the current artifacts and choose a new evidence directory.

```sh
python3 tools/e2e/build.py --go ./scripts/go.sh --with-app
python3 demos/moku-landing/verify_conversation.py --output .build/chief-conversation
```

The first native visit checks previously submitted messages and keyboard focus, types a Chinese message that wraps in the mounted editor, stages a PNG from disk and sends with Return. It observes the accepted text and filename, two consecutive Talk replies, and the unsent draft after closing and reopening. A second App and Runtime process reopen the same profile. Both visits compare ordered accessibility labels, individual dates and public content reads. Window screenshots show the resting bubbles and a held left swipe in dark and light appearances. The corresponding MP4s record the timestamps appearing and retracting. Escape dismisses the panel with its draft intact.

Each visit measures native message, list and composer frames at 1100×800 points and at the application minimum of 860×600. At the smaller size it grows a one-line draft to four lines and scrolls the messages above it. The send and restart JSON receipts record the panel and editor heights, the attachment bubble’s height and the gaps for both a speaker change and consecutive replies. The `conversation-small-*.png` captures show the compact window with each draft. Text recognition checks that the latest reply and the draft’s last line are both visible in the four-line capture.

The Note-click scenario also opens cached conversation pages in the production Dock. It crosses midnight and a 15-minute gap, captures the three centered date headings in `conversation-periods.png` and clicks both page controls. On the longer page it scrolls up, reveals the times and verifies that releasing the gesture restores the horizontal origin. The vertical reading position must hold both through the gesture and when the window becomes shorter. These replays use window-addressed AppKit events. Physical trackpad hardware and a remote model service have separate evidence boundaries.

Use `--status-only` in place of `--note-click` to run the mixed catalog scenario
independently. It mounts the [production Overview](../../app/macos/Sources/Host/Overview/README.md)
with ordinary tasks, running interactions, completed work and eight reports.
`overview-status.json` records the selected scope, tag and status, card area,
mounted Agent cards and individual or collected report members at each step.

Window-addressed AppKit gestures from both halves traverse one left column.
The mixed-catalog replay steps through the folder's semantic tags and the final
Running tag, including a switch from a tag with no running tasks to running
work elsewhere in the folder. It checks endpoints, cross-center contacts,
system momentum, inverted device deltas, horizontal camera travel, live status
changes, and reentry to a folder whose sole left choice is empty Running.
A catalog delta moves a semantic tag into first place while a semantic tag
named Running and the last built-in choice retain distinct identities.
In macOS full screen it swipes on both empty margins and a running card.

Selecting a top-row Inbox tag mounts Running, All statuses and Completed on the
left. The replay checks their order, window positions, tag-scoped cards and
state on entry. It distinguishes an Inbox tag named Inbox from a real directory
of the same name. It removes and assigns tags while checking retained reader
and catalog state. A Runtime notice leaves top-row controls clickable.

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

A second workspace presents a long reminder outside the display with two points of the panel on screen for WindowServer composition. Its message body scrolls independently, the exposed canvas selects the Running tag, and an explicit receipt advances the reminder. See `reminder-note-ownership.json`.

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
