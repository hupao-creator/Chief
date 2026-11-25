# First-run onboarding

`NativeOnboardingState` admits a new profile after the authoritative workspace
catalog and Moku shell load. It owns the discovery → Chief → Tag → Super Thread → Dock
sequence; the connected workspace continues to own installation discovery,
settings resources, draft validation and Runtime persistence.

A valid preexisting desktop preferences file or actual catalog activity skips
first-run setup. An empty Chief history from a default Harness change, settings
revisions and prefetched execution snapshots do not establish prior use.
The profile stores an explicit pending marker before setup,
so restarting during setup preserves all saved choices and returns to discovery.
A pending marker takes priority over subsequently created history. Marker write
failures stay visible and retryable. Completion is written only after the last
settings flush succeeds; ordinary preference writes preserve that state.

The floating panel keeps the landing background and uses a neutral window
surface with untinted Liquid Glass controls. The panel, hosted controls, and
Tag and Super Thread animations inherit the system appearance. During the
noninteractive handoff, the contracting surface takes on the Dock's capsule
color. Discovery reveals each ready Harness by logo and name. Pending Harnesses share
a single progress indicator. Each failed Harness has its own error and retry. An executable alone is not discovered:
readiness joins the workspace's retained Moku execution and enabled independent
background-role resources for that Harness. Inherited roles join
Moku's exact resource, so readiness does not wait for unused application scopes.
Configuration prefetch begins after that Harness is confirmed installed, leaving
the shared queue available for other installation replies. Each Harness queues
its execution resources ahead of ordinary Thread defaults in the same batch,
without a phase barrier that holds defaults behind execution retries. Defaults
are not read by any subsequent onboarding page and do not gate discovery or its retry;
they continue warming separately for Settings. Harnesses without execution-host
capability still require their ordinary resource. This includes each plugin's decoded
model catalog, capabilities/options and nonempty saved execution snapshots.
Transport/decode failures, CLI failures and embedded catalog errors remain errors;
background retries are bounded (1 and 3 seconds) and never count as completion.
Codex/Pi/OpenCode require usable model catalogs; Claude supports custom model
identifiers and can legitimately have an empty advertised list. OpenCode waits
for the account phase that can still filter model availability, not usage telemetry.

The title shows discovery in progress, then the ready count, installation prompt
or discovery failure. Continue requires at least one ready Moku-capable Harness and
does not wait for unrelated slow/failed Harnesses. It admits the current ready
roster into Moku and the role pickers; returning to discovery can admit newly
ready Harnesses. The admitted roster remains stable across execution-profile
saves, while each active editor still enforces its own readiness and validation.
The same cached, source-keyed surfaces supply the subsequent editors immediately;
page changes do not reload successful resources or reseed selected defaults.
If discovery publishes other settings while a first-run draft saves, the draft
and the new revision can reconcile automatically when they agree on every
changed field. Overlapping edits still surface the conflict and preserve the draft.
The workspace admits the saved source when the draft adopts it, including when
the Runtime event arrives before the local save reply. A local Chief/Codex
profile confirmed exactly as submitted can reuse its fresh catalog. The
fields display the current draft and the catalog keeps its original expiry. Switching to a loading Agent or receiving a different saved source from
another client gates Continue on that source's own readiness. Disabled roles
need execution resources only when enabled.
Plugin-owned installation guides remain available for missing Harnesses. Moku reuses the
Settings coordination map and native Harness execution fields. Tag and Super Thread
reuse application-owned background configuration, including inheritance and
retained independent profiles. Provider catalogs, pending model choices and
validation remain in their native plugins. Model, reasoning and other select
fields use AppKit system popups through the compact presentation environment,
with the same option identities, disabled states and discrete-change bindings
as Settings. The shared readiness registry
combines resource acquisition and incomplete local input; IME, failed saves,
unavailable Harnesses and invalid fields prevent advancing.

Inherited Tag and Super Thread configuration displays the actual saved Moku profile
through the same read-only native Harness fields as Settings, including catalog
and resource status. It waits for resource readiness rather than treating the
presence of a saved profile as sufficient. Switching back to independent mode
restores its own retained configuration.

Opening the independent editor loads the selected Harness catalog in the role's
workspace. During the read, the skillet and “Loading Agent configuration…”
form one notice centered horizontally and vertically between the Agent choices
and the bottom navigation. If the window is too short for the notice to fit,
the content can scroll while the navigation stays in place. The editor's
read-only preview uses retained settings when available and Chief's saved
profiles on first use. Returning to that role and Harness during
a read joins it. Once ready, the editor can reuse that role's presentation for
five minutes across Back, mode changes, Harness switches and app activation.
A changed saved profile, workspace, installation or connection requires its
own current resource. Tag and Super Thread have distinct workspaces, so each
can have a cold first read for the same Harness. Inherited discovery still
joins Chief's resource. Confirming waits for the revision-checked save of the complete draft.
The save does not reacquire native snapshots for the copied profiles or recheck
the selected Harness's native catalog.

