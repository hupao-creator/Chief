# Opening Chief history with execution links

The supplied 7.72-second recording shows two openings of the Chief Bar in Overview.
In each opening the bottom shell begins to widen, holds at an intermediate width,
then grows vertically and reveals replies with inline execution links. At 768 × 514
analysis resolution, the shell's left highlight on scanline 455 held its position
from 1.050 to 1.283 seconds and from 3.795 to 4.028 seconds. Each interval was
233 ms. The first frames with blue message bubbles were at 1.325 and 4.053
seconds. These times use the recording's presentation timestamps. The recording
contains no timestamp for the physical input. The sample archive retains the
scanline's leftmost pixel above gray level 45 between x = 230 and 380, with the
presentation time of each of the 402 frames.

## Reproduction

The [native input monitor](../../../../app/macos/Sources/Host/Overview/NativeOverviewScrollInput.swift)
handles a secondary click on the Bar, including Control-click. The scene opens the
editor and conversation together. The Dock mounts the newest page and subscribes
to its content. A ready page fits every message at its reading width so scrolling
can use the exact document height. Linked Chief replies also build TextKit
attachments. Each attachment used to mount an independent glass button even
when its message was many viewports away. This placed AppKit and SwiftUI layout
on the main thread during shell travel.

The [benchmark](../../README.md#chief-bar-opening) posts the secondary click in
an isolated Release workspace with 18 cards, then dismisses the conversation
with an outside click. The local cached page has 64 alternating messages,
28,749 encoded bytes and 31 links to a fixture Thread. Its final plain reply is
taller than the viewport. The recording shows several visible capsules and gives
no total page length. This synthetic workload isolates the cost of the older
links. No user profile or message content was copied into the replay.

## Displayed frames

The comparison uses an Apple M1 Pro, macOS 27.2.1, Swift 6.3.2, dark appearance,
an 1100 × 800 pt window, 2× scale and a reported 60 Hz display. Reduce Motion
and Reduce Transparency were off. Input and ScreenCaptureKit frame timestamps
use the host clock. The collector checks an idle optical control and uses Vision
to locate the final reply line after capture. Readability requires a 90% match to
its settled bright-pixel mask. A common-mode 120 Hz timer measures main run-loop
intervals. A visual hold begins at the first visible response, so a first frame
that already contains the settled line records zero hold.

| Milliseconds from input, except intervals | First, baseline | First, fix | Median of four reopens, baseline | Median of four reopens, fix |
| --- | ---: | ---: | ---: | ---: |
| First visible response | 136.3 | 109.6 | 95.8 | 90.6 |
| Latest line readable | 538.3 | 344.3 | 467.5 | 305.8 |
| Longest visible hold | 383.2 | 216.1 | 288.2 | 197.9 |
| Longest main run-loop interval | 494.2 | 233.0 | 330.1 | 207.9 |
| First observation of an editable first responder | 76.0 | 71.1 | 79.8 | 68.1 |

Each of the five openings reached the final line earlier. The first visit is
cold within the running workspace. The remaining roughly 200 ms holds are
visible in the samples. Full text layout, window composition and capture cadence
remain in the measurement. These comparisons have no calibrated CI budget and
do not measure network delivery, physical trackpad latency or VoiceOver timing.

Production baseline `70684b74d69154083b5a2a41db30dd6d43f1d7b8` and fixed
source `517b3215b51c91a74140b24db9441598882ea90e` have source SHA-256
`f19fcdab7b192ae960176b1fabed7ae387032434a4b88c80e6b156de24d9256c`
and `c493d3c923f3faa9d789895a30bed744bc5f753e9850d118139e3ebff58ae0cd`
respectively. The paired runs compiled the same collector, preserved at
`34a39ccdb321edc616de24fa76df7a37103e4a32`. The runner captured each source
digest before and after compilation. The archive includes hashes for both
executables and the collector sources, all five visits, the frame comparisons,
main-loop intervals and configuration. [Raw samples and receipts](linked-page-samples.json.gz)

```sh
python3 demos/moku-landing/verify_header.py --conversation-performance --linked-page --output .build/linked-baseline
python3 demos/moku-landing/verify_header.py --conversation-performance --linked-page --output .build/linked-opening
```

## Reading behavior and trials

The fix keeps TextKit's exact inline seats. Visual proximity admits the native
controls a viewport ahead, and an accessibility request can admit them earlier.
The subscription starts on entry. A cached page can begin fitting the glass from
its vertical bubble insets during the first 24 pt of shell travel, before full
text layout. An already expanded editor admits text at its destination width.
The shell and the bubbles keep their existing drawing and animation parameters.

In the controls-only trial, the latest line was readable in 379.6 ms on the
first visit and 329.5 ms on the median reopen. Two reopens first showed their
settled line on the first detected change. The final implementation also starts
the shell moving before fitting a ready page. All five first responses in its
paired run arrived within 114 ms.

An initial plain-page build was discarded when the collector source changed
during linking. A linked baseline run reached the old 60-second harness deadline
after its second visit. A controls-only interaction run captured all four
openings, then reached that deadline in Vision text recognition. The whole-run
allowance accommodates post-capture analysis. The optical and reading checks
use their original criteria. Partial runs are excluded from the table.

A separate first-opening profile of the fixed source captured 188 main-thread
samples. The call graph includes 51 samples under a SwiftUI hosting view layout
and 38 under scroll-view fitting. Its stacks include text measurement, text-view
creation and display-list updates. These are inclusive sample counts. A trial
that reserved offscreen TextKit heights before mounting text views reached the
last line in 363.2 ms on first opening and 290.1 ms on the median reopen. A
single-width column trial recorded 392.1 and 345.4 ms respectively. Both trials
reported a 120 Hz display maximum. Neither established a consistent improvement
over the paired result, and neither is in the fix. The profile was collected
separately from the timing table. [First-opening main-thread sample](linked-page-main-thread.txt.gz)

The interaction replay on `517b3215` opened a 32-message page with 15 execution
links. One glass button was mounted on entry. Fresh entry, a delayed page,
entry from Compose and an interrupted reopen all showed the final line with
a zero-point bottom gap. Three scrolls kept the document at 6,323 pt. A new
reply and a window resize preserved the 4,734 pt reading offset. Scrolling up
exposed the earlier execution button before accessibility traversal. Both page
controls reached their expected text. The send replay verified typing, retry
with a restored attachment, six distinct messages after delivery, and the same
reading position before and after the reply.

```sh
python3 tools/e2e/build.py --go ./scripts/go.sh --with-app
python3 demos/moku-landing/verify_header.py --conversation-opening --linked-page --output .build/verified-reading
python3 demos/moku-landing/verify_conversation.py --send-refresh --output .build/verified-send
python3 demos/moku-landing/verify_header.py --talk-link --output .build/verified-navigation
```

The first broader Talk-link replay passed the history-link clicks and compact
multiline notification, then failed after clicking the link at the end of an
overflowing notification. The selected historical reply was ready, at offset
zero with following disabled. Its semantic timeline reported a 260 pt document
in a 450 pt viewport. The fixture requires the 40-paragraph reply to overflow.
The failure capture shows its heading and the first paragraphs. The failed receipt is retained. Separate debug builds of the baseline and
the same fixed source then passed all eight visits with the original assertion.
The repeated overflow visit reported 1,966 pt of content at offset zero on
the fixed build. The cause of the first height discrepancy remains unresolved. [Failed reader capture](linked-page-navigation-failure.png)
