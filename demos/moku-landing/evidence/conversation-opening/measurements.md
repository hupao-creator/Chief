# Chief Bar conversation opening

The reported recording shows two upward swipes on the collapsed Chief Bar in Overview. In both, about 0.53 seconds elapse between the first visible widening of the glass and the message bubbles appearing. The recording provides no input timestamp. The replay measures that input separately.

## Results

All times are milliseconds. The comparison separates the first opening from the median of the four reopens. A timing requires the latest line in the settled capture and a passing idle control on that visit. Shorter time to readable text and shorter visible holds indicate improvement. The first response and main run-loop intervals show where the remaining latency occurs.

| Metric | Main, first | Fix, first | Main, reopens | Fix, reopens |
| --- | ---: | ---: | ---: | ---: |
| First visible response | 187.8 | 216.0 | 131.4 | 113.5 |
| Last line readable | 630.4 | 322.8 | 606.5 | 214.7 |
| Longest visible hold | 231.2 | 21.2 | 206.7 | 73.2 |
| Longest main run-loop interval | 138.2 | 103.0 | 199.1 | 94.6 |

Each pair below is main / fix. An independent unprofiled run on the same fixed sources measured 325.3 ms for first-visit readability and 218.5 ms for the reopen median. Its corresponding visible holds were 73.3 and 68.4 ms. Cold first response varied from 138.2 to 216.0 ms across the two fixed runs. The paired cold response was slower than main. Both fixed runs reached readable text sooner on every visit.

| Visit | First response | Readable | Longest visible hold | Longest main interval |
| --- | ---: | ---: | ---: | ---: |
| 1 | 187.8 / 216.0 | 630.4 / 322.8 | 231.2 / 21.2 | 138.2 / 103.0 |
| 2 | 132.9 / 117.2 | 620.9 / 207.9 | 226.1 / 73.4 | 219.4 / 96.5 |
| 3 | 129.8 / 128.1 | 609.2 / 232.9 | 209.6 / 69.8 | 197.6 / 85.6 |
| 4 | 125.3 / 105.8 | 595.4 / 209.3 | 197.6 / 86.7 | 197.4 / 102.5 |
| 5 | 136.3 / 109.7 | 603.8 / 220.1 | 203.8 / 73.1 | 200.6 / 92.7 |

The paired fixed run used the clean implementation commit `c905d3f82ab0f99120db1da7370580336b769526`. Its production source digest is `f166d94c2ca6fe27d06e94f0f2bfde14f3f18fc03472dcb56cbeee58b86ccc29`, shared by the delivered tree, the independent run and the mounted reading receipts. The baseline collector links the retained, unmodified main objects to the same Swift fixture. Binary identities, collector hashes, every captured frame comparison and the timer intervals are in the [raw samples](samples.json.gz).

## Workload and collection

The baseline is local main at `8ee825d40c4f783833f1532f61611fea3905cd93`. Both builds run the production workspace on the same Apple M1 Pro, macOS 26.5.1 (25F80), Swift 6.3.2, in Release with testable imports. Each starts a fresh isolated profile. The dark 1100 × 800-point window contains 18 Overview cards. Display scale is 2×, maximum refresh is 60 Hz, and Reduce Motion and Reduce Transparency are off. The full local cache page contains 64 alternating, multiline messages (26,460 encoded bytes). Its last reply spans more than one viewport. A phased upward AppKit scroll opens the collapsed Bar. An outside click dismisses it between visits. The first visit is cold within the running workspace. Four more visits use the same page.

ScreenCaptureKit records the replay's own window at one pixel per point, requesting 60 frames per second. Input and frame display timestamps use the host clock. The collector compares the lower central 720 × 200 points and excludes the resting eyes from the motion mask. A first visible change takes at least 60 sampled pixels with a change greater than 12 in the green channel. After capture, Vision locates the exact final line in the settled reply. Readability requires its bright-pixel mask to have at least 90% intersection over union with that reference at its final position. The longest visual hold is the longest interval between successive visible changes from first response through readability. The main-thread metric is the largest interval between 120 Hz common-mode timer callbacks intersecting the input-to-readable interval.

