# Desktop interaction verification

This runner checks **interaction input → real system → user-observable state**.
Overview, Reading, Settings and Collection use the opt-in
[native automation protocol](../native-interaction/README.md), with real Swift
UI, Runtime, authenticated HTTP/NDJSON, persistence and native Codex processes.
Onboarding uses an unattended macOS Accessibility driver with real confirmation
buttons and a strict per-confirmation deadline.
Composer uses an explicit operator-assisted system Accessibility/input path; the
runner independently checks its public persisted inputs, output and interruption.
It does not link reducers or instantiate fixture views. Runtime setup and public
content reads establish prerequisites and independent result evidence. Runtime
invariants belong to PBT. Benchmarks own general UX timing, resource use and
visual-performance measurements.

## Harness Thread Markdown

Run `python3 tools/e2e/thread-transcript/run.py --output /tmp/chief-thread-transcript-evidence` on macOS with a graphical session and the pinned dependencies cached. Specify a fresh output directory. The driver feeds Codex app-server, Claude stream-json, Pi RPC and OpenCode SSE frames to their production parsers and reducers. The replay checks the same manual input identity in all four readers. OpenCode consumes its native inbox event and also replays the authoritative message list twice.

The replay first checks the manifest preview, the turn projection with deferred presence, full execution rows and the text in the native Markdown views. Retained-state fixtures exercise independent equal-text Codex notices, Claude fork history, a Pi extension notification and terminal partial reply, and a targeted OpenCode child reply. Additional frames exercise interleaved Unicode text, reasoning and a tool in Pi, and corrected Claude blocks around a moving review.

A nonactivating panel mounts the ordinary Agent workspace with an isolated content store and live subscriptions. The replay checks native Markdown order, turn state, work controls, group counts and metadata during execution, settlement, permission requests, success and failure. It records paragraph geometry and fonts, unfolds the work summary and remounts the saved turn. The Codex case separates catalog and scoped completion updates and locates an earlier reply by its message link.

The evidence directory contains the revision, platform, source projections, comparison results and images captured from the replay's own windows. Codex samples record changing pixels in the last work summary and its stationary text after the reply begins and after completion. These frames check whether the sweep appears at the right time. Installed CLI transport, real account permissions, database transactions and rendering latency have separate verification boundaries. [Reading contract](../../design/reading.md#content-and-execution-identity) · [Fixtures and launcher](thread-transcript)

## Current scenario contract

[scenarios.json](scenarios.json) is the executable inventory. IDs remain stable
across wording changes; changing a scenario's meaning requires a new ID. Each
entry names its owning module doc and required evidence files. A report always
contains every requested ID, including blocked and unreached entries.

