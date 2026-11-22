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
a temporary fixture catalog. It starts at 5×, checks 1100pt and 600pt windows
at actual size, visits 1.44× and 2.5×, and returns to 5× at two window heights.
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
while a task enters and leaves a wide window, as the width crosses the three-column
boundary, when scrolling remains necessary, and when the window grows again.
With `--keyboard`, the replay scrolls a column with each arrow key and opens the
focused card with Return. It records both distances and the card identity in
`overview-keyboard.json`. Optional captures show the isolated workspace.
Wheel samples enter the mounted AppKit monitor. Pointer events go through the
window. Physical trackpad delivery and system fullscreen need separate observation.
