# Chief Bar transition recordings

A nonactivating window mounted the production Dock on macOS 26.5.1 (25F80),
arm64. ScreenCaptureKit recorded the preview process's own window. The
warnings-as-errors Debug build and mounted replays used revision
`b35c8f197fb41e87a1a1ef2a83a87fc5ad1d6ffd`. The product source tree was
`df1f1cc5ec227ab0d25322338eba7b907f7ae272`. The manifest identifies the
executables, collectors and individual artifacts. [Capture manifest](capture.json)

| Recording | Observed result |
| --- | --- |
| [Send, Stop and dispatch](normal/window.mp4) · [Consecutive action frames](normal/contact.png) | 244 frames. The first character changes Stop to Send. Further typing keeps the shell at its expanded width and the Send glyph steady. Clearing the draft about 55 ms into another reveal reverses it at 53% of the measured glyph change. Dispatch status and configuration fade out and in without readable overlap. |
| [Reduce Motion](reduced/window.mp4) | 240 frames. The same inputs switch the glyph and dispatch text directly under the local SwiftUI accessibility override. The native editor keeps its responder. |
| [Overview folds and interrupted return](overview/window.mp4) | 332 frames. The largest single width change was 87 pt and the maximum center error was 0.5 pt. The visible Stop center stayed 22.75–28.5 pt from the edge. Both eyes could be localized in 330 frames. |
| [Mounted routes](route-contact.jpg) · [Measurements and event receipts](observations.json.gz) | Ordinary and reduced-motion visits covered permission, questions, interrupted withdrawal, Talk, Note, Settings and timers. Timer retries preserved the outstanding receipt. Tool projections and 187 orbit samples covered consecutive updates. Agent and wide/narrow Report visits exercised reader entry and return. Native text replays covered the 32 pt click and AXPress target, marked text, attachments, same-event-stack Return and draft recovery. |

Downsampling obscured the white eye cores during a blink and rounded away a
corner of the fading Stop. Native-scale measurement resolved the eyes in
frames 109, 112 and 113 and the Stop in frame 299. Two frames at peak blink
still have no measurable pair. The geometry check includes all 332 frames.
[Blink frames](overview/blink.png) · [Stop frame](overview/stop.png)

The same-event-stack replay exposed a Return ignored immediately after receipt
settlement. The passing run submitted the following draft before redraw and
checked duplicate input and restored text. Projection inputs were deterministic.
The first-run handoff, system pointer and VoiceOver focus, Collection and Browser
annotation have source-level coverage here. Full-workspace recordings of those
paths, a live Harness and calibrated interaction latency are outside this capture.
[Route and property map](../../../../app/macos/Sources/Host/MokuScene/README.md#state-and-transition-map)

## Recheck the evidence

From the repository root, with FFmpeg, ffprobe, Python, NumPy and OpenCV:

```sh
replay=demos/moku-panel-transition
evidence="$replay/evidence/state-ink"
python3 "$replay/check_control_ink.py" "$evidence/normal" /tmp/chief-bar-normal.json
python3 "$replay/check_control_ink.py" "$evidence/reduced" /tmp/chief-bar-reduced.json
python3 "$replay/check_overview.py" "$evidence/overview"
```

The build used `xcrun swift build --package-path app/macos --product Chief --only-use-versions-from-resolved-file -Xswiftc -warnings-as-errors`.
The preview ran `--capture-overview --english --control-ink` with and without
`--reduced-motion`, `--capture-overview`, `--replay-chief-input --verify-actions`,
`--replay-send`, `--capture-agent-entrance` and `--capture-collapse` at ordinary
and narrow widths. The remaining mounted visits used the following command on
the recorded revision above.
[Capture instructions](../../README.md#control-ink-recording)

```sh
python3 demos/moku-panel-transition/remaining/run.py .build/bar-visits-verified routes routes-reduced timers timers-reduced tool-feedback orbit-fade
```
