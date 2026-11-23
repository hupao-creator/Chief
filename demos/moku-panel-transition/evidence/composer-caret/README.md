# Chief Bar insertion latency

In a populated Overview, press ⌘⇧B with the workspace key and the bar folded.
The measured interval starts when the opening shell reaches its settled width
and ends at the first visible insertion stroke. A stroke visible during travel
has zero wait after expansion. The target is a reduction of at least 50%
in the median wait across three openings per build.

The workspace Compose menu command calls `toggleInput(focusOnOpening: true)`.
The Dock hands that request to the attached native editor and calls
`makeFirstResponder`. Input ink fades in over the last tenth of shell travel.
On the baseline, the layer appeared on an AppKit on-phase blink callback.
The fix uses TextKit's insertion location on the focused editor's first
drawable layout. The native callback continues to position it during editing.
[Dock contract](../../../../app/macos/Sources/Host/MokuScene/README.md#dock-and-composer)

## Window recordings

Both Debug builds ran the production workspace and menu command on macOS
26.5.1 (25F80), with a fresh profile, a private runtime and one completed
fixture task. The same PID-targeted keyboard driver opened and closed the
bar, without typing during the timed visits. ScreenCaptureKit recorded only
the identified 1180 × 760 pt window at 2× with a requested 60 Hz cadence.
The UI, native replay and performance leases serialized capture with builds.
Elapsed times use the recorded presentation timestamps, including gaps.

| Visit | Baseline wait | Fixed wait | First fixed caret relative to arrival |
| --- | ---: | ---: | ---: |
| 1 | 610.0 ms | 0 ms | -275.0 ms |
| 2 | 613.3 ms | 0 ms | -280.0 ms |
| 3 | 593.3 ms | 0 ms | -266.7 ms |

Median post-expansion wait fell from 610.0 ms to 0 ms, a 100% reduction.

The review movies preserve the windows' original frame sequence and PTS,
cropped to 1240 × 162 px at (560, 1318). The PNGs and CSVs come directly
from the original window recordings before the review movies were encoded.
[Baseline movie](baseline.mp4) · [Fixed movie](fixed.mp4) ·
[Baseline boundary frames](baseline.png) · [Fixed boundary frames](fixed.png)

In crop coordinates, the shell edges are the first and last pixels with
green below 20 on row 48. Arrival is the first of three consecutive frames
with both edges within one pixel of the final positions. Their reference positions are the medians over the last 250 ms
of the sampling interval, ending 200 ms before the shell narrows below 880 px. For the insertion mark,
look at columns 232–236 and rows 66–78. The first of three consecutive
frames with a continuous column at green 48 or higher identifies the stroke.
Start searching after 90% of the final width to exclude the moving eyes.
The signed intervals retain a negative value when the caret leads arrival.
This is a frame-level comparison on one Mac at one window size.
[Baseline samples](baseline.csv) · [Fixed samples](fixed.csv) ·
[Run identities, timestamps and focus observations](results.json)

## Reported recording

The supplied 4096 × 2450 video contains two openings with the pointer away
from the bar. The keyboard event itself is outside the recording. The two recorded
waits were 566.7 ms (frames 34 → 56) and 583.3 ms (175 → 200).
The scan uses a 1160 × 144 crop at (1468, 2124), shell row 50, caret
columns 227–231 and rows 66–78. Frame numbers are zero-based.
[First opening](original.png) · [Second opening](original-second.png)

## Input and focus

The driver sent the first character immediately after the Compose key pair.
AX read `a` from the focused text area. The driver closed with Compose, waited 120 ms, reopened
with Compose and immediately typed again. AX then read `ab` in the focused editor.
On closing, focus returned to the workspace window. Clicking the folded bar
restored the editor and its draft. A separate populated profile with two
directory filters allowed AX to move focus from the open editor to Library.
After 1.25 seconds that same button still held focus.
[Typing and reversal](typing.mp4) · [Compose replay procedure](../../../../tools/e2e/README.md#chief-compose-shortcut)

The empty-filter fixture disables its All button. Focus transfer was measured
in the separate two-directory run. In the preliminary baseline typing run,
Escape left the editor focused and changed its value from `ab` to `a`.
The baseline timing samples come from the three preceding untyped openings.
Compose closed the final typing visit.
Additional fixed-build attempts lost the foreground or had no on-screen window,
so their incomplete visits are excluded. The timings and focus observations above
come from complete visits on the recorded production source digest.