Below the independent Harness picker, basic and expanded advanced fields use
the shared Settings form rhythm. The field stacks get their spacing from each
row's vertical padding. **Advanced options** starts collapsed, and
conditional fields only occupy space while visible.
See the [form spacing replay](../../../../../tools/e2e/README.md#onboarding-agent-configuration-form-spacing).

Tag and Super Thread share Settings' Agent off, Use Chief and Configure separately
choices. Turning a role off keeps its source mode and retained independent
profile, and bypasses that role's resource/availability gate. Selecting either
enabled choice restores the ordinary readiness gate. Existing reports, tags and
pending backend work are retained.

The Tag SpriteKit and Report SwiftUI sequences are abstract capability examples,
shared with Settings through `NativeRoleConfigurationPanel` and with the visual
demo. Role titles and subtitles are shown during onboarding. Each mounted Tag
or Super Thread page plays once with the discovered Harness logos and retains
its completed composition. When OpenCode is available, the Tag animation uses its
plugin logo for Improve search, Update dev docs and Explore shortcuts in both
the scattered and grouped cards. Settings uses the same behavior
without onboarding step admission. Leaving the page cancels playback; entering
it again creates a new playback visit. Hiding or deactivating the window during
playback settles to the completed composition without replaying on activation.
Tag
also rebuilds a static final frame on size, appearance, locale or Harness changes
after playback starts, and pauses SpriteKit once that frame is rendered. Tag's
collision boundaries remain invisible. A native `SKView` adapter makes both the
view and its backing Metal layer nonopaque and clears the layer before presenting
the scene. This keeps tab entry transparent before SpriteKit's first drawable;
a clear scene background alone does not configure the native host. Ordinary
updates retain scene identity, and unmounting pauses and detaches it.
No native Tag-surface capture suite is configured in this source tree;
transparent host/layer state and playback lifecycle are production constraints,
not a claim of continuous-frame coverage.
The Super Thread illustration gathers dense documents into one landscape document.
Each of its three abstract figures sits directly above two placeholder lines.
The illustration has no visible text and exposes a single accessibility description.

Setup keeps the composer unmounted until the final save. Each page's controls
become available when the transition completes and the editor is ready. After
persistence, the panel fades its contents over 140ms while preparing the hidden
Dock, contracts to the laid-out Dock over 780ms, then reveals the Dock behind
the panel's fade. These stages advance on animation completion. Workspace input
and accessibility become available after the reveal. In an active, visible window, the
resident eyes stay open through the 180ms final fade and blink once for 320ms
as the input box comes fully into view. Leaving the foreground or hiding
the face during either interval cancels the cue for
this handoff. **Start using Chief** gives the visible editor keyboard focus when the handoff finishes in the active app.
See the [first-run handoff replay](../../../../../tools/e2e/README.md#first-run-handoff)
for the window capture procedure. The one-time marker is independent of empty-workspace landing:
archiving all conversations still restores landing without replaying setup.

The deterministic [visual demo](../../../../../demos/landing-setup/README.md)
uses the production surfaces with in-memory data. It does not establish Runtime
persistence, real discovery, focus, input or native-frame correctness. The
Settings e2e starts with onboarding complete. The
[verification policy](../../../../../scripts/ci/verification-policy.md) defines
validation ownership.

The Super Thread role uses the Super Thread Agent application settings label.
Onboarding progress keys and the `report.settings` binding preserve completed
onboarding and saved execution configuration.

The explicit App launch option `--benchmark-scenario overview` prepares an
isolated rendering experiment by recording completion before workspace creation.
It requires `--data-dir` and the opt-in automation socket. The external runner
does not navigate or measure this setup flow; ordinary launches retain the
first-run admission above. Scenario preparation does not alter rendering or
native Harness execution.

The Overview benchmark entry also requests a fixed 1280 × 820 initial window
and disables scene restoration for that explicit scenario. This removes saved
window geometry as a startup variable; the OS bounds remain externally verified.

## Confirmation e2e

[E2E-ONBOARDING-001](../../../../../tools/e2e/README.md#onboarding-confirmations)
launches first-run setup with a fresh profile and uses macOS AXPress on each
confirmation. Discovery → Chief, Chief → Tag and Tag → Super Thread each
have a strict budget below 1,000ms. Super Thread → Chief's focused input has
a strict budget below 1,560ms, including the full 1,100ms visual handoff.
The run measures confirmation through persistence, preparation before fade, each
animation through logical completion, and reveal completion through AX focus.
Persistence and preparation before the fade must take under 260ms combined.
Post-reveal AX focus must take under 200ms. The replay checks each animation's duration. A page
is interactive when its own enabled confirmation is available. The final
destination requires the workspace's enabled attachment control and its focused,
editable composer. Both background roles are configured separately in the UI;
the run checks their saved settings and the completion marker after the handoff.

While the setup panel is waiting for admission, the shared skillet loading mark is centered in its content area. Setup errors retain their recovery controls.