The timings include window composition and capture cadence. They characterize this machine, page and window. Physical touch-to-glass latency, network delivery, other display modes and pathological pages near the Runtime byte limit have separate workloads. These are local comparisons without a calibrated CI budget. The two profiles use a separate launch of the same fixture, with `/usr/bin/sample` attached before the first swipe, for one second at a requested 1 ms interval. Time spent in the sampler is excluded from the latency runs.

See the [collector and replay commands](../../README.md#chief-bar-opening) and the [Chief Bar reading contract](../../../../app/macos/Sources/Host/MokuScene/README.md#chief-bar-conversation).

## Layout and reading position

On the baseline the Dock waits for 90% of its width transition before mounting the conversation and subscribing to its page. SwiftUI then measures an eager stack of every bubble, including selectable text, timestamps and background geometry. Reporting the measured height also disables the shell animation for that layout pass. A cached page reproduces the visible pause without a model request.

The Dock now starts the page subscription on the swipe. The first movement of the glass admits the transcript at its final width. Older bubbles use a lazy stack. The six trailing rows and end inset keep exact heights, and the viewport clips above the composer throughout the height transition. The panel only needs the document height up to its own 648-point cap. Scroll and resize events distinguish a reader following the latest reply from one scrolling through history.

A fully lazy trial placed the latest text 332 points below the resized viewport on reopening. A second trial could pull a reader back to the end while scrolling to the first message. The opening replay checks the actual AppKit clip, the final text in captured pixels, the first visible row at the opposite end and both page controls. The live send and restart replays also check the bottom after timestamp release, window resizing and a taller draft. These checks cover defects that a faster opening alone would miss.

## Main thread and mounted behavior

The separate first-visit profiles contain 383 baseline and 379 fixed main-thread samples. Each entry counts samples whose stack contains the named symbol. Categories overlap, and the sampler also observes the rest of the workspace and idle time. Nested stack layout, text fitting and Core Text appear in the baseline main-thread stacks. The fixed profile still shows hosting-view layout while fewer samples pass through conversation views and text sizing. [Baseline main-thread graph](baseline-main-thread.txt.gz) · [Fixed main-thread graph](candidate-main-thread.txt.gz)

| Symbol or symbol fragment | Main | Fix |
| --- | ---: | ---: |
| `NativeMokuConversation` | 50 | 5 |
| `StackLayout` | 65 | 43 |
| `sizeThatFits` | 64 | 43 |
| `CTLineCreateWithAttributedString` | 27 | 18 |
| `NSHostingView.layout` | 110 | 114 |

The opening replay measures a zero-point bottom gap and recognizes the tall final reply after the first swipe, delayed content, entry from Compose and interrupted reopening. A new scroll moves the native reading offset from 3523 to 3283 points. It stays at 3283 through both an appended message and a shorter window. The first bubble and the earlier and newer page controls remain reachable. The live Runtime replay covers five ordered messages, attachment names, window and Runtime restart, short content fitting, 1100 × 800 and 860 × 600 windows, multiline drafts and horizontal timestamps. The admission replay retains six distinct messages and preserves the reader's offset on a later reply. [Mounted reading receipts](interactions.json)

`make lint typecheck` completed, as did the Debug build with Swift warnings as errors and the optimized benchmark build. The live scenarios use temporary storage, the real SQLite Runtime and a loopback model peer. The largest individual replies still lay out their full selectable text. The cached timing workload covers one full 64-message page at one window size.

A combined Overview Debug replay on the implementation commit passed conversation paging, then stopped when its click probe missed the overflowing Chief Note body. A diagnostic run with captures on that failure path passed the same Note scroll criterion and reached the Landing conversation and Compose checks. On the integrated workspace, the center point was inside the 524-point Note viewport with 2,066.5 points of document content. AppKit returned a SwiftUI graphics host at that point. Its enclosing scroll view lookup missed the mounted Note viewport. The [combined replay](../../README.md) observes that viewport inside the Note panel and sends both native scroll events at the same point. The dedicated conversation latency and reading replays run independently of this probe.
