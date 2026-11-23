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
The Note swipe cases post window-addressed pixel scrolls to the replay app's
AppKit event queue over the background, a card, the overflowing filter scroller
and Chief Bar. They check the opening generation, threshold, direct and momentum
tails, downward and modified input, native tag and Note scrolling, camera travel
and composer/Settings ownership. Their receipt is `overview-note-swipe.json`.
An additional sample exercises inverted device deltas at the mounted handler.
The reader case also checks that a fresh upward gesture leaves Note closed.
The camera geometry cases send samples directly to the mounted AppKit monitor.
Physical trackpad delivery and system fullscreen need separate observation.

The Note swipe replay also routes real window-addressed scroll events through an offscreen workspace with a pending long reminder. Two points of the panel remain on the display for WindowServer composition. The replay checks that the reminder viewport stays entirely outside all displays. Its body scrolls independently, an upward swipe on the exposed canvas opens Note, and only an explicit receipt advances the reminder. See `reminder-note-ownership.json`.
