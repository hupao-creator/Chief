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
phases, mouse wheel bounds and Settings input ownership. An 18-task fixture
also exercises blank-space drags and clicks, a mouse click on a newly reached
card, reader return, insertion and deletion. The drags start in the blank area
beyond the trailing and bottom card edges. The receipt `overview-scroll.json`
records the input point and the card frames. A directory selection reduces a
scrolled grid to four columns totaling 1328pt. At 1360pt the grid stays
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
### Overview Note swipe at actual size

```sh
python3 demos/moku-landing/verify_header.py --note-swipe --output .build/overview-note-swipe
```

This scenario keeps the workspace at 1× throughout, including its first frame.
It checks the empty Overview with folded input as well as the populated canvas.
The replay posts window-addressed, phased pixel scrolls over the background, a card, the overflowing tag bar and Chief Bar. It checks the Note threshold and hit region, direct and momentum tails, native tag and Note scrolling, camera travel, composer/Settings ownership and inverted device deltas. The reader and landing cases check Note ownership on their respective surfaces. See `overview-note-swipe.json` and `landing-note-swipe.json`.

The mixed catalog scenario checks mounted cards in all three status filters, both endpoints, individual and collected Super Threads, semantic tag selection with zero matches, and incremental changes to the same execution while filtered. `overview-status.json` records the visible tag identities, selected tag, ordinary cards and report members at each step. Add `--capture` to save the corresponding window images. Physical trackpad delivery and system fullscreen require separate observation.

Use `--status-only` in place of `--note-swipe` to run just the mixed catalog scenario.
With Shipping selected, a catalog update admits and removes a card in each status
filter. The replay measures the mounted skillet in both empty filters at
156 × 68 pt and sends window-addressed line-wheel events over both panels.
It also sends a phased upward swipe over the Completed panel. Both paths
return to all statuses with Shipping retained.

With `--capture`, the replay recognizes both empty titles and hints and the
Completed capsule, Agent name and completion time in English and Chinese
from the window images. It also checks empty text in Aqua and Dark Aqua.
These single-window captures do not sample desktop wallpapers or the system
accessibility tree.

The fixture runs without a Runtime connection, so its window shows the sync notice.

The [16-second walkthrough](evidence/overview-status/swipes.mp4) uses stills captured from the isolated production workspace. The [status receipt](evidence/overview-status/overview-status.json) records 12 steps, including selection of Shipping and its 0 → 1 → 0 running-card count. The Completed frame contains one Agent, two individual Reports and a six-member collection. The [gesture receipt](evidence/overview-status/overview-note-swipe.json) and [reminder receipt](evidence/overview-status/reminder-note-ownership.json) record the native scrolling checks. These artifacts come from the command above with `--capture` at application and replay revision `b9cc86a7cb7345470f65c1e147f0783639d7fe26`. The replay uses fixture catalog content and window-addressed AppKit events on Apple Silicon macOS 26.5.1.

A second workspace presents a long reminder outside the display with two points of the panel on screen for WindowServer composition. Its message body scrolls independently, the exposed canvas switches status, and an explicit receipt advances the reminder. See `reminder-note-ownership.json`.
