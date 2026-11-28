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

## Antigravity task dispatch

Run on macOS with Python 3.11 or later and both native executables (`codex`, `agy`) available to Chief. The replay uses a disposable Chief profile, separate native homes and two loopback model peers. The installed AGY supplies the actual ACP session, tool permission and command execution. It uses a temporary Gemini API key accepted by the local peer.

```sh
make runtime
python3 tools/e2e/agy/run.py --runtime .build/go/chief-runtime
```

To also exercise the production macOS Settings and reader, build `xcrun swift build --package-path app/macos --product Chief` and append `--desktop app/macos/.build/debug/Chief` to the Python command in a graphical session. The runner opens that executable with the disposable profile and holds the shared host and desktop verification leases. With Screen Recording access, append `--capture COLLECTOR DIRECTORY` to save the three Settings pages, the Overview card and the Thread reader with the native benchmark collector.

A separate runtime with a controlled PATH first checks a missing executable, another ACP identity and an old Antigravity version. The coordinator then receives the published Antigravity model choices through `moku:submit` and calls the injected `create_thread` tool with a non-default native model. The replay checks its receipt, the exact task reply and a same-session recall. After a Runtime restart it reads both turns by execution ID, resumes the native session, approves one temporary marker file and denies another. Stop interrupts an in-flight prompt. An injected provider error must settle as failed. The coordinator must receive terminal notifications for the completed, stopped and failed executions. The replay rejects explicit AGY role settings and execution catalog requests through the public API. Between restarts it seeds obsolete Chief, Tag and retained Super Thread preferences in the stopped disposable store. Reopening must preserve eligible profiles, role switches, AGY defaults, the selected target and the existing conversation. With the desktop option, the mounted Chief Host row, dispatch row and both independent role pickers must match the declared roles of installed agents. The replay enables Antigravity in the dispatch row and waits for the saved selection before submitting. After restart the reader must show a mounted, ready turn with visible rows. Output identifies the source revision, dirty state, executables' SHA-256, CLI version and model. Real Google account access, physical Settings/approval gestures and visual layout have separate verification boundaries. [Adapter contract](../../internal/plugins/harness/agy/README.md)

## Global voice

Build the runtime, then run the opt-in account replay on macOS with a signed-in native Codex installation, network access and a configured Chief Harness.

```sh
make runtime
uv run --script tools/e2e/global-voice/live.py --runtime .build/go/chief-runtime --harness codex
```

The replay uses a disposable Chief profile and a synthetic microphone. Only the target Chief receives a randomly chosen sentence through its private routing preferences. The recording asks Chief for the sentence. The replay checks WebRTC, a handoff admitted by the selected owner and a successful Talk carrying the exact sentence on its execution. During the replay and a short observation window after each reply, the remote data channel must contain neither a speech append nor the private sentence. The report records whether decoded remote audio was audible. The replay checks the executable’s embedded Go revision against the checkout and records the runtime hash and build dirty status. Use `--rounds 2` to play the identical recording twice on one connection and require two independent receipts and replies. Select `pi`, `claude` or `opencode` to exercise another configured target. For Pi, point `PI_CODING_AGENT_DIR` at its configured agent directory so the temporary home can use the native account. Native account access, available models and provider behavior can change between runs.

For a repeatable destination, use `--harness pi --pi-loopback --rounds 2` or `--harness opencode --opencode-loopback`. Both run the installed harness with an isolated model configuration and a deterministic local HTTP model. The real Codex voice service supplies transcription and may send a brief acknowledgement. The JSON result identifies the model boundary.

The network replay uses a software media peer. `--chief-profile PATH` applies the selected harness’s ordinary Chief Agent execution settings from a JSON file in the disposable profile. A real provider run requires that harness's own native account, model and quota. The result includes the profile digest when supplied.

For a signed workspace, build with `make pack` and run the [system mouse replay](global-voice/workspace.py). It starts the production app with a temporary profile, holds the mounted Bar, waits for its listening orb and clicks to mute. It opens Settings, waits for the Settings close control to replace the orb, returns to Overview and verifies the orb is still muted. It then clicks to unmute and secondary-clicks to exit. The replay checks the signed bundle’s source commit against the checkout and records its build dirty status and the native, runtime and WebRTC hashes. The system Accessibility driver targets only that app's PID and window. The first microphone request requires macOS consent for the tested Chief signature.

```sh
python3 tools/e2e/global-voice/workspace.py --app app/macos/dist/Chief.app
uv run --script tools/e2e/global-voice/native.py --exercise
```

