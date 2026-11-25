# Opening Chief conversation history from Overview

The mounted Release replay posts a window-addressed AppKit right mouse-down to the collapsed Chief Bar. The Overview input monitor also accepts Control-click. It checks the registered Bar bounds and workspace admission, then opens the conversation and requests composer focus. The Dock mounts the latest-page subscription and the window’s draft editor. The timeline fits its last six bubbles and bottom inset exactly so the last line stays in view.

## Measurement

Each fresh workspace contains 18 task cards and a local reading-cache page with 64 alternating multiline messages (26,460 encoded bytes). The last reply exceeds the viewport. Each process performs one first open and four reopens, with an outside click and 650 ms for dismissal between visits. First open starts in an already mounted Overview. The benchmark excludes app launch, live Runtime delivery, model execution, and physical pointer latency.

All visits use an Apple M1 Pro, macOS 26.5.1 (25F80), Swift 6.3.2 and optimized production modules with testable imports. The dark 1100 × 800 pt window uses a 2× display at up to 60 Hz with Reduce Motion and Reduce Transparency off. Each run uses the shared desktop and performance locks. Observations start immediately before the replay posts the click.

- **Response** is the first changed ScreenCaptureKit frame in the lower central 720 × 200 pt region, excluding the resting eyes.
- **Input ready** is the first 120 Hz main-loop probe that sees an editable, non-hidden NSTextView as the key window’s first responder. Busy main-loop intervals delay the observation. This measures keyboard admission and can precede the editor ink becoming fully visible.
- **Latest line readable** requires the displayed pixels to match at least 90% of the settled final line’s bright-pixel mask at its final position. Vision locates the line after capture. Each visit requires a stable idle reference and a readable final frame.
- **Visual hold** is the longest interval without visible progress from first response through readability. All timings are milliseconds. The comparison has no calibrated pass budget.

## Same-machine results

Two independent processes per version each contributed one first open and four reopens. The table gives the median of two first opens and the pooled median of eight reopens. Baseline is `f52d3289`, candidate is `eb368bb6`. All twenty timing visits passed the idle and final-line controls.

| From right mouse-down (ms) | First, baseline | First, candidate | Reopen, baseline | Reopen, candidate |
| --- | ---: | ---: | ---: | ---: |
| First visible response | 140.7 | 94.0 | 103.3 | 105.3 |
| Editable first responder | 102.3 | 60.8 | 79.5 | 76.2 |
| Latest line readable | 335.2 | 330.3 | 216.1 | 215.7 |
| Longest visual hold | 95.2 | 66.2 | 69.6 | 52.9 |
| Longest main-loop interval | 102.7 | 70.4 | 75.8 | 77.6 |

Both first opens admitted input earlier (108 and 97 ms on baseline, 56 and 66 ms on candidate) and responded visibly earlier. The longest visible hold also fell on each first open and across reopens. Final-line timing varied substantially on first open (345 and 326 ms on baseline, 293 and 367 ms on candidate). These samples establish no consistent improvement in time to the settled latest line or in reopen input latency.

`chat-baseline` and `chat-baseline-repeat` are the unprofiled baseline. `chat-fit` and `chat-fit-repeat` are the unprofiled final implementation. All four have identical fixture and collector source hashes and identical window and accessibility configuration. The archive also identifies the separate diagnostic profile, the failed one-row trial and the intermediate editor-only preparation run (which already deferred hidden time labels). Those runs are outside the table. [Per-visit frame samples, input times and build identities](secondary-click-samples.json.gz)

## Diagnosis and reading position

A separate one-second first-open profile on baseline `f52d3289c9f74d4126d38c2bcee01075a1144023` used the same fixture and a requested 1 ms sample interval. Of 383 main-thread samples, 138 included hosting-view layout, 54 included size fitting, 70 included Core Graphics shading and one included conversation-page decoding. These counts overlap and include other workspace rendering. They locate costs in the cached-page workload. [Main-thread sample](secondary-click-main-thread.txt.gz)

A trial with one exact trailing bubble (`91053024b1ea4faf39a03e6c2e239eaa52506a56`) failed on visit three. The capture lacked the final reply line and AppKit measured 99.5 pt below the clip. Its incomplete observations are excluded from the timing comparison. The delivered timeline retains six exact trailing rows. [Failed third-visit capture](secondary-click-trial-failure.png)


## Implementation and verification

The active Overview prepares one disabled plain editor at its expanded width. Opening the Bar enables it and applies the existing visit-scoped focus request. This moves some native text-system work into the idle Bar. Time to initial Overview and the resident editor’s memory cost were outside the measurement. The first visible response can be movement of the shell while the history is loading. Drafts with attachments and directories keep their demand-loaded editor. The visit still owns its history subscription, page cursor and scroll state.

While the shell starts widening, a cached page can already report a minimum height from the sum of its bubble insets. A full page reaches the existing height cap without first sizing a progress indicator. Short pages still fit their measured content. Each row reserves the timestamp column’s width and lays out its time label when the reader reveals it. Shell animation durations and horizontal travel follow the existing Dock implementation.

The production source tested is `eb368bb63bcf480c9cd3626f347324773731b35f`. The Release and Debug build receipts agree on production source SHA-256 `8deadb12f17414b6a8160d846362aeb6847103e5492491b3d18445ed3e134a5b`. The timing fixture links Release production modules. The interaction fixture links Debug production modules. Reproduce with the opening commands in the [replay guide](../../README.md#chief-bar-opening).

- `python3 demos/moku-landing/verify_header.py --conversation-opening --output .build/chat-fit-reading` passed. The first visit, delayed page, entry from Compose and interrupted reopen each showed the last reply line at a zero-point bottom gap. The 240 pt scroll back held its 3,283 pt reading position through a new reply and a shorter window. Both page controls reached their destinations.
- `python3 tools/e2e/build.py --go ./scripts/go.sh --with-app` built Chief with Swift warnings as errors and the Go Runtime. The first Debug build of the discarded one-row trial stopped when its sources changed. The final build completed on fixed sources.
- `python3 demos/moku-landing/verify_conversation.py --output .build/chat-fit-live` passed with a private SQLite Runtime, native Codex CLI and a loopback model peer. The editor acquired focus, sent a wrapping Chinese message with an attachment, and retained the next draft through Escape and reopening. App and Runtime restart recovered all five ordered messages. The short page, timestamp reveal, regular and minimum windows and taller draft passed the layout checks.
- `python3 demos/moku-landing/verify_conversation.py --send-refresh --output .build/chat-fit-send` passed. Both panel and compact sends appeared during delayed admission. A rejected attachment send restored the draft for retry, and the persisted conversation contained six distinct rows. [Mounted interaction receipts](secondary-click-interactions.json.gz)

The first combined `--bar-swipe` replay stopped after dismissing the conversation. A horizontal wheel event at window point (648, 8) was assigned to a native responder, leaving the canvas at 0 of 1,228 pt. A diagnostic replay of the same sequence on the same build observed the Overview hosting view at that point, no registered scroll exclusion, no pressed mouse buttons and a folded Bar clear of the point. Its pan moved the camera, a primary click restored the conversation draft in Compose, and Control-click opened the Landing conversation. The unmodified runner also completed the full sequence on its next run (`--bar-swipe --output .build/chat-fit-controls-recheck`). The original event’s native hit target remains unknown. [Failure, diagnostic and repeat receipts](secondary-click-interactions.json.gz)
