# Chief Bar face and orbit recordings

The isolated windows ran the native sources at `a4c478899b6e3da8b46aac051ec7b125e4bc2a4b` on macOS 26.5.1, arm64, at 2× backing scale. The Report workspace used a private runtime profile and a deterministic provider. The orbit window mounted the production Dock and supplied execution changes through its catalog. Both used ScreenCaptureKit current-process capture. [Build and capture identities](capture.json)

## Report source conversation

Selecting a source execution takes the compact bar to the right column, turns the eyes into the Codex mark and admits the editor. Close withdraws the Report execution preference during the panel return. The mark stays in the resident Dock as the input and column change ownership. The independent turn continues through the edge while the shell contracts.

The comparison aligns the first measurable incoming face in each direction. Each close-up and its wider view come from the same encoded frame. The first pass plays at normal speed and the second at quarter speed. The full-window movie also includes an interrupted Close, reopening and a second Close. [Comparison](compare.mp4) · [Full Report window](identity/window.mp4) · [Reduce Motion window](identity-reduced/window.mp4)

| Visible phase | Opening | Closing |
| --- | ---: | ---: |
| Eyes between the thin projection and 94% of the local full height | 138 ms | 142 ms |
| Logo between the thin projection and 94% of the local full height | 158 ms | 153 ms |

The measured intervals use the actual movie timestamps. The nominal full turn takes 420 ms. At the return edge the observed shell was 547 px wide, between its wide and compact endpoints. Nine distinct tilted logo heights and seven tilted eye heights were visible on return. The normal visit contained 626 frames. The reduced-motion visit contained 223 frames and switched between compact and expanded widths directly. [Normal frame measurements](identity/frames.csv) · [Normal result](identity/check.json) · [Reduced-motion result](identity-reduced/check.json)

The baseline normal Report visit at `7657594009f4acbecb2cad24872124bee4adb33c` yielded 68 ms of tilted logo and 73 ms of revealing eyes by the same measurement. Its separate reduced-motion process failed the foreground-preservation check. Only the normal baseline visit contributes to the comparison. The user recording showed a clear logo at 6.633 s and nearly full eyes at 6.667 s. [Baseline measurements](baseline-report-check.json)

## Running eyes

The opening comparison uses the archived Overview window and the corresponding stretch of the contour in the current recording. In the archived frames 0–28 the cluster centre moved from (578, 476) to (595, 375) px while the eye centre stayed at (720, 428) px. The rest of the movie shows the current window crop at normal speed through startup, tool replacement, pause, resume, interrupted retirement and rapid editor changes. [Orbit comparison and replay](orbit.mp4) · [Current full window](orbit-gaze/window.mp4) · [Archived full window](../state-ink/overview/window.mp4)

In the current recording, eye and dot cluster positions correlated at 0.983 horizontally and 0.979 vertically across the first settled lap interval. The 31 measured paused frames kept both positions within one pixel. Reopening the editor hid the dots. All 735 frames have measured counts, including partially visible dots and blinks. [Window measurements](orbit-gaze/positions.csv) · [Phase results](orbit-gaze/gaze.json) · [Event times](orbit-gaze/events.json)

See the [Report capture and checking commands](../../README.md#report-identity-flip) and [compact replay commands](../../remaining/README.md).

The ordinary Agent regression used a running successor in the Execution sidecard. Its first attempt recorded both legs and passed their frame checks, then failed the combined Overview handoff and foreground assertion. That attempt did not record which condition failed. A fresh isolated visit using the same production sources retained the draft on rapid reopening, returned the bar and draft to Overview and preserved the foreground application on both closes. The replay now reports the individual terminal observations on failure.