| ID | Implemented interaction and criterion | Prerequisite / evidence | Coverage boundary |
| --- | --- | --- | --- |
| `E2E-ONBOARDING-001` | Confirm discovery, Chief, Tag and Super Thread in order. Select **Configure separately** for both background roles. Page changes take under 1,000ms each. The final Dock handoff takes under 1,560ms. | Fresh profile, authorized system AX driver, exclusive desktop. Each press verifies the private runtime PID/epoch, target button and focused test window. `onboarding-ax.jsonl` records inputs and timings. `onboarding-persisted.json` records the saved roles and completion. | Real macOS AXPress, native discovery and Runtime persistence. The final endpoint is the focused, editable Chief composer. Individual rendered frames and live model service behavior require separate evidence. |
| `E2E-OVERVIEW-002` | Check the leading and trailing horizontal limits, open Settings at the trailing edge and return to the same position. | Twelve completed tasks in the default suite, or mixed cards in the Collection suite. Leading, trailing, uncovered and start snapshots record the poses. | Mounted semantic controls and placement geometry. The [window replay](../../demos/moku-landing/README.md#nested-workspace-header-replay) also exercises native input routing and pointer hits. |
| `E2E-CHIEF-001` | Open Note and switch to Compose. The legacy command is rejected and Chief records have no Overview reading targets. | Populated private profile, `chief-controls.json`. | Mounted semantic controls. Menu shortcuts, eye placement and the click target require native window observation. |
| `E2E-READ-001` | Open the prepared Agent from Overview; observe its ready, nonempty mounted turn; deliver an external follow-up; observe its mounted successor; activate the first history entry; Back returns to the successor; Overview closes the reader | Fresh profile, real Codex directory, settled source reply; `creation.json`, scoped content, `ui-initial/current/history/return/overview.json`, `ui-events.jsonl` | Navigation callbacks, content acquisition and mounted turn identity; HTTP follow-up input, not composer submission. Semantic readiness is not proof of exact rendered pixels or text layout |
| `E2E-SETTINGS-001` | Open Settings with Chief Agent selected and only Chief Agent, Auto-Categorization and Super Thread available; activate an unselected `routingPreset` capsule; close through the save gate; read the exact saved preset through public Runtime state; reopen on Chief Agent and observe it selected | Same isolated connected workspace; `settings-before/edited/persisted/reopened.json`, UI operations and public API receipts | Default navigation and the binding/draft/transport/persistence/reopen path for one preset; IME, keyboard, pointer hit-testing, errors/conflicts and system presentation need separate evidence |
| `E2E-COLLECTION-001` | Open a grouped member, return, then revisit and read. Switch directory and archive/restore unrelated reports while All remains mounted. | Two isolated directories, two completed tasks and eight reports from a deterministic peer. | In the three-column replay window, All groups six fresh reports and a four-report directory groups two. A brief visit holds the cover, a qualified visit promotes the report, and archiving down to three reports releases the group. Restoring reports groups them again. |
| `E2E-COMPOSER-001` | Type a follow-up and activate the actual Send button; observe accepted draft clearing and completed output; send a held task, observe Stop in the empty action seat, activate it and observe interruption and an editable empty composer without navigating away | Exclusive desktop, accessible isolated bundle, external operator; `operator-send/stop.json` AX observations, exact persisted prompts, `composer-send-content/oracle/ui.json`, `composer-running/stopped/stop-content/stop-ui.json` | Operator-assisted OS input, not unattended CI; current ordinary Thread text input and cancellation only, not pause/resume, historical forks, IME or uncertain receipt recovery |

The implemented desktop scenarios require execution evidence before they can be
called verified. Source inspection and a successful preparation do not certify
them. The runner emits the actual status, revision and evidence for each attempt;
there is no repository-wide "covered" flag. Current implementation supports
Codex only and deterministic text without attachments. The collection scenario
uses two ordinary Threads. The default suite prepares twelve and reads the first. Composer alone uses one.
Reading uses two completed executions; Composer adds one completed follow-up and
one interrupted execution. Real provider behavior/authentication, other Harnesses,
forks, archive button input, reconnect/restart recovery and cancellation invariants are not
certified by these scenarios.

### Alpha install and first launch

Use the [packaging contract](../../app/macos/build/README.md#invited-alpha-dmgs)
and [installation guide](../../docs/getting-started.md#install-chief-alpha).
Verify the DMG against the checksum from the same release. Mount it read-only,
check the Applications shortcut and compare the enclosed guide with the download.
Copy the app to a temporary install directory, eject the image, then run alpha
smoke on the copy. Record the DMG hash, source commit and build number.

Launch that copy with an isolated home and profile. Observe discovery with no
agents and the available installation and retry actions. With an isolated,
configured agent, complete setup, reopen the same profile and check that setup
stays complete. For an update, populate a disposable profile with the distributed
version, quit it and open the candidate against the same home. Check its saved
work and settings. Record the OS, fixture, observed pages and cleanup.
Downloaded-file Gatekeeper and permission prompts require a quarantined copy
on a clean Mac. A local launch cannot establish those outcomes.

### Onboarding confirmations

Build with `python3 tools/e2e/build.py --go ./scripts/go.sh --with-app`, then
use the local E2E runner from a macOS graphical session with Accessibility
authorization for the invoking tool and Reduce Motion off. Coordinate the
desktop slot before running. The measurement holds the shared performance lease
and the desktop lease through cleanup.

```sh
python3 tools/e2e/run.py run --suite onboarding --runtime .build/e2e/chief-runtime \
  --app app/macos/.build/debug/Chief \
  --desktop-lease /private/tmp/mokusei-ui-verification.lock \
  --desktop-owner YOUR_COORDINATOR_THREAD_ID \
  --output output/e2e/onboarding
python3 tools/e2e/run.py verify output/e2e/onboarding
```

The runner launches a uniquely bundled development App, starts Runtime with a
fresh isolated profile and passes no Overview preparation flags. It performs
no settings writes during preparation. Native discovery uses the installed
Harnesses found in the isolated environment. The external peer and private
native homes follow the same isolation policy as the other desktop scenarios.

The clock starts immediately before each AXPress. The next page must expose its
own enabled confirmation after the normal page animation. After **Start using
Chief**, the same window must expose the enabled attachment button and have an
editable Chief text area focused. Observation and AX transport overhead count
toward each deadline. The timings are individual samples, with one press per
confirmation. A sample at or above its deadline fails. Page changes have 1,000ms each.
The final handoff has 1,560ms, including 140ms of form fade, 780ms of
contraction and 180ms of reveal. A late destination can allow
the journey to continue measuring subsequent confirmations in that same visit.
After AX observes the editable field, a single read of the app's local interaction
socket retrieves its monotonic timestamps for successful persistence, Dock preparation
and the three animation boundaries. The terminal and report show each interval.
Persistence and preparation before the fade together must take under 260ms.
Post-reveal AX focus must take under 200ms. Each animation must last its
authored duration with at most 34ms of early completion (two 60Hz frames).
These are callback intervals. Use the window recording for rendered motion. The run also reads
both saved role modes through Runtime and checks the profile completion marker.

The `onboarding` suite runs separately from prepared-profile suites, including
`all`. The hosted Desktop interaction workflow covers its supported mounted
journeys. Onboarding requires a local AX-authorized graphical session. The
driver records macOS and accessibility settings for that session.

### Full-surface loading mark

Open the native app with a disposable returning profile. Delay the start of its
background service long enough to see a complete 3.2-second loop. At the center
of the loading surface, the pan should dip, toss three colored agent marks into
a fan and catch them. In both appearances, the surface background must remain visible
between the marks and around the pan throughout the loop. Release the service and check that Overview replaces the
mark as soon as initial content arrives. With Reduce Motion enabled, the same
120 pt mark should remain still while waiting. Record the source revision,
runtime delay, captured window frames and the first ready workspace frame.
[Startup surface](../../app/macos/README.md#system-appearance-and-language)

From a finished result, send a follow-up and hold execution admission. Inspect
the Execution sidecard for the same toss above **Opening conversation…** and
release the pending execution to check that its reader takes over. For a delayed
Report body or related execution list, check the mark in the corresponding
column. In an ordinary Agent reader, check the 180ms placeholder grace period,
the title/emoji handoff and the centered mark within the reader's viewport.
[Reader placeholders](../../app/macos/Sources/Shared/PluginUI/README.md#reading-placeholders)

### First-run handoff

Launch the native app with a fresh private profile and a ready Chief-capable
agent. With the window active and visible, record the window as you
click **Start using Chief** on the Super Thread Agent page. Inspect the frames
as the panel reaches the input box. Both eyes should be open as the box comes
into view, then narrow together once and reopen in the same seat. Watch for
the next idle blink after a full interval. Type in the
revealed editor. Reopen the same profile and check that it skips setup.
Repeat with a fresh profile for each interruption. Cover the window during
the final 180ms fade and uncover it during the following 320ms. In a separate
visit, leave the app while the eyes are closing and return before the blink
would have ended. Both eyes should be open on return and stay open until
the next idle blink. Verify that you can type at handoff in each case.
Record the revision, the times of the interruption and return, and the
eye frames through the next idle blink.
This visual check exercises the [onboarding handoff](../../app/macos/Sources/Host/Onboarding/README.md).

For a blink renderer comparison, mount the baseline and candidate at the same
scale, pose, color and wall-clock phase in one isolated window. Compare both
eye silhouettes when open, closing, narrowest and reopening in the Dock and
composer. Record the contours at native resolution, the time of minimum area
and the open interval between blinks. To isolate compositor progress, hold the
fixture's main thread during a second blink and read complete window frames
on an independent capture queue.

The [mounted Dock replay](../../demos/moku-panel-transition/remaining/README.md) exercises reply read state,
permission and questionnaire controls, Timer acknowledgment and editor reversal
with ordinary and reduced motion.

### OpenCode cold discovery

Use a private home, XDG directories and Chief profile with the supported
OpenCode CLI on PATH. Set `OPENCODE_DISABLE_MODELS_FETCH=1` and
`OPENCODE_DB=:memory:` to enumerate built-in models without a real account.
Start with no `$XDG_CONFIG_HOME/opencode` directory.

In first-run setup, wait for OpenCode to appear ready. Open the Chief setup
page and check for an OpenCode dispatch target. For the transport boundary,
launch a separate cold profile and call `harness:detect-installation` with
`["opencode"]`, then `harness:settings-presentation` with
`{"scope":"global","harnessId":"opencode","executionOwner":"moku"}` as its
single argument. The first presentation must report a ready CLI and a
nonempty catalog with no execution snapshot error while the native CLI
creates the empty directory. Repeat with a precreated empty directory as a
control. For routing, call the adapter's `DiscoverMokuTarget` on a separate
cold directory and require a complete nonempty catalog on its first request.

Record the source revision, executable identities, OpenCode version, profile
conditions, first result, and mounted setup observations when a desktop
session is available. Built-in enumeration covers local discovery and target
admission. Provider execution and real account state need separate evidence.
[Catalog identity contract](../../internal/plugins/harness/opencode/README.md).

### System appearance and language

Use a private profile and a disposable macOS session for system-wide setting
changes. The [native app contract](../../app/macos/README.md#system-appearance-and-language)
owns resolution, profile compatibility and window appearance.

1. Launch into a fresh profile and inspect onboarding and menus. Repeat with a
   profile containing saved `preferences.appearance` and `preferences.locale`
   opposite to the system settings. Check that this profile keeps its onboarding
   marker, selection and reading records across a normal write and relaunch.
2. Cover Chinese with different scripts and regions, English with different
   regions, and a different primary language with Chinese second. Inspect the
   visible language and `snapshot.settings.locale`, including after changing the
   preferred order while Chief is running. Check the profile's output locale
   receipt before starting a generated-output operation. In an isolated profile,
   count successful locale temporary-file creations, fsyncs and renames for
   initial publication, then through two 15-second discovery intervals and a
   reconnect. Expect one of each initially, zero with the same published value,
   and one of each per language change. Race two clients requesting the same
   change and check that only one publishes. Force a rename failure and check
   that the next command publishes after the obstruction is removed. See the
   [profile publication contract](../../app/macos/Sources/Core/README.md).
3. Open Settings from loaded Overview and confirm Chief Agent is selected and the
   English tabs read Chief Agent, Auto-Categorization and Super Thread, in order.
   In Chinese, check Chief Agent, 自动归类 and 超级线程. At normal and narrow widths,
   select each tab and check its content and selection indicator. On Chief Agent,
   choose an available model under Chief Model (Chief 模型 in Chinese). Check the
   selected value after switching away and back. Close Settings from another
   tab and reopen on Chief Agent. Repeat the open on a previously loaded Overview
   while disconnected.
4. Change macOS Appearance from Light to Dark and back with Overview, a reader
   and an attachment preview open. Record effective appearance in the snapshot
   and capture each window. Repeat with the same Settings visit and the same
   first-run form mounted. Check that the form backgrounds and controls follow
   the new appearance without changing the active tab or setup step.
5. With an installed, enabled agent, compare the Chief map and the Tag and
   Super Thread animation backdrops in both appearances. Capture the animations
   during playback and after switching away and back. At the full Settings
   width, check that all three panels extend equally past both sides of the form
   and have internal padding above and below their contents. Narrow the viewport
   until the illustration canvas scales down. Check that the art and the panel
   fit, that the form below remains reachable by scrolling, and that clicking a
   Chief dispatch target and each role's mode control updates its selection.
   In a short Settings viewport, scroll the header out of view and continue down to the form.
   Check that the resident eyes move out with the header.
   Repeat the backdrop check with Reduce Transparency and inspect the opaque
   fallback. Record the window width, height, frames and observed selections.
   See the [Settings backdrop and playback contract](../../app/macos/Sources/Host/Settings/README.md).

Keep the revision, primary language order, appearance, profile fixture, launch
mode and before/after observations with each run. A process-local simulation
covers only its injected inputs. It cannot certify macOS notifications or all
window pixels.

### Settings over a populated Overview

In an isolated workspace, scroll horizontally until an Agent and a Super Thread are in view.
Record the window while opening Settings with the gear and closing it with **×**.
Compare each clear frame of the Super Thread title and cover with its pre-click
appearance. The workspace blur and shade should follow the capsule in both
directions. A sharp but faded report before the blur starts or after it lifts
fails the replay. Check that the cards retain their positions, canvas scrolling
is blocked while Settings is open, and the same canvas responds again on return.
See the [Settings presentation contract](../../app/macos/Sources/Host/Settings/README.md).

### Custom task orchestration editor

Open **Chief → Task Orchestration Preferences → Custom** in Settings. Verify
the title and hint in English and Simplified Chinese. In light and dark
appearance, capture the empty editor before and after focus. The rounded
glass has the same border in both states. Type the first words of the hint,
return the insertion point to the start of the line, and compare the first text
origin, baseline and insertion position with the empty frame. At narrow widths,
compare the hint and the same text typed into the editor across wrapped lines.
Delete the text and check that the entire hint returns with the same padding.
Repeat with Reduce Transparency and check for an opaque editor with a neutral
outline. Check that an invalid draft shows the danger outline on and off focus.
Compare same-line typing and Return with Chief's composer. The insertion point
eases along a line and moves directly to a new line. Select text and move focus
away to check that the glow clears.

Enter multiline text, replace and undo a selection, and scroll within the field.
Check that the text and selection share the inset as lines scroll in and out.
Check that macOS exposes a labeled multiline editor with the current value and
selection. With a system input method, start composing and cancel or commit the
marked text. Check that composition uses the native caret and that Escape during
composition leaves Settings open. Switch presets and return to Custom, then
close and reopen Settings and compare the exact text with the saved
`moku.routingGuidance`. Record the revision, appearance, input method, editor
observations and saved value. The [Settings preview](../../demos/settings-navigation/README.md)
can check the mounted editor with an in-memory save. Runtime persistence requires
an isolated connected workspace. `E2E-SETTINGS-001` exercises preset persistence.

### Chief Note execution link

Prepare an isolated workspace with two directories. Give both ordinary Threads
at least two completed runs with distinguishable replies longer than the viewport. Have one Super Thread
cite a different run of the same Thread as the Note. Put links to both Threads
near the bottom of a long Chief Note. Include enough Reports for a multipage
Collection on All. Record the isolated window continuously and save the filter,
carousel member, execution identities and link position alongside the recording.

1. In the other directory, scroll the Note to the ordinary link and click it
   with the system pointer. Check that the Note closes and the selected filter and canvas offset stay put.
   The reader should open at the cited run’s heading. After the scoped body has loaded, check that its timeline
   height exceeds its viewport, `top` is zero and `following` is false. Repeat from a filter that already contains the target and check that
   its selection stays put. Click the reader’s **×** and verify the Note stays
   closed on Overview. Reopen the Note and follow the historical link again.
   Press Escape in the read-only text to return to the Note and compare the
   link’s window position. On separate visits, use the Overview command and
   click the reader backdrop. Both Overview exits leave the Note closed.
2. Open the associated link from a different directory. Check the Report title
   and the exact cited execution in its open side panel. Apply the same scroll
   checks to that timeline. Close the expanded visit with the Report’s **×**
   and verify Overview settles with the Note closed. Reopen the link. Use the conversation
   contents to visit current and historical rows. Type a draft on the historical
   run and switch away and back. **Back to related executions** should show
   the Report’s list. Click the Report’s upper-left **×**. Wait for Overview to
   settle and check that the Note stays closed. Press **⌘⇧N** and verify the
   same Note text and citation are available.
3. In All, start with another Report showing in the target Collection. Open
   the associated link. The filter should stay on All. Check consecutive frames
   for the Note closing, the carousel moving to the cited Report and settling,
   then the reader expanding from that card. Compare the panel travel with a
   direct click on the same card at the same window size and camera position.
   Repeat the comparison for an ordinary Thread and an individual Report.
   After a brief Report visit, type an unsent draft in its source conversation
   and close the report. From the same window recording, check that the input
   folds in its source column and travels back to the resting canvas center. Check the carousel page, collapsed Note and retired editor focus.
   Reopen the Note and follow the same citation to recover the focused draft.
   Check the separate Overview draft through its Compose shortcut. On the ordinary
   Thread route, use Escape to check the restored Note’s scroll position.
4. Repeat the three routes with system AXPress. Check English and Simplified
   Chinese. Record the capture rate. Track source revision, executable identity, scoped replies,
   input targets and returned state for each visit.

The semantic Note toggle exercises the Note entrance. Mounted route identity
and window frame recordings supply separate evidence.
[Note and link behavior](../../app/macos/Sources/Host/MokuScene/README.md)

### Chief navigation

Start with a private profile containing a Chief conversation and a completed task. A saved selection for the current Chief or a retained Chief archive must open Overview. Open Chief Note and inspect its accessible controls and the View menu. Compose and Chief Note have their own shortcuts. A plain Command-B leaves the current route in place. Check that the former history action is rejected, then open an ordinary task and a Super Thread from Overview.

### Live Super Thread updates

In an isolated app, open an existing Super Thread from its Overview card with
a cited execution visible beside the document. Use a long report with a
recognizable background, a section link, and text that distinguishes each
revision. Record the target window before triggering any update.

Complete a follow-up in the cited source conversation. Have the background
Super Thread Agent read the report and update just its introduction. Complete
another follow-up and have the agent replace only the HTML. Record the report
ID, revisions, accepted fields and selected reader throughout. Inspect the
window frames from the old text through the first visible new text. The body
must stay visible and the related list must keep its width and position.
Repeat after following the section link and compare the visible section, its
updated text and focus across the change. Keep the source commits, capture
conditions and movies with the results.
[Reader contract](../../design/reading.md#report-and-execution-sidecards)

### Live follow-up in a related execution

Open a Super Thread in an isolated app and select a source conversation from
**Related executions** while its latest execution is running. With the external
model stream still active, type two follow-ups in the sidecard composer and
send each through its mounted Send control. Capture the window across both
submissions and a subsequent content update. Inspect the text, timestamp and
background together in the intermediate frames. Each new row rises and fades
in once. Compare the position of an earlier visible row across sends, check
that the report and execution stay open, and check the exact inputs and
execution ID through Runtime. Repeat with a settled reply taller than the
viewport. Scroll partway up before sending and compare the timeline's offset
and following state before and after each steer. Repeat with Reduce Motion
enabled to check the immediate final placement. Record the build, capture settings, input method
and which cases were exercised. [Reading contract](../../design/reading.md#content-and-execution-identity) · [Recorded window and observations](../../demos/moku-panel-transition/evidence/live-steer/README.md)

### Super Thread reading regression

The [Markdown layout contract](../../design/markdown.md) also applies to the
related-execution sidebar. This local desktop replay needs the native Report
reader and system scroll input. The `supported` suite covers navigation in the
ordinary Thread reader.

In a private profile, prepare two completed Threads in one directory and link
both from one Super Thread. Open that report from Overview and activate the
target row in **Related executions**. Verify the selected execution against
its public scoped reply. Direct the input into the right-hand text column
while the report stays open. Include downward scrolling and a reversal with
momentum. Record the timeline offset, content height, viewport and time for
the next UI request after each gesture. A five-second request timeout fails
this replay. For a short, settled text fixture, the extent at a fixed width
must stay constant and the offset must travel in both directions.

For the [execution timeline's top padding](../../design/reading.md#report-and-execution-sidecards),
use a reply tall enough to scroll. Compare the initial content position with the
same timeline fixture using its standard document padding. The heading starts
20pt lower in the same viewport. Scroll beyond the added padding and back to
the start. The padding travels with the document, and the Back button and
left-hand Report stay in place throughout.

To check the [Dock return](../../design/composer.md#geometry-and-surfaces), type a
draft beneath the selected execution. Record the window while clicking the
upper-left **Close Super Thread** on the report. Measure the center and width
of the glass on each frame through arrival in Overview. The expanded bar must
narrow to its compact width at the execution column before its center moves.
Compare its final center and size with the settled Overview bar. Reopen the
same execution, verify its draft, and type in the editor. Repeat with Close
during entry, a repeated Close, reselection during return, and Reduce Motion.

For a long fixture, the [128 KiB mixed Markdown corpus](../benchmarks/reading/corpus.py)
provides identifiable first and last blocks. Check first entry, scrolling to
the final marker, scrolling back through visited sections, native text
selection after leaving a section and returning, narrow-window reflow, Back
to the related list and re-entry. First visits can refine the reserved heights.
After traversing the full document at one width, reversing through it should
retain the measured extent. Record the app and fixture digests, each input,
the original timeout and sample when present, and the isolated cleanup receipt.
Mounted readiness and UI request times measure different events from display
frame times.

To check [related list reveal](../../design/reading.md#report-and-execution-sidecards),
use a report with several distinguishable Markdown excerpts. Record first entry,
open a row and use **Back to related executions**. Inspect the first frame
showing the cards and the settled list. Each visible card with excerpt text
should show it in both frames. Repeat with a rapid return and another row
selection, and with delayed excerpt preparation. A pending list can show a
progress indicator. Once the cards appear, check that their excerpts match the
cited runs and that a late completion from a closed visit does not change a new
visit. The [production component preview](../../demos/report-thread/README.md)
can exercise this visually with synthetic data and a window recording.

### Agent reader alignment

At a fixed main Agent panel width, show one short reply, extend that same reply
until it scrolls, then shorten it again. Start the native replay process with
`-AppleShowScrollBars Always`. Record the argument-domain value, the actual
document scroll view's legacy style, clip width and vertical scroller visibility.
Measure the heading or full-width divider against both panel edges. The short
and long states must have the same centered column and wrap the same sample text
identically. Check a narrow pane at or below 540pt and a pane wide enough to
reach the 744pt column limit. Open an earlier run from the margin and return
to verify the same geometry in both documents.

### Agent history composer

Use an isolated profile with an ordinary Agent Thread and at least three
runs. After the input below the current run settles, select an earlier run
from Conversation contents, select another earlier run, and return to current.
Check the visible run in each direction, including when returning to the first
historical selection. Use distinct drafts to check that input follows the
selected run and that selection leaves focus with the reader. The mounted
history controls use the same navigation callbacks as the rail.

For the vertical transition, start with selected text in a scrolled current
document and the system scrollbar always visible. Check the selection, scroll
position and column width after Back. Reverse an opening, select another run
during return, then resize or deactivate during an accepted Back. The old
completion must leave the replacement run open. In an isolated component
window, record the page boundary and a running summary's text sweep while
briefly holding its main thread after the animation starts. Collect the
window's ScreenCaptureKit frames on a separate queue. Use complete frames
whose display and delivery timestamps both fall inside the hold. Check that
the pages meet throughout, that the band moves within the glyphs, and that
withdrawing reading admission restores static text.

To check the [Agent reader's history marks](../../app/macos/Sources/Shared/PluginUI/README.md#reading-panel-presentation),
also start with one completed run and send a second at a fixed window size.
Compare the heading and body frames before and after the marks appear. The
column should keep its width and horizontal position. Check both marks in the
leading margin. Start just outside the 24pt hit area and check that the preview
stays closed. The selected and idle marks should be equally long and share a
left edge. Hover each mark to open its preview. In a longer history check that
nearby marks extend progressively less and that the original widths return
when the pointer leaves. Click the earlier run
and click the newest mark to return. Press Up immediately. The earlier preview
should appear while the newest document stays on screen. Press Return and
check that the earlier document opens. Repeat in the related-execution reader
beside a Super Thread and at a narrow width. Record the viewport, document and
mark bounds alongside the frames. The mounted navigation scenario alone does
not measure this geometry.

For the [composer geometry contract](../../design/composer.md#geometry-and-surfaces),
record the isolated window during each selection. Check intermediate frames at
fixed window size with empty drafts. The glass must stay expanded and the
Harness mark must remain visible. Compare each frame's horizontal center and
width to the settled bar at the same column, allowing for capture and edge
detection precision. With a running execution in an open Execution sidecard,
switch between historical runs in the main pane and check the same geometry.
When the destination actually changes columns, check for direct travel between
the two settled centers. Repeat at ordinary and narrow window sizes in English
and Simplified Chinese. Record the build identity, observed sizes, language,
events, frame samples and capture limitations. `E2E-READ-001` checks mounted
navigation, while the window recording supplies the geometry evidence.

## Fact sources

Expectations follow these current production contracts, not removed replays:

- [Moku creation](../../internal/services/moku/README.md#e2e-preparation):
  `context.go` validates a nonempty enumerated directory; `tools.go` admits
  `create_thread`. Tool success is admission, so preparation separately awaits
  completed output.
- [Runtime input/content](../../internal/core/runtime/README.md#e2e-observation):
  `commands.go` receives `thread:follow-up`; scoped content is the authoritative
  independent output read. No database writes or internal log reads occur.
- [Mounted interactions](../../app/macos/Sources/Host/Interaction/README.md#e2e-contract):
  `NativeWorkspaceInteraction.swift`, `NativeReadingInteraction.swift`,
  `ThreadDetailTurn.swift` and `ThreadHistorySidebar.swift` own the observed
  route, execution, row and control identities.
- [Settings](../../app/macos/Sources/Host/Settings/README.md#e2e-contract):
  `NativeModelRoutingPreferences.swift` registers four preset actions;
  `NativeSettingsDraft.swift` and `NativeSettingsNavigation.swift` own save/close.

## Build and run

Python 3.10+, the pinned Go toolchain, macOS 26/Xcode with Metal, and a usable
native Codex CLI are prerequisites. No real provider account is required.
Build receipts bind both binaries to the production source digest and record
their SHA-256. A stale or missing receipt blocks the run. `--go` accepts the local
pinned wrapper or CI's `go`; build failures remain nonzero.

```sh
python3 tools/e2e/build.py --go ./scripts/go.sh --with-app

# No GUI. A ready preparation still exits 2: interactions remain unverified.
python3 tools/e2e/run.py run --runtime .build/e2e/chief-runtime \
  --prepare-only --output output/e2e/preparation

# Arrange an exclusive desktop slot first. All desktop users must agree on this lock.
python3 tools/e2e/run.py run --runtime .build/e2e/chief-runtime \
  --app app/macos/.build/debug/Chief \
  --desktop-lease /private/tmp/mokusei-ui-verification.lock \
  --desktop-owner YOUR_COORDINATOR_THREAD_ID \
  --output output/e2e/interaction

python3 tools/e2e/run.py list
python3 tools/e2e/run.py verify output/e2e/interaction
```

Output directories must be new; no rerun overwrites evidence. The default
`supported` suite requests Overview, Reading and Settings. Use `--suite collection` on the
same run command to check the populated camera and report grouping under its real clock. It enables
the isolated Super Thread Agent, activates the uniquely bundled test application and waits for the mounted reader to own foreground before timing visits.
`all` additionally requests collection and Composer. Composer requires `--operator-composer` and real external
input receipts. `--suite composer` selects just that scenario. No scenario is
silently skipped. The desktop lease uses atomic directory creation, records
threadId/pid/start/nonce, and refuses any existing lock (including an unresolved
stale lock). It remains held until App and Runtime teardown; cleanup removes only
the matching directory inode and owner. It coordinates cooperating runners, not unrelated apps;
manual shared-desktop scheduling remains necessary. The App's existing explicit
`--benchmark-scenario overview` prepares onboarding in the fresh profile; it
does not certify first-run onboarding.

### Collection member opening

Open the page count with two reports, then with enough covered reports to fill
several rows. At 2352×1400pt, capture the member panel at the top
of the grid. Measure the first row from the panel's top edge, both side
margins, card width, and the counts of fully and partially visible cards.
The first row starts 20pt from the top in both cases. Two cards sit together
in the center. A populated row uses as many 280pt cards and 20pt gaps as fit
between the side margins, with individual cards capped at 360pt. The
[before](../../demos/super-thread-carousel/evidence/member-grid-before.png)
and [after](../../demos/super-thread-carousel/evidence/member-grid-after.png)
frames use the same 17 covered reports and one report without a cover.

Resize the open window to 1192×780pt, then to 860×600pt. Scroll
with the pointer over the grid and check that it clears Close.
Click a scrolled member, confirm its report title and body, and use Back.
Compare the visible cards and scroll offset on return. Widen the window again
and check the column count. At 500×400pt in the preview, reach the final card
and click Close with the grid scrolled.

Use a report with a cover and an introduction long enough to wrap past three
lines. On its individual Overview card, carousel page and member grid card,
check that the first three lines are readable and the ellipsis ends line three.
Repeat with English and Chinese text, in light and dark appearance, including
a narrow single-column grid. Check that a short introduction stays on one
line. Compare the settled pages after switching to check the cover size and
the alignment of the title, update time and introduction.

The automated Collection journey opens members by semantic Overview target.
For the grid and its return destination, use the same populated, isolated
workspace. Open the page count, scroll to a member and record its frame. Use
a system click and AXPress in separate visits. Capture opening and return.
The Report shell expands from the member and contracts to it on Back. Check
intermediate shell positions, the report title and the **Back to Super Thread
Collection** arrow. Back must restore the grid’s scroll position and member
order. Qualify a read and check that regrouping waits for the grid’s Close.
For a brief read, check the retained carousel cover after closing the grid.

Repeat from an Overview card. Its **Close Super Thread** button returns to
Overview. Check that the panel contracts to the original card. Semantic
state alone cannot certify those frames or system inputs.
See the [member panel contract](../../app/macos/Sources/Host/Overview/README.md#viewed-application-collections).

## External input and isolation

The runner reuses the benchmark's external `Provider`, HTTP adapter and public
scoped-content reader read-only. It records their source hashes and adds only
e2e response text. The provider replaces **model service responses**, not the
native Codex CLI, Harness, Runtime or UI. `BENCHMARK CREATE` / `BENCH ITEM` are
the reused peer's wire markers; no performance measurement is performed.
Actual discovered CLI path/version/digest are recorded, not inferred from PATH.

Each invocation creates a private temporary profile, native configuration/home,
workspace and socket. Child environment contains no inherited API credentials;
only the synthetic peer credential is configured. External HTTPS proxy requests
are rejected; these controls do not claim to be an OS network sandbox. Native
catalog cache/fallback availability is not real-provider availability. No daily
profile, global account/configuration, product debug API or internal log sink is
used. Raw native homes and connection credentials stay outside uploaded evidence.

## Validity, result and evidence

`report.json` separates run validity (`valid`, `blocked`, `invalid`, `incomplete`)
from each interaction (`passed`, `failed`, `blocked`, `not-run`). A successful
operation receipt is not the result: the runner waits for mounted, nontransitioning
postconditions across repeated observations. Expected complete output is checked
by exact UTF-8 size/SHA through a public turn subscription, independently of
mounted execution identities. The provider's own response does not prove delivery.

Exit codes: **0** means all requested interactions passed with valid evidence and
cleanup; **1** means a valid run observed a functional assertion failure;
**2** means blocked/invalid/incomplete execution, unavailable prerequisites,
timeout, corrupt/missing evidence or unreached interactions. CLI parse errors
also use 2. Python optimization is rejected so assertions cannot disappear.

`source.json` records Git revision, dirty status, runner/adapter hashes and CI
run/attempt/ref. Build receipts identify actual binary bytes and source inputs.
`events.jsonl` records phases, process identities and outcomes; `api.jsonl` and
`ui-events.jsonl` retain external operations and observations. Each scenario's
named JSON files retain the actual criterion inputs. `cleanup.json` records
process termination and the private temporary directory. `manifest.json` hashes
all emitted evidence. Offline `verify` checks completeness/integrity and the
reported exit code; it neither reruns the product nor authenticates the author.
Missing files, unknown states and an empty result cannot earn a pass.

The whole run defaults to 600 seconds for `collection` and `all`, and 240 seconds
otherwise. Calls also have bounded local deadlines.
SIGINT/SIGTERM/total timeout revoke execution and enter cleanup. The runner first
requests graceful termination, then fences fallback signals to OS process
identities observed before teardown, including descendants in separate groups.
Forced cleanup invalidates the run. OS-enforced kill, machine loss and children
that escape observation cannot be claimed clean; missing final evidence fails
verification. Temporary profiles are retained locally on both success and failure
for diagnosis; the operator may remove the exact `privateDirectory` after all
owned processes are confirmed stopped. CI retains only the evidence directory.

## CI boundary

[Desktop interaction e2e](../../.github/workflows/e2e.yml) is an independent manual
workflow on one hosted macOS runner. Build, interaction and cleanup are serial;
dispatches queue. Choose `collection` for changes to reading eligibility or
collection projection. The default `supported` choice exercises OVERVIEW, READ and SETTINGS.
Native Codex is explicitly installed at `0.167.0`; the actual
selected executable is still recorded. Environment/version differences from a
local run remain visible. No signing credentials or self-hosted shared desktop
are needed for this development-artifact protocol check. A GUI prerequisite
failure stays nonzero. The workflow publishes evidence on failure as well as
success and fails when expected artifacts are absent. This workflow is not part
of `Complete coverage`, and its existence is not a claim of a hosted passing run.

## Composer system-input boundary

The production protocol has no `composer.send` / `composer.pause` operations.
The optional `--operator-composer` mode packages the same checked Swift executable
and its resource bundles with a unique test bundle ID. It publishes
`operator-request.json` with the exact App path, PID, nonce, Thread and stage.
An external operator activates that App through system Accessibility and performs
the indicated text input and button clicks. No production debug API is added.

```sh
python3 tools/e2e/run.py run --runtime .build/e2e/chief-runtime \
  --app app/macos/.build/debug/Chief --suite all --operator-composer \
  --desktop-lease /private/tmp/mokusei-ui-verification.lock \
  --desktop-owner YOUR_COORDINATOR_THREAD_ID \
  --output output/e2e/operator --timeout 900
```

The operator reads each request and operates only its exact isolated App. The
`activate` stage needs the actual window mounted; `send` and `stop` specify the
synthetic input. For each input stage the operator writes the named receipt into
the output directory after observing the result. Its JSON copies `nonce`, `pid`,
`threadId`, `app`, `stage`, sets `driver` to `system-accessibility`, includes each
listed confirmation as `true`, and retains the actual AX observations in the
nonempty `observations` string. This is an explicit operator attestation, not an
automatically collected AX transcript or screenshot. The runner never creates
these receipts. Operator mistakes and fabricated attestations cannot be excluded
by a hash manifest; the public oracles are independent checks, not author authentication.

Each request includes `inputEvidenceTemplate`. An operator may copy it to the
receipt's optional `inputEvidence` field and record the actual backend name,
TCC host when known, and permission probe tool/status/permissions/artifact.
Probe status is `unknown`, `reported` or `recorded`; `recorded` requires its
bundle-local artifact. Missing values remain `unknown`, not inferred from CUA,
another probe or a successful click. These are operator declarations.

`rawAXArtifacts` and `screenshotArtifacts` are null when archival status is
unknown, empty lists when explicitly not archived, or bundle-local filename
lists when retained. Named files must exist and be present in the manifest.
The report's `inputEvidence.operatorStages` keeps each validated stage's metadata
and receipt separately. A tool-return screenshot or manually summarized AX
observation is not automatically a raw archived recording; Runtime result
artifacts remain independent. Exact per-run probe results and input backends
belong to that report, not a permanent host-capability claim in this guide.

The Send criterion includes an exact persisted prompt, a new execution, exact
completed reply, mounted result and observed empty draft. The second input holds
the real native engine at an unfinished external Responses stream. Stop must be
observed and clicked in the same reader visit, without a close/reopen workaround;
the exact current execution must become `interrupted`, Stop must disappear and
the editor remain usable. Stop is cancellation, not a resumable pause. Source
socket closure alone does not establish successful cancellation. The hold has no
Runtime control hook; cleanup releases it even on failure.

No built-in unattended OS-input driver or hosted Composer run exists. The local
standalone AX probe can lack TCC permission even when the trusted desktop tool
can read and control the isolated App. Missing permissions, missing receipts,
missing controls, a deadline or failed public postconditions remain nonpassing;
HTTP submission is never substituted for Composer input. Keyboard Return, IME,
attachments, other providers, historical/exact-execution input, steering during
active output and recovery after uncertain admission are outside this scenario.

### Chief Compose shortcut

Use a development executable in a fresh isolated profile and hold the shared
desktop lease. Start on a populated Overview with the Chief input collapsed.
With the workspace key, press **⌘⇧B** and immediately type one character.
Check that the focused native editor contains that character when the input
ink appears, without a click or a second character. Record the shortcut and
key timing, focused element, exact draft value and App revision. Repeat after
reactivating the workspace and after restoring a minimized workspace.

Open the input, close it with **⌘⇧B** and reopen it before the Dock finishes
folding. Type a first character again and check that it joined the retained
draft at the saved selection. Repeat after closing before the input first
finishes opening. Also open with a mouse click, wait for the caret, then
switch focus to an Overview filter and verify that the Dock leaves it there.
Check that Escape and outside click still close the bottom input. A Compose
shortcut sent while another app is foreground belongs to that app.

This procedure uses the real workspace menu and system keyboard input. The
[Agent entrance replay](../../demos/moku-panel-transition/README.md#agent-entrance-replay)
separately drives the Compose intent and the responder chain of a non-key
fixture window. Its result cannot establish system event delivery or window
activation. The [Dock contract](../../app/macos/Sources/Host/MokuScene/README.md#dock-and-composer)
defines focus ownership and admission.

### Chief file picker

Use a uniquely bundled production build and an isolated online profile with a
configured Chief. The [Dock contract](../../app/macos/Sources/Host/MokuScene/README.md#dock-and-composer)
and [shared composer](../../app/macos/Sources/Shared/PluginUI/README.md#cards-composer-and-forms)
own the control and its draft import. Start on Overview and click the plus next
to the eyes with the system mouse. Check that the native chooser opens on the
first click, cancel it, and check that the draft text and chips are still present.
Use AXPress on the same button and confirm the chooser opens directly. Select a
known text file, image and empty folder together. Check the two ready file chips
and the single folder chip. Open and dismiss the image preview, then send. Independently read the current Chief transcript through
Runtime and match the user message, attachment names and sizes. Check the
managed file bytes against the fixtures, verify the selected folder path in the
submitted input and confirm the draft clears. A
deterministic external peer can observe native delivery without a provider account.

On a host-enabled draft, Control-click the plus and check that each host option
opens the corresponding file or directory browser. Check English and Chinese. Capture the plus and
the eyes in the same row in light and dark system appearances and at a narrow
width that admits the two-row composer. Inspect the control's
localized accessibility label, action and frame. Keep the commit, app digest,
profile and input backend, screenshots or AX observations, fixture digests,
transcript result and cleanup receipt. This local system-input procedure is
separate from `E2E-COMPOSER-001` and has no hosted runner.