The [local hardware replay](global-voice/native.py) runs the production media code with a loopback WebRTC peer. It observes CoreAudio input and output for the probe PID, sender RTP, decoded remote audio while muted, restoration, disconnect and release. With `--acoustic-loopback`, concurrent room and uplink measurements check local speaker leakage. Adding `--require-input-signal` uses an independent 2100 Hz source to check that near-end audio survives the same playback windows. The default invocation checks existing permissions without starting audio. `--exercise` needs a previously authorized launch host and live audio devices. These hardware and window checks share the desktop lock. The [fixture interaction replay](../../demos/global-voice-mode/README.md) separately covers drag cancellation, navigation, resizing, text ownership and glass geometry. [Native audio contract](../../app/macos/Sources/Voice/README.md)

## Claude thread permission selection

For a live headless replay, use a signed-in Pi coordinator and Claude Code on
macOS. From the repository root, build and start the runtime with a fresh
profile for each sample. Use your normal provider network settings.

```sh
sample=$(mktemp -d)
./scripts/go.sh build -o "$sample/chief-runtime" ./cmd/chief-runtime
CHIEF_HEADLESS=1 "$sample/chief-runtime" start --data-dir "$sample/profile"
python3 - "$sample/profile" <<'PY'
from pathlib import Path
import sys
from tools.benchmarks.adapter import Runtime

runtime = Runtime(Path(sys.argv[1]))
state = runtime.state()
settings = state["settings"]
settings["moku"]["hostHarnessPreference"] = "pi"
settings["moku"]["targetHarnessIds"] = ["claude"]
for entry in settings["pluginSettings"]:
    if entry["id"] in ("report.settings", "tag.settings"):
        entry["value"]["enabled"] = False
settings.setdefault("pluginEnabled", {})["context:artificial-analysis"] = False
result = runtime.invoke("app:update-settings", [{
    "settings": settings, "expectedSettingsRevision": state["settingsRevision"]
}])
assert result["status"] == "saved"
prompt = "请新建一个 Claude Code thread，只回答四月有多少天。"
runtime.invoke("moku:submit", [{"input": {"parts": [{"kind": "text", "text": prompt}]}}])
PY
```

While the coordinator is running, inspect the `create_thread` entry in Pi's
`host-config-*.json` under the profile's `chief-go-state-v1/harnesses/pi`.
Its `parameters.properties.target.properties.claude` contains the advertised
default and required fields. For the ordinary Claude process, match
`--session-id` and `--permission-mode` to the thread's native session. Exclude
short-lived model catalog probes. After completion, read the coordinator's
creation arguments and the child's saved and native-reported values.

```sh
db="$sample/profile/chief-go-state-v1/state.sqlite"
sqlite3 -readonly "$db" "
  SELECT json_extract(op.value,'$.arguments.target.claude') FROM records AS r,
    json_each(body,'$.transcript') AS op
    WHERE r.key LIKE 'thread:%' AND json_extract(op.value,'$.name')='create_thread';
  SELECT json_extract(body,'$.id'), json_extract(body,'$.settings.permissionMode'),
    json_extract(body,'$.sessionState.primarySessionId'),
    json_extract(body,'$.sessionState.runtime.permissionMode'),
    json_extract(body,'$.observation.latestExecution.status'),
    json_extract(body,'$.sessionState.turns[0].notices')
    FROM records WHERE key LIKE 'thread:%' AND json_extract(body,'$.harnessId')='claude';"
"$sample/chief-runtime" stop --data-dir "$sample/profile"
```

