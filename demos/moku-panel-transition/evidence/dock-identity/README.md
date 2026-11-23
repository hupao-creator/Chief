# Dock identity on entry from Overview

Two fresh running-Thread visits on macOS 26.5.1 kept the eyes and the Codex mark inside the glass, starting from the wide **Thread started** notification. The tested production source was `edf07339d8baea52087b7cca0559f18bd03b4bc9`. The independent recording of `3ccd87359ce4ae3fd11dbb2e1a1bf7fb33249e68` reproduced a detached logo under the same entry condition. [Frame comparison](comparison.png) · [Dock contract](../../../../app/macos/Sources/Host/MokuScene/README.md#dock-and-composer)

| Source and entry | Whole-window recording | Positions by frame | Frames | Frames outside by more than 2 pt | Smallest measured clearance |
| --- | --- | --- | ---: | ---: | ---: |
| 3ccd8735, running Thread, dispatch visible | [Before](before.mp4) | [CSV](before.csv) | 246 | 17 | −179.89 pt |
| 73fb5444, running Thread, dispatch visible | [Intermediate build](handoff.mp4) | [CSV](handoff.csv) | 247 | 8 | −55.26 pt |
| edf07339, running Thread, dispatch visible | [Open and close](dispatch.mp4) | [CSV](dispatch.csv) | 251 | 0 | 7 pt |
| edf07339, same case in a fresh profile | [Repeat](repeat.mp4) | [CSV](repeat.csv) | 270 | 0 | 6 pt |
| edf07339, completed Thread, compact Dock | [Open and close](completed.mp4) | [CSV](completed.csv) | 262 | 0 | 7 pt |
| edf07339, Close during expansion, then reopen | [Rapid reversal](reverse.mp4) | [CSV](reverse.csv) | 511 | 0 | 6 pt |
| edf07339, explicit Overview composer click, outside click | [Overview input](overview.mp4) | [CSV](overview.csv) | 177 | 0 | 10 pt |

### System interaction

Each session used the built Chief executable in a unique application bundle and an isolated Runtime profile, CLI home and temporary directory. The project desktop lease covered setup, window interaction and teardown. The installed Codex CLI communicated with a deterministic loopback peer. In the dispatch case, the application was already mounted when the Runtime created two Threads. The peer held the executions open. System accessibility reported **Thread 已启动** in the 400 × 58 pt capsule before entry, a centered 560 × 58 pt capsule with a native editor and Stop after opening, and the selected Thread matched the clicked card. The independently recorded completed Thread began with a 168 × 44 pt idle capsule. [Process, AX, build and cleanup receipts](receipts.json)

The driver located the right-hand card in the AX tree, verified that the frontmost application and the AX element at the click point belonged to the isolated PID, then posted mouse move, down and up through the system HID event tap. The reader's upper-left Close received the same input. Clicks landed at screen points (1210.5, 588.5) and (206, 114) in a window at (100, 26). The UI socket supplied snapshots only. ScreenCaptureKit recorded that PID's entire 3770 × 2250 window with the cursor hidden. The bundled executable's SHA-256 matched the build receipt and the executable at the path reported by the running process. [Receipts](receipts.json)

For the reversal, Close was clicked as soon as the reader reported its input open. The observed glass width reached 509 pt at 2.433 s, folded to the compact seat, and reached 553 pt on the subsequent settled visit. These widths come from the visible dark cap. AX measures the full 560 pt editor. In the explicit composer case the system click targeted **打开 Chief 输入框**, AX exposed the expanded editor, and a click on the blank canvas returned it to idle. [Reversal measurements](reverse.csv) · [Composer measurements](overview.csv)

### Checking the detector

The positive control was the user's original full-display recording, identified by SHA-256 in the receipts. At 2.067 s the eye pair center was (666, 745.5) and the top of the glass was at y = 1059. At 3.083 s the Codex mark center was at x = 745 while the glass began at x = 878. At 5.550 s the returning logo center was (522.5, 562), far above the bottom capsule. These examples were checked against decoded pixels. The reference CSV retains all candidates, including toolbar glyphs that resemble eyes. The comparison includes cropped ink from the user's movie. [Reference positions](reference.csv) · [Frame comparison](comparison.png)

The same detector found the logo at its final x position in frame 110 of the new 3ccd8735 movie while the shell was still compact. A separate instrumented run showed the editor correcting its vertical inset about 19 ms after the mark started moving, with the horizontal animation still registered and a zero presented translation. The first correction preserved the horizontal track. Its own dispatch recording then exposed eyes to the left of the contracting notification in frames 50–57. The final build kept the Overview shell and its clipped eyes together through reading admission. [Logo failure](before.mp4) · [Eye failure](handoff.mp4)

Decode in presentation order, halve both dimensions and search the full workspace for isolated neutral eye pairs and purple Codex silhouettes. The original recording uses an additional workspace crop. Coordinates are half-resolution pixels, equivalent to points on the isolated app's 2× capture. The dark upper cap supplies the horizontal glass span. A downward luminance edge across the central half of the cap locates the bottom rim. Taking the median of the individual column edges distinguishes the common rim from the dispatch text baseline. Clearance is the smallest signed inward distance of the four detected ink-box corners to this estimated capsule. The two-point threshold follows the centered return replay. [Measurement script](measure.py) · [Replay criteria](../../README.md#agent-entrance-replay)

The five final movies contain 1,471 encoded frames. The detector located the glass in every frame and measured mark bounds in 1,448. All 23 unresolved frames are indexed and shown below. Visual review found blinking, angled or nearly edge-on marks inside the capsule. The numeric minima in the table use only localized ink. The evidence covers displayed frames on this dark, Chinese-language Retina workspace. It measures neither unsampled compositor frames nor animation performance. [All unresolved frames](unresolved.png)

The measurement uses Python, OpenCV, NumPy and ffprobe.

```sh
python3 measure.py dispatch.mp4 /tmp/dispatch-positions.csv
python3 measure.py "/path/to/the/original.mov" /tmp/reference-positions.csv --reference
```

The actual build commands, driver commands, input events, recording IDs, executable digests and isolated paths are in the receipts. The production build used `python3 tools/e2e/build.py --go ./scripts/go.sh --with-app`. An initial pre-admission Escape probe on 3ccd8735 left the reader open. Its attempt log is retained locally. The reversal result above comes from clicking the visible Close control during a measured expansion. An earlier final-build attempt lost foreground ownership before its first click and the input guard stopped it. The runner reacquired the target and completed a fresh recorded visit. The driver also attempted a pair of Compose shortcuts at the end of the reversal movie. Only the mouse-driven reversal has a measured intermediate width. [Run receipts](receipts.json)

### Adjacent preview replay

The standalone Agent entrance preview also ran against the `edf07339` production objects. In its first run the draft survived closing, but the queued Talk was absent at the visibility checkpoint. A diagnostic run kept the same assertions and added fixture observations around Talk publication and closing. It saw the retained draft and the queued message in a 560 × 58 pt shell after closing. All of its frame checks passed. The cause of the first Talk failure remains undetermined. [First run](preview-failure.json) · [Diagnostic observations](preview-diagnostic.json) · [Diagnostic frame checks](preview-frames.json)
