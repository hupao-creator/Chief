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
the visit from the matching tag, and opens
the owning Super Thread in a different directory. The Report cites a later
run of the same task. `note-links.json` records the filter during dismissal,
location and reading, the mounted reader, and the requested execution and entry
position. For ordinary Threads it also checks the loaded historical row and
its scroll position against an offline two-run fixture. System-wide accessibility
activation and live Report content use the [product replay](../../tools/e2e/README.md#chief-note-execution-link).

### Overview Note swipe at actual size

```sh
python3 demos/moku-landing/verify_header.py --note-swipe --output .build/overview-note-swipe
```

This scenario keeps the workspace at 1× throughout, including its first frame.
It checks the empty Overview with folded input as well as the populated canvas.
The replay posts window-addressed, phased pixel scrolls over the background, a card, the overflowing tag bar and Chief Bar. It checks the Note threshold and hit region, direct and momentum tails, native tag and Note scrolling, camera travel, composer/Settings ownership and inverted device deltas. The reader and landing cases check Note ownership on their respective surfaces. See `overview-note-swipe.json` and `landing-note-swipe.json`.

Use `--status-only` in place of `--note-swipe` to run the mixed catalog scenario
independently. It mounts the [production Overview](../../app/macos/Sources/Host/Overview/README.md)
with ordinary tasks, running interactions, completed work and eight reports.
`overview-status.json` records the selected scope, tag and status, card area,
mounted Agent cards and individual or collected report members at each step.

The right-half gesture traverses Running only, All statuses and Completed only.
The left-half gesture enters the first semantic tag from the directory and then traverses the visible tags. Each side
checks a contact that crosses the midpoint before recognition, the endpoints
and momentum. The replay selects a top-level Inbox tag and checks its exact
cards, restored All statuses and absence of a left column. It distinguishes a top-row
tag named Inbox from a real directory named Inbox. Entering a directory with
two visible tags selects its first tag, and clicking that directory again shows
all its tagged cards. It opens the sole tagged
card and removes its tag through a catalog delta while the reader is open.
The selection clears while the covered canvas retains its old scene. Returning
to Overview shows an empty canvas with no filter controls. Both untagged
Threads remain in the catalog. The replay compares the measured heights of the
top directory and Inbox chips with the left tag and right status chips.
Window-local mouse clicks select
the middle status and a semantic tag. Changing child or status retains the
full-window card area within the directory. A capsule over a card accepts the click, and a click in the gap between two capsules opens the underlying task. At the production minimum of
860 × 600 pt, a five-tag directory exposes five semantic controls and selects a tag
with a long label. The replay reads the mounted accessible buttons to check
their names and frames. The selected tag and status stay expanded beyond five seconds. The replay places the cursor 10 points beyond the compact left tag and right status button, then moves it away
to check hover and exit, then restores the cursor. A click in the horizontal hover margin of the compact
tag opens the card underneath. The same click on its expanded title selects
the tag. With `--capture`, the cropped columns are checked for the expected
visible tag and status titles. At the right edge the replay checks that the
hourglass expands left on hover, a click on its title selects Running only,
the title stays open on pointer exit and a swipe selects and expands All statuses. With capture enabled, `filter-switches.mp4` records the window through status and tag swipes between a grid and a single card. Captures read the hourglass title in English and Chinese. The hovered
tag title is read in Aqua and Dark Aqua and with a bright backdrop behind dark-appearance glass.
Samples from inside each capsule show its glass tint changing with the
selection on both rails and the top row. `source.json` records the checkout revision,
source changes, macOS version and architecture. While the Runtime notice is
visible, the replay measures the gap below the folder and Inbox buttons and
uses window-local clicks to select both kinds of top filter.

With Shipping selected, a catalog update admits and removes a card in each
status filter. Line-wheel events on the right return to All statuses from
either empty filter. A left-side line-wheel event keeps the empty Running
selection. Both empty states use a 195 × 85 pt illustration. The replay checks
that the full image fits inside the content area and its bowl center is within
1 pt of the content centerline. With `--capture`, the replay reads both localized
empty titles and the completed task's timestamp, and verifies the absence of
scroll hints in both empty states. The `running-empty-*.png` and
`completed-empty-*.png` captures show both states in Aqua and Dark Aqua.
`sleeping-skillet.mp4` spans a full sleep animation cycle when motion is enabled.
It does not exercise a hardware trackpad or system fullscreen.
The fixture has no Runtime connection.

A second workspace presents a long reminder outside the display with two points of the panel on screen for WindowServer composition. Its message body scrolls independently, the exposed canvas switches status, and an explicit receipt advances the reminder. See `reminder-note-ownership.json`.

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
from 🔵. The left rail checks warm, blue and green semantic emoji tints.
Blue and green semantic emoji
have distinct tints, the hourglass and dividers have warm tints and the
checkered flag has a neutral tint. The selected controls must retain the
same emoji ink as their unselected counterparts.

`--rail-hover` mounts three Chinese semantic tags on a neutral gray
background in an active, isolated window. The replay requests 60 Hz and
retains every complete WindowServer frame delivered through hover,
transfer and reversal. It tracks the red badge and glass edge as the capsule moves, checks the two four-character titles against native
CJK text width and checks truncation of a longer title. The captured
intervals bound the observed transition without measuring hardware
refresh rate. This option can run alongside `--header-glass` in one command.