Repeat the neutral request in independent profiles to observe model choices.
For an explicit override, append “请将此线程的权限模式设为 acceptEdits。”
For a native restriction, ask for `auto` in an empty temporary task directory
whose `.claude/settings.json` contains
`{"permissions":{"disableAutoMode":"disable"}}`. Compare the saved request,
native initialization and turn notice. A reply-only task establishes the
reported startup mode. Testing individual tool approval decisions requires a
different workload. [Claude permission contract](../../internal/plugins/harness/claude/README.md#native-configuration-controls)

## Overview task card preview capacity

In a native Overview replay, use a running Codex task with an unfinished plan,
Git changes, three eligible message previews and six eligible tool calls. At a
width that gives the main section two rows, check that the two newest previews
appear oldest first, followed by the five latest tool calls in their existing
order. Use long message and tool text to check truncation and verify that every
row fits inside the main section beside the plan and Git panels. Remove the Git
changes from the fixture so the composer gives the main section one row, then
check for the latest message and zero tool rows. Repeat the two-row layout
with one eligible message and two eligible
tools and check that all three appear once. The
[Overview contract](../../app/macos/Sources/Host/Overview/README.md#card-update-isolation)
defines which section controls capacity. A fixture replay can use the
production catalog projector and mounted card to verify presentation without a
live agent session.

## Agent Thread running badge

The [native badge replay](../../demos/running-emoji-badge/README.md) mounts the default
44pt badge in four production card views. Its window recording exercises running,
idle and completed fixtures and the adaptive harness colors. The [Overview probe](../verification/overview-ci-performance/README.md)
checks the active decorations in the mounted workspace against a fixture Runtime.

The [mounted filter replay](../../demos/moku-panel-transition/remaining/README.md)
checks [folder and tag activity](../../app/macos/Sources/Host/Overview/README.md#tag-activity)
while **Reading** is selected. The fixture includes a running task under **Work** in the same folder. The `tag-activity` and `tag-activity-reduced` cases
first sample the 44pt badge and adjacent upper lip of the running card in **Work**,
then verify that switching to **Reading** removes its edge. They inspect the filter
dot pattern, its animation under each motion setting, and its
removal when the task completes. The replay captures the production window.

## Harness Thread Markdown

Run `python3 tools/e2e/thread-transcript/run.py --output /tmp/chief-thread-transcript-evidence` on macOS with a graphical session and the pinned dependencies cached. Specify a fresh output directory. The driver feeds Codex app-server, Claude stream-json, Pi RPC and OpenCode SSE frames to their production parsers and reducers. The replay checks the same manual input identity in all four readers. OpenCode consumes its native inbox event and also replays the authoritative message list twice.

The replay first checks the manifest preview, the turn projection with deferred presence, full execution rows and the text in the native Markdown views. Retained-state fixtures exercise independent equal-text Codex notices, Claude fork history, a Pi extension notification and terminal partial reply, and a targeted OpenCode child reply. Additional frames exercise interleaved Unicode text, reasoning and a tool in Pi, and corrected Claude blocks around a moving review.

A nonactivating panel mounts the ordinary Agent workspace with an isolated content store and live subscriptions. The replay checks native Markdown order, turn state, work controls, group counts and metadata during execution, settlement, permission requests, success and failure. It records paragraph geometry and fonts, unfolds the work summary and remounts the saved turn. The Codex case separates catalog and scoped completion updates and locates an earlier reply by its message link.

The evidence directory contains the revision, platform, source projections, comparison results and images captured from the replay's own windows. Codex samples record changing pixels in the last work summary and its stationary text after the reply begins and after completion. These frames check whether the sweep appears at the right time. Installed CLI transport, real account permissions, database transactions and rendering latency have separate verification boundaries. [Reading contract](../../design/reading.md#content-and-execution-identity) · [Fixtures and launcher](thread-transcript)

### Follow-up image attachments

Use an isolated app and Runtime profile on a graphical Mac. Keep an ordinary
Codex execution running while a follow-up with a managed raster and a text file
is admitted, then open its task card from Overview. To exercise an unavailable
image, remove its managed copy in the disposable profile after admission.
Check the compact text and time, press **Show full text** and capture the
expanded row with **Collapse text** visible. The image should fit without
cropping, and the text file and unavailable image should still show their
filenames. Click the image to check Quick Look opens the original, dismiss it,
and press **Collapse text** to confirm the compact row returns. Record the
revision, attachment inputs, native window captures and observed results.
This check covers the mounted ordinary Agent reader with a retained follow-up.
See the [attachment presentation contract](../../app/macos/Sources/Shared/PluginUI/README.md#harness-transcript).

## AA evaluation context

Capture the public roster and Astra release HTML, then replay the response bodies
through the registered Artificial Analysis plugin and the Context host.

```sh
curl -fLsS https://artificialanalysis.ai/models/ -o /tmp/aa-roster.html
curl -fLsS https://artificialanalysis.ai/models/gpt-6-2-astra -o /tmp/aa-astra.html
./scripts/go.sh run ./tools/e2e/aa-context /tmp/aa-roster.html /tmp/aa-astra.html
```

The [runner](aa-context/main.go) supplies one native catalog identity and starts
with a missing cache directory. The November 2026 Astra scenario requires one
index and one release request, five effort rows, published scores, cost, ten
component measurements, token prices and headline performance. Both median
measurements must be null. After reopening the host without a catalog, its
cached fallback must reproduce each measured row. The JSON output includes
both response digests, requested URLs and the two routing texts. This exercises
the [evaluation contract](../../internal/plugins/contexts/artificialanalysis/README.md)
up to the before-send slot. It supplies no evidence of a model's eventual
routing choice, GUI behavior or live request latency.

## Current scenario contract

[scenarios.json](scenarios.json) is the executable inventory. IDs remain stable
across wording changes; changing a scenario's meaning requires a new ID. Each
entry names its owning module doc and required evidence files. A report always
contains every requested ID, including blocked and unreached entries.

| ID | Implemented interaction and criterion | Prerequisite / evidence | Coverage boundary |
| --- | --- | --- | --- |
| `E2E-ONBOARDING-001` | Confirm discovery, Chief, Tag and Super Thread in order. Select **Configure separately** for both background roles. The enabled model popup must display the inherited selection within 1,000ms of each press. Page changes take under 1,000ms each. The final Dock handoff takes under 1,560ms. | Fresh profile, authorized system AX driver, exclusive desktop. Each press verifies the private runtime PID/epoch, target button and focused test window. `onboarding-ax.jsonl` records inputs and timings. `onboarding-persisted.json` records the saved roles and completion. | Real macOS AXPress, native discovery and Runtime persistence. The final endpoint is the focused, editable Chief composer. Individual rendered frames and live model service behavior require separate evidence. |
| `E2E-OVERVIEW-002` | Check the leading and trailing horizontal limits, open Settings at the trailing edge and return to the same position. | Twelve tagged tasks in the selected folder in the default suite, or mixed cards in the Collection suite. Leading, trailing, uncovered and start snapshots record the poses. | Mounted semantic controls and placement geometry. The [window replay](../../demos/moku-landing/README.md#nested-workspace-header-replay) also exercises native input routing and pointer hits. |
| `E2E-OVERVIEW-004` | Select the folder’s Running tag, switch spaces and return. Choose Completed in a top-level Inbox tag. In the Collection suite, enter Studio’s first tag and click Studio again to view the whole folder. | Tagged project and Inbox tasks plus an untagged Inbox task in the supported suite, or tagged reports and tasks across two folders in the Collection suite. `overview-filters.json` records the Runtime scope and source references alongside the mounted pages. | Checks scoped membership, the available left buttons, the empty Running view and the remembered folder choice. The [untagged work replay](../../demos/moku-landing/README.md#untagged-running-work-and-tag-visibility) checks the running empty state, a live untagged card, first assignment and selection of tags with overlapping membership. |
| `E2E-OVERVIEW-005` | Launch, select filters through mounted controls, relaunch the same isolated profile, fork tasks and classify them. | Three tagged project tasks with distinct tags, one tagged Inbox task and forks with inherited or empty tags. | Checks launch and folder defaults, preference restoration, empty-catalog and unavailable-space fallback, first-assignment selection, batch order, Settings focus and reclassification. |
| `E2E-CHIEF-001` | Open Compose. Retired Note and history commands are rejected and Chief records have no Overview reading targets. | Populated private profile, `chief-controls.json`. | Mounted semantic controls. Menu shortcuts, eye placement and the click target require native window observation. |
| `E2E-READ-001` | Open the prepared Agent from Overview; observe its ready, nonempty mounted turn; deliver an external follow-up; observe its mounted successor; activate the first history entry; Back returns to the successor; Overview closes the reader | Fresh profile, real Codex directory, settled source reply; `creation.json`, scoped content, `ui-initial/current/history/return/overview.json`, `ui-events.jsonl` | Navigation callbacks, content acquisition and mounted turn identity; HTTP follow-up input, not composer submission. Semantic readiness is not proof of exact rendered pixels or text layout |
| `E2E-SETTINGS-001` | Open Settings with Chief Agent selected and only Chief Agent, Auto-Categorization and Super Thread available; activate an unselected `routingPreset` capsule; close through the save gate; read the exact saved preset through public Runtime state; reopen on Chief Agent and observe it selected | Same isolated connected workspace; `settings-before/edited/persisted/reopened.json`, UI operations and public API receipts | Default navigation and the binding/draft/transport/persistence/reopen path for one preset; IME, keyboard, pointer hit-testing, errors/conflicts and system presentation need separate evidence |
| `E2E-COLLECTION-001` | Switch folders, open a grouped report, return and revisit it. Archive and restore other reports while the folder stays selected. | The Library and Studio fixtures contain eight and four tagged reports respectively. Each cites a distinct completed task. Each folder also has a standalone tagged task. | Checks grouping under viewport pressure, selection on return, promotion after reading, folder unread counts, release after archive and regrouping on restore. |
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
open the volume in Finder and check that both filenames are fully visible, with
the app on the left and the Applications shortcut on the right of the arrow.
Confirm the shortcut resolves to `/Applications` and the separate release guide
matches `app/macos/build/alpha-installation.txt`.
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

For a provider-specific replay, add `--onboarding-host opencode` to the run command.
Discovery waits for that Harness and the driver selects it on the Chief page.
For each role, the driver reads the inherited model, presses **Configure separately**
and hit-tests the enabled model popup in the focused window. The field must show
the same selected title within 1,000ms. The trace records the field ID, both values
and the press and observation timestamps.

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

### Onboarding Agent configuration reuse

Use a disposable first-run profile with OpenCode and a second ready Agent.
Drive the mounted setup controls and observe `onboarding.canContinue` and
`onboarding.editorReady` through the [interaction socket](../native-interaction/README.md).
For request attribution, count Runtime entries to `harness:settings-presentation`
by Harness, execution owner, application setting and refresh flag. A disabled
confirmation alone cannot establish that a read occurred. These checks concern
the [onboarding resource contract](../../app/macos/Sources/Host/Onboarding/README.md).

1. On Tag Agent, choose **Configure separately** and select OpenCode. With a
   delayed first Tag/OpenCode reply, switch to another Agent and back before
   the reply arrives. Expect one Tag/OpenCode presentation and confirmation
   gated until the selected catalog and draft are ready.
2. Within five minutes, choose **Use Chief**, restore the separate settings,
   go **Back** to Chief and return to Tag. Leave and reactivate the app twice.
   Expect zero additional Tag/OpenCode presentations for those actions.
3. Continue to Super Thread, then return to the saved Tag step. Check that
   the same profile is selected. Change the saved Tag/OpenCode profile from a
   second client and watch the Tag editor revalidate. Expect a read for its
   new source and an enabled confirmation after it settles.
4. Open Super Thread’s separate OpenCode editor. Count its first presentation
   under `report.settings`. On a failed read, check that the error and retry
   are accessible and that **Start using Chief** waits for a usable result.

Record the source revisions, build identities, request starts and completions,
and readiness at each action. Record any injected reply delay or simulated
activation notification. A simulated notification exercises the mounted handler;
system focus, rendered frames and native CLI launches require their own observations.

### Onboarding Chief reasoning effort

Use a fresh profile with Codex and a second ready Agent. Record the build,
the mounted confirmation's enabled state, `onboarding.editorReady`, the draft
and catalog revisions, and Runtime starts for `harness:settings-presentation`.
Use the [interaction socket](../native-interaction/README.md) for choices and
a separate Runtime client for persisted readback.

1. On Chief, switch to Codex and select a different supported reasoning effort.
   Exercise the ordering where the settings event arrives before the save
   response. Once the receipt arrives, expect the new effort in the saved
   revision, an enabled **Continue**, and zero new Codex/Chief presentation
   reads. Confirm and check that Tag Agent opens.
2. On another visit to Chief, change the saved Codex profile from the second
   client. Hold the new Codex presentation response. Check that **Continue**
   rejects activation on Codex, becomes available on the other ready Agent,
   and waits again on returning to Codex. Release the response. Expect a single
   Codex/Chief read, the externally saved value and an enabled confirmation.

Record any synthetic delays separately from time observed in a screen recording.
The [first-run contract](../../app/macos/Sources/Host/Onboarding/README.md)
defines the resource and save gates.

### Onboarding Agent configuration loading layout

On both Tag Agent and Super Thread Agent in a disposable first-run profile,
choose **Configure separately** and select an Agent with a delayed
first configuration reply. Capture the mounted window while **Loading Agent
configuration…** is visible. Compare the center of the combined skillet and
label with the horizontal center of the picker and the midpoint between the
picker's bottom edge and the navigation row's top edge. Resize the window
while the read is pending. Where the content fits, both centers should still
match. Where it overflows, check that the notice can be reached by scrolling
and that the navigation remains visible. Release the read and confirm the
form replaces the notice.

Record the tested revision, app artifact, fixture delay, window sizes, and
captured frames. The [onboarding layout contract](../../app/macos/Sources/Host/Onboarding/README.md)
applies to the separate configuration editor on both pages.

### Onboarding Agent configuration form spacing

In a fresh profile with ready Codex and Pi catalogs, open **Configure separately**
on the Tag and Super Thread Agent pages. Select Codex and capture the form with
**Advanced options** collapsed and expanded. Compare the vertical distance
between the Model and Reasoning effort popups with that between Service tier and
Permission mode. With equally sized rows, those distances should match.
Collapse and reopen the disclosure to check that it reserves no space for hidden
fields and that the previously selected values reappear. Switch to Pi and check
that no empty disclosure or advanced rows remain. Return to Codex and confirm
the disclosure starts collapsed and the basic fields keep their spacing.

Record the revision, app and catalog fixture, disclosure states and measured
popup frames. See the [onboarding form contract](../../app/macos/Sources/Host/Onboarding/README.md).

### Harness resource notice spacing

Mount the OpenCode execution form with a ready catalog in the Settings or
onboarding form presentation, then with a fixture that shows a resource notice
and Retry above the same fields. At the same width, compare the first popup's
vertical offset from the top of the editor. The increase should equal the
notice's rendered height, including its own padding. The distances between the
Provider, Model and OpenCode model variant popups should be identical in both
states. Repeat in wide inline and narrow stacked Settings layouts.

Record the revision, catalog fixture, viewport width, and notice and popup
frames. See the [shared form layout contract](../../app/macos/Sources/Shared/PluginUI/README.md#model-and-reasoning-selection).

### Full-surface loading mark

Run the [same-window native replay](../../demos/chief-logo-loading/README.md#原生加载标记).
Compare the painted width from bowl to handle with the sleeping skillet on the
Running empty state. Both should span about 191 pt at full size. Inspect two
consecutive 2.8-second cycles for a dip, staggered release, catch and continuous
return through the resting pose. Compare the two Reduce Motion captures for a
stationary pan and icons. Switch motion on again and check the icons lift.
Admitting the fixture catalog should replace the mark with the Running empty
state in the same window. Keep the revision, window frames and recording.

For a complete launch, delay the background service of a disposable returning
profile. Release it while the mark is moving and check that the ready workspace
takes over. Record the delay and the first ready frame.
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
permission and questionnaire controls and editor reversal
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
   first-run form mounted. Check that onboarding stays dark and keeps its setup step. On the Chief
   step, select Pi Agent and OpenCode in turn and check that each mark is
   legible against the black character. Settings should stay dark on the active tab. In each system
   appearance, close Settings and reopen it using the Overview gear or the Settings keyboard shortcut.
   Check the dark background, header eyes and legible form labels. Open the
   Chief Model menu and choose an available model. Under Auto-Categorization,
   switch between Agent off and Configure separately. Check that the selected
   mode and visible fields match, then close Settings and inspect Overview.
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

### Recent-thread contrast and hover

Use an isolated workspace with read Agent Threads and no unread results, or
build and open the [native empty-state fixture](../../demos/empty-state-native-candidates/README.md).
The fixture mounts the production list with sample data on a solid canvas.
Use the built workspace over a saturated gradient for the desktop-material
check. Follow the [Overview presentation contract](../../app/macos/Sources/Host/Overview/README.md#recent-threads-at-empty-status-filters).

1. In Light and Dark, capture the empty Unread and Running views. Cover solid
   and wallpaper-backed windows, then repeat with Reduce Transparency and
   Increase Contrast. On a neutral backdrop, check both lists for an idle face
   and rim without gold coloring. Wallpaper can contribute color to the glass.
   Sample the label and row ink and the adjacent fill in sRGB. Use a 4.5:1
   contrast floor for titles and timestamps.
2. Hover the single-row list, then the first, middle and last rows of a
   populated list. Include the top and bottom end insets when pointing.
   Check that only the active row changes fill, that the fill follows the
   panel corners with no strips of the idle face and that the text remains
   readable. Check that hover, press and the inset keyboard focus outline
   stay neutral, including at the outer corners.
3. Activate a row with the pointer and with the keyboard. Confirm that each
   opens the indicated Thread and returns to the same filter after closing.
4. In the isolated workspace, open the last unread Agent Thread and wait for
   its result. Close it and check the first Recently read row as it appears.
   Repeat with Reduce Motion and compare the row face and rim with the settled
   empty state.

Record the revision, fixture or profile, effective appearance, background,
accessibility settings, input route, frames and contrast samples. A static
export covers only the flat face and resting text.

### Workspace full-screen backdrop

Use a built Chief and an isolated profile with Overview visible. In both light
and dark appearance, capture the windowed workspace, enter macOS full screen,
wait for the transition to finish, then capture the workspace again. Convert
captured pixels to sRGB. Sample unobstructed canvas near the edges and above
or below the cards. The solid backdrop should be `#E9E7DF` in light appearance
and `#20211F` in dark appearance. The cards and reader panels retain their own
surfaces. Exit full screen and confirm the windowed material has returned.
Record the commit, build, capture method and sampled coordinates.
[Workspace window contract](../../app/macos/Sources/Host/WindowNavigation/README.md#window-and-reading-navigation)

### Demo related execution draft

Open a built Chief with `--demo` or launch **Chief Demo.app**. Open **Checkout release brief**, then
select **Trace the discounted receipt** under **Related executions**. Wait for the Chief Bar below the
execution to show its text editor. Type a distinctive draft. Return to the related list and confirm that
the input closes. Reopen the same execution and check the text. Open a different report's execution
and confirm its draft starts empty. Quit and reopen the demo, then check the first execution again.
It should now have an empty draft. Record the commit, build, launch method and the visible text and
Dock position at each step. [Demo reader contract](../../app/macos/README.md#read-only-demo-workspace)

### Settings factory reset

Run `python3 tools/e2e/factory_reset.py /private/tmp/chief-reset-evidence-UNIQUE`
on macOS with a graphical session. The [replay](FactoryResetReplay.swift) mounts
the production workspace and routes AppKit mouse events through its own window.
It checks early release, dragging outside, a single confirmation during a
continued hold, cancellation with saved settings intact, and explicit erasure.
A fresh process must mount onboarding, restore default Runtime settings and
replace the old Chief conversation. The runner uses temporary app and agent
homes, a legacy SQLite profile and a real detached Git worktree. It checks a
removed draft and Codex plugin catalog clone and preserved external files.
Offline maintenance exercises a current profile with a one-shot Codex home.
It rejects a linked worktree at the catalog path, a catalog backing an external
worktree and an unexpected nested checkout before allowing a standalone clone
to be removed. It also rejects
a missing or mismatched confirmation, an occupied ownership port, a
symlinked cache directory and unexpected transfer files. It retries after
the obstruction is cleared. The output records the revision, local
observations and isolated profile. System-wide AX and physical input
are separate boundaries.

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

### Chief Talk execution links

In an isolated workspace, send a Talk message with links to two different runs. Click one execution capsule in the compact bar. Check that the reader starts at the cited run’s heading, including when the task has since run again. Close the reader and right-click Chief Bar. Click the other link in the saved message and check its run independently. Repeat from another tag and from a Super Thread whose related card cites a different execution. After a fresh notification hides at one minute, follow the link from conversation history again. An invalid URL stays readable. A deleted Thread shows an unavailable notice. A missing run in an existing Thread opens the unavailable historical page.

The [mounted two-surface replay](../../demos/moku-landing/README.md#talk-execution-links) uses window-addressed mouse events, an isolated catalog and cached execution content. It checks full visibility for a short multiline reply and the scroll-to-link path for a saved report above the current submission limit. The [live conversation replay](../../demos/moku-landing/verify_conversation.py) checks native Return, public dialogue and restart against a private Runtime and loopback provider. Its `--failure-resend` scenario clicks Resend in both the compact Bar and history, checks the saved request and reply, reopens the profile, and attempts to reuse each consumed failure.

The same mounted replay checks [message web links](../../app/macos/Sources/Host/MokuScene/README.md#talk-execution-links) in a compact reply and in sent and received bubbles. It compares displayed text, accessible web capsule labels, appearance selection and exact link handoffs. It checks that dragging selects the capsules without dispatching a link and that punctuation and unsupported syntax stay visible. The callback observes the system-open request inside the replay window. Browser launch and page loading are outside this fixture.

### Chief Bar opening

The [mounted opening replay](../../demos/moku-landing/README.md#chief-bar-opening)
checks the latest message’s visible end, scrolls to the first message, visits
the earlier page and returns to the latest page. It opens the Bar with a
window-addressed secondary click and dismisses it with an outside click. It checks
the reading position across a content revision and window resize.
Its window movie supports frame-by-frame review of
the eyes, composer and transcript during expansion and dismissal.

### Chief navigation

Start with a private profile containing a Chief conversation and a completed task. A saved selection for the current Chief or a retained Chief archive must open Overview. Open **View → Compose** and inspect its accessible controls. A plain Command-B leaves the current route in place. Check that retired navigation actions are rejected, then open an ordinary task and a Super Thread from Overview.

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

### Overview unread bookmarks

The [native Unread preset replay](../../demos/moku-landing/README.md#unread-preset)
checks the mounted left-rail entry, untagged completed-result admission, removal
after marking the tag as read, localized zero results and
reappearance after a new execution arrives. Switching top-row folders and tags in Unread
must show the bookmarked members counted by each badge, including a task shared
by two tags.

The [native tag press replay](../../demos/moku-landing/README.md#mark-a-tag-as-read)
checks bulk acknowledgment from the left rail, pointer cancellation, shared
counts, saved version receipts and a later completed run.

Use a private profile with an individual Super Thread and an ordinary completed
Agent Thread. In the native window, capture the two emoji badges, open each
reader, wait for its content in the key window and return to Overview. The red
bookmark disappears on the visited card. For the background case, open the
reader while the test window is inactive. Check that no receipt appears until
the reader comes to the foreground. Restart Chief with the same profile and
check both badges again. Provide a new HTML revision and another completed
execution for the same IDs. Each badge should show its bookmark again until
that version is displayed. Keep the window captures and profile receipt set
for each step. Also check the red count on each containing tag before and after
opening a bookmarked card, including a shared child tag, a covered execution
and a Report collection. Selecting a tag preserves the count. When its last
unread version is acknowledged, the number disappears and the selected
glass keeps its tint. With an active member in the same tag, check that its
perforated activity indicator also remains visible after the unread count clears.
Choose a directory at normal window scale. Select a tag with an unread count
and move the pointer away. Capture the expanded selected tag. Click the top folder button, hover over the previous tag to reveal its title, then move away and capture it during contraction. Check the selected tint and confirm that
the complete red badge stays at its upper trailing corner. Try a short
name and one long enough to truncate. Switch folders rapidly and change a tag's
unread count while its title is visible, including to zero. Check the selected
folder's count in the top bar and each visible tag's count in the left column.
Repeat with Reduce Motion. [Bookmark contract](../../app/macos/Sources/Host/Overview/README.md#unread-bookmarks)

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

### Agent card input focus

Run `python3 demos/moku-panel-transition/workspace/composer_focus.py /private/tmp/chief-agent-focus` with a new output directory on macOS.
The replay builds the current workspace and holds two private Codex tasks in their first execution with a loopback provider.
It clicks the visible cards and Close controls in a mounted workspace, types through the window's first responder, clicks back into the editor, revisits the first draft and opens Compose on Overview.
A second offscreen panel receives a key while the workspace is hidden and its scene is inactive. On return the next key must reach the original Agent draft.
The panels use window-local AppKit events and stay outside system key-window arbitration. System activation and physical input methods require separate evidence.
The output includes the build receipts, observed drafts in `focus.txt` and owned-process cleanup. [Composer focus ownership](../../design/composer.md#route-input-and-focus)

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

### Overview space restoration

Run the [desktop command](#build-and-run) with `--suite overview-spaces`. This
suite starts the normal application with its private profile and automation
socket. A prepared Runtime supplies completed tasks, with no desktop
preferences at the first launch. It relaunches with an explicitly selected empty Running tag and with the older directory preference fields. Mounted filter buttons select the left tag,
top folder and Inbox tag. The folder button exercises first entry, restoration,
invalid-child fallback and return to the entire folder. The runner also selects a semantic tag named after the project and checks its individual card. With every tagged task archived, it restores an unassigned task, holds a real Codex follow-up at the external peer, and observes the running card before and after Tag Agent assigns it. Runtime archive and classification operations vary tag availability. The final relaunch leaves an older saved catalog on disk and
checks selection against the Runtime. The first observable
populated Overview must already select the expected filter and project its
exact card IDs. The settled state must also mount those cards and the selected
control. `overview-spaces.json` records process IDs, preference values and
snapshots for each stage. A tagged fork created while Settings is open selects
its source tag behind Settings. A mixed classification batch selects the first
newly tagged fork in Runtime catalog order. Restoring and reclassifying these
tasks after relaunch keeps a manually selected folder. An Inbox fork switches
the underlying tag while a project reader stays open. Returning shows the
Inbox cards. This semantic replay does not measure pixels or
system pointer input.

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

With Reduce Transparency off, check that the member grid sits on a rounded
regular Liquid Glass panel during opening, scrolling and return. With Reduce
Transparency on, check for the opaque reading fill. In both cases the member
cards retain their own opaque surfaces and Close retains its glass style.

On Overview, compare the carousel with a standalone Super Thread card. The
surface and border, cover gap, metadata and emoji backdrop share the ordinary
card treatment. Hover to reveal the Liquid Glass navigation capsule, use an
arrow to switch pages, then move the pointer off the card. Check that the
navigation capsule disappears and the upper-right glass count remains.

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

For visible-caret latency, record three untyped Compose openings per build
in a populated, key Overview window. Use the same window size, appearance,
capture scale and input driver for both builds. On each video, mark the first
frame where both shell edges are within one pixel of their settled positions,
then locate the first visible insertion stroke at the editor's text origin.
Use frame presentation timestamps. Record both times and the signed difference.
A caret already visible at arrival has zero post-expansion wait. Keep the
preceding frames, the window recording and the separate typing/focus
observations with each build's identity.

This procedure uses the real workspace menu and system keyboard input. The
[Agent entrance replay](../../demos/moku-panel-transition/README.md#agent-entrance-replay)
separately drives the Compose intent and the responder chain of a non-key
fixture window. Its result cannot establish system event delivery or window
activation. The [Dock contract](../../app/macos/Sources/Host/MokuScene/README.md#dock-and-composer)
defines focus ownership and admission.

### Chief file picker

Use a uniquely bundled production build and an isolated online profile with a
configured Chief. Hold the shared desktop lease and operate only the isolated
app. The [Dock contract](../../app/macos/Sources/Host/MokuScene/README.md#dock-and-composer)
and [shared composer](../../app/macos/Sources/Shared/PluginUI/README.md#cards-composer-and-forms)
own the control and its draft import. Start on Overview and click the plus next
to the eyes with the system mouse. Check that the native chooser opens on the
first click and that it shows the current user's Desktop. Navigate to a
different folder and cancel. Check that the draft text and chips are still
present, then click the plus again and verify the chooser starts on the Desktop.
Cancel, use AXPress on the same button, and confirm the chooser opens directly
on the Desktop. In an Agent composer with a known explicit working directory,
check that its plus opens the chooser in that directory. In the default Chief
composer, select a known text file, image and empty folder together. Check the two ready file chips
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
