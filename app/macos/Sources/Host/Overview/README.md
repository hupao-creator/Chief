# Overview

[NativeOverviewWorkspaceModel](NativeOverviewWorkspaceModel.swift) projects public catalog records into visible cards, tags and selection. [NativeOverviewCanvas](NativeOverviewCanvas.swift) owns structural geometry; the registered plugin supplies each card's semantic content. All placements in the selected layout remain mounted, including outgoing cards through exit. Camera movement alone does not mount/unmount cards or start structural transitions.

[Membership facts](NativeOverviewMembership.swift) separate filter membership from
streaming card content. Admitted catalog deltas carry changed identities into the
workspace; content-only changes compare those identities' facts and refresh only
selected changed card slots, without scanning or sorting the selection.
Activity-only mutations do no catalog/card work. Full snapshots, explicit refresh,
locale changes and reordered surviving records retain full reconciliation.
Same-patch removal and upsert of an existing identity, including renderer recovery
at the same revision, retains its slot and follows the changed-record path. Only
real creation/deletion or an explicit relative reorder marks structure dirty;
membership facts still invalidate affected scopes when the replacement changes them.

The [membership index](NativeOverviewMembershipIndex.swift) retains identities and
selection results per canonical scope. Execution, visibility, archive, tag and
scope changes reselect only affected old/new scopes. Unscoped applications have
reverse label dependencies so their matching directories and Inbox semantic
filters remain current. Coverage uses exact execution sets rather than checking
every selected application for each task. Stable per-scope order comes from the
admitted catalog positions; changing one scope cannot reorder equal-date records
in another. Cached inputs, membership facts, directory labels and results are
bounded by current catalog identities and exposed filters and are released on stop.

Global conversation availability is updated from changed eligible records before
tag filtering and report coverage, including directory-only documents. Moku
uses these facts for its empty-workspace landing; an unloaded catalog remains
unknown. The All membership is invalidated lazily and resolved when browsing or
tag activity needs it. Filter chrome and Moku still receive the complete filter
description
when membership changes, so producing that public output scales with the output
size; unrelated scope selections and card projections are reused. Selecting a
filter or changing card geometry retains the ordinary complete selected-layout
transaction.

While the first creation awaits native admission, the canvas and filters stay
covered by landing so a durable, unadmitted shell cannot replace the primary
input. Ordinary eligibility rules, including archive and terminal visibility,
are shared with Overview rather than reimplemented by the Dock. Each scope selection
normalizes its distinct labels once. The
[CPU benchmark and scenario matrix](../../../../../tools/verification/overview-performance/README.md)
distinguishes model work from GUI and GPU work.

Ordinary Overview cards, including Agent Threads and individual Reports, use
opaque palette surfaces and a soft border, including completed cards.
Super Thread collections provide one continuous regular Liquid Glass plate
behind their cover, metadata and intervening layout space. Their policy's
`providesCardSurface` omits the Canvas's opaque shell; glass remains in the
semantic camera plane so scrolling updates its backdrop geometry. Collection
emoji badges opt into regular glass with a light mint tint at the unchanged
44pt diameter / top 12pt / trailing 17pt metadata seat. Reduce Transparency
uses opaque palette fills; the material helper falls back to system Material
when Liquid Glass is unavailable. Other card content keeps the shared flat
policy for provider badges, terminal marks and plan highlights.
Running Agent Threads show a diagonal sweep of harness-colored perforations
behind the stationary emoji. Reduce Motion holds the pattern still. Idle badges
have a neutral fill and completed badges have an accent-soft green fill and
terminal symbol. Their accessible labels follow the projected execution status.
The isolated `--benchmark-agent-emoji-badge liquid-glass` scenario can compare only
Agent emoji backdrops with regular glass; ordinary launch defaults and all other
card materials remain unchanged. See the [external comparison](../../../../../tools/benchmarks/README.md#agent-emoji-badge-material-comparison).
Only Super Thread collections opt into the new card material; individual Report
and ordinary Thread surfaces stay flat.
There is no `glass world` preference. The filter capsules, Moku,
Settings and shared controls outside a card keep their own materials.

Overview cannot originate steer/send input for a specified Thread. Emoji badges
retain their status presentation. For an unarchived ordinary Thread whose latest
execution was explicitly interrupted by user Stop, with no pending input or
background work, the badge becomes an independent Archive conversation button.
Hovering the card or focusing that button replaces the emoji with a close icon;
Return/Space and accessibility activation archive without opening the reader.
The Host rechecks current catalog eligibility, blocks duplicate requests and
displays failures on the card. Other interruption sources, including unknown
historical provenance, do not acquire this action. Badges have no Send swap or
draft callback. The Harness overview renderer receives only an existing-interaction
response callback plus ordinary reading navigation, rather than full thread
actions. Permission/question responses remain available; those are bound to a
current pending interaction. There is no per-card message editor, text/file drop
target or send shortcut. Horizontal scrolling, Return-to-open and card activation share the mounted canvas. The independent Moku composer,
Thread-detail Moku input, Browser annotation sends and general Runtime APIs
remain owned by their existing boundaries. Moku tool operations do not decorate
card borders; returning from a reader must not replay an operation-completion
edge flash. The workspace-level running list-refresh indicator remains separate.

Overview projects a finished `interrupt_thread` from its tool acknowledgement.
The compact catalog carries just the batch `ok`. A detailed transcript can
identify each target by its argument position and matching Thread ID, including
duplicates. A missing or mismatched acknowledgement leaves the outcome unknown.
Tool dispatch errors remain failures. [Operation projection](NativeOverviewMokuOperations.swift)

## Card update isolation

[NativeOverviewContentStore](NativeOverviewContentStore.swift) separates the
latest semantic snapshots from the canvas's structural inputs. The workspace
installs it synchronously at each admitted catalog transaction; the canvas reads
only its structural revision and retains a stable slot for each mounted
structural identity. A content-only change updates that card's slot directly,
without rebuilding the canvas body, its two placement loops or a second
`items`-to-`rendered` state copy. The production delta path updates only changed card slots and attention identities;
structural changes retain the full selected-layout transaction. Array-based
fixture hosts feed the same store and layout state machine.

Each card retains separate Equatable shell and semantic boundaries outside its
spatial frame. The shell keeps a neutral palette surface;
the semantic wrapper observes its current item, including completion. Geometry, motion,
visibility, viewport, locale, decorative policy, activation and explicit
renderer/state identities still invalidate the appropriate wrappers. Completion
changes reach the badge through the semantic wrapper's observed item.

Slots are keyed by structural identity, including footprint and internal
structure, rather than thread ID alone. Leaving the current collection or
changing footprint freezes the old mounted slot at its last compatible content.
The model retains those slots' current presentation IDs alongside the latest
structural snapshot until exit finishes. Newer content can adopt an existing
slot only for the same structural identity; a different incarnation starts its
own slot. Source replacement retires the old ownership.

Presented placements have an identity index rebuilt only with a new layout. Each scroll input checks the current attention identities against that index,
so finished and unrelated placements do not participate. The empty attention set
returns immediately.

Offscreen attention changes notify the mounted coordinator without routing
ordinary text updates through canvas attachment or moving the camera. Structural, scene and viewport changes refresh the visibility callback. The workspace's empty-state and Dock
reservation read separate presence facts, not the high-frequency item array or
complete Moku thread.

The card closure captures stable owners. Callers replacing its renderer must
update `cardContentIdentity`; the workspace supplies its model identity, and the
identity reaches the innermost Equatable content boundary. Callbacks use a stable
workspace-owned reference whose current receivers are refreshed when the
workspace view is rebuilt, so mounted actions reach the latest receiver without
remounting.

The body counter is an observation-boundary diagnostic, not a CPU/FPS
measurement.

The production card closure enables native derived scans. Both the scan and
the running badge use Core Animation and receive viewport visibility from the
canvas. The badge only mounts for a running status. The Release probe checks
the mounted decorations on the production workspace path.
See the [native decoration contract](../../Shared/PluginUI/README.md#native-overview-decorations).

## Accessibility gesture ownership

The canvas groups its accessibility children and exposes horizontal scroll actions.
Each Agent card groups its title, status and embedded actions before attaching its
open gesture. Tab can focus cards and buttons. Return opens a focused Agent card.
Entering Overview leaves keyboard focus to the normal window responder chain.

## Layout, motion and input

The logical cell is 320×196pt with a 16pt gap. A 1×2 card is 320×408pt
and a 2×1 card is 656×196pt. The [layout solver](NativeOverviewLayout.swift)
uses current membership in product order, card spans and the usable viewport.
It scores regular grids and packs mixed spans into horizontal and vertical
bands. Candidates must fit the available rows, or the tallest single card
when it exceeds the available height. Within this limit, the best natural fit
wins, followed by smaller area and width. A column pass includes the exact row
limit so the next cards can extend to the right. Mixed-span passes consider
up to 65 strip sizes per orientation and retain up to 64 disjoint openings.
Within the chosen grid, the solver checks the space between occupied columns
across the full height of a candidate card. It pulls cards from lower rows
into these openings, including openings across strip boundaries. It visits
upper rows first and prefers taller cards, then wider cards that fit. Equal
footprints keep their existing reading order when competing for an opening.
Returned placements follow product order. Empty input has no projection.
Invalid identities, spans, metrics or viewport sizes produce a layout error.

A projected arrangement that fits in the window with a 16pt clearance on
each side stays centered with zero horizontal travel. Packing uses its preferred
side margins even when centering uses some of that space. A wider arrangement
starts at the preferred leading inset and scrolls until its last card reaches
the matching trailing inset.
Cards retain their natural size unless a single card is taller than the usable
height, in which case the projection scales all cards uniformly to fit that
height. Packing and camera framing leave 30pt above and below the grid area.
Preferred side margins are 64pt, or 32pt at window widths up to 620pt. A dimension that
cannot fit both preferred margins with room for cards uses its full extent, including for the fit check.
The top filter bar, side filter columns and Chief Bar overlay the cards. Packing,
centering, collection budgeting and horizontal travel use the full window.
Control heights and the visibility or width of a side column leave the framing
geometry unchanged. A click on a visible filter activates its button. Gaps
between buttons pass the click through to the underlying canvas or card.

The workspace retains one horizontal offset in memory while a reader or Settings
covers the canvas. A resize, filter change or membership update clamps that
offset into the new range. An empty layout resets it to zero. The profile
persists card and filter data independently of layout geometry.
[Design and example arrangement](../../../../../design/overview.md)

The layout transaction publishes the latest placements and projection together.
Content-only changes keep card slots and reuse geometry. A newer structural
snapshot cancels the previous worker. Interrupted card transitions start from
the sampled poses and release outgoing cards when their exit completes.
Presentation pauses gate pointer and accessibility input while preserving the
ordinary appearance of embedded controls.

Tag scene changes retain their filter choreography: outgoing cards shrink
and fade over 140ms, survivors move over 320ms after a 70ms delay, and new cards
enter over 230ms after a 150ms delay. The new collection first lays out at frozen
start poses; only that layout's acknowledgement starts the shared clock, so plugin
construction cannot consume the transition. The projection is installed before that layout. Reprojecting
the sampled card poses preserves their screen-space origins. Rapid selections
cancel the old owner and retarget those samples. An empty destination retains the
camera through the exit before disposing it; switching from an empty scene still
animates entry.

Within a visible canvas selection, authoritative catalog changes use the
160ms upward shrink and fade when a card leaves. This includes eligible Agent
Thread and Report archive, linked Threads hidden by Report archive, and
visibility or coverage changes that remove a placement. Status and content
updates that preserve membership keep the mounted card. When the final
workspace card leaves, the Dock's landing composer takes input immediately
while the empty canvas layout finishes the card's exit. **Clear all history**
is a workspace reset under Settings, where the covered canvas coalesces
catalog changes and resumes from the latest projection.

Card motion starts, interruption samples and display samples all use
`ProcessInfo.systemUptime`. A MainActor clock shares one uptime sample for each
exact SwiftUI timeline date across the shell and semantic planes. Dates are only
tick identifiers, so wall-clock drift or adjustments cannot accumulate into the
motion's elapsed time. The clock retains the 64 most recent distinct ticks.

The spatial frame builds its content when receiving new inputs and reuses that
view value across animation ticks. Ticks only sample the pose and apply its
geometry, opacity and accessibility state; they do not rerun the shell/semantic
content builder. New card inputs still replace the value without changing its
mounted identity, and child state, Observation and environment updates remain
live.

[NativeOverviewStageCoordinator](NativeOverviewStageCoordinator.swift) serializes card spatial motion with Moku.

### Overview scroll input

[NativeOverviewScrollInput](NativeOverviewScrollInput.swift) routes window-local AppKit wheel events.
The [vertical gesture router](NativeOverviewVerticalSwipe.swift) recognizes an
unmodified, precise trackpad contact after at least 24 points of vertical travel
and more than 1.5 times its horizontal travel. The initial pointer location in
the Overview window chooses the column. On the left, a swipe steps among the
current directory's visible tags, including its unrestricted first choice. On
the right, it steps among Running, All (initial) and Completed. A physical up
swipe advances to the next choice below. A down swipe selects the preceding
choice above. From All, up selects Completed and down selects Running under
either Natural Scrolling setting. The gesture stops at either end. Crossing the
middle or receiving momentum cannot advance the other column. When the left
column is hidden, including in global All and on an Inbox tag, a left-half
vertical swipe keeps both selections.

The background, cards, carousel cover and filter controls accept these gestures.
Horizontal starts retain their original owner through reversals. The
[Chief Bar](../MokuScene/README.md) reserves its Note target. Vertically
overflowing native viewports keep scrolling at either limit. Open Note, editing,
interventions, onboarding, Settings, readers and collection panels keep their input.

Status filters apply to the selected tag's eligible members after report coverage and before layout and collection budgeting. Running includes pending submission, an active execution (running or waiting for the user), or background work. Completed uses the existing successful completion fact with no pending submission or background work, and includes Super Threads individually or collected. Idle and visible interruptions with no ongoing work appear only in All. A status change reprojects membership for the current view when a catalog delta admits or removes a matching card. The tag hierarchy, redundancy rules, counts, activity indicators and current tag selection use the full eligible catalog.

The [status empty states](NativeOverviewStatusPresentation.swift) put the
[sleeping Chief skillet](../../Shared/PluginUI/Resources/ChiefOverviewIdle.png)
at up to 156 × 68 pt inside one regular Liquid Glass panel with the localized
title and scroll hint. The text provides the group's accessibility label.
An adaptive tint strengthens contrast behind the text, and Reduce Transparency
uses an opaque panel. The panel passes input through to Overview. On the
right half of the Overview filter surface, a vertical line-wheel event can exit an empty status
filter in its return direction. Scroll up from Running or down from Completed
to return to All while keeping the selected tag. An empty All status shows a
localized title and tag-switch hint on an opaque surface. A left-half wheel event keeps the selected status.
The [status replay](../../../../../demos/moku-landing/README.md#overview-note-swipe-at-actual-size)
exercises empty and populated states and both input types.

The outlined right-hand emoji identifies the status, including when the view is empty. The existing plugin cards keep their layout and
activation. Hover outlines emphasize cards and keyboard focus outlines Agent
cards. Agent cards show the localized time of the latest successful execution
from its public `finishedAt` in addition to its duration. Super Threads retain
their document update time and collection selection.

A trackpad contributes its horizontal delta, including native momentum. For
canvas travel, a line wheel uses its horizontal delta when available and
otherwise its vertical delta, at 40 window points per line. Pointer presses interrupt inertia. Dragging the
window header moves the window. Empty canvas presses leave the offset alone.
Native editors, the horizontally scrolling top filter bar, the Dock and carousel cover retain their own input.
Settings, readers and active text entry gate canvas scrolling. Card focus keeps
horizontal arrow navigation and Return available. Opening the Chief input
explicitly hands focus to its editor.

A superseded layout worker cannot pause input after a newer layout has settled or reused its geometry. Geometry reuse applies when the current membership and viewport are unchanged; a structural slot refresh then updates content without invoking the solver. Recovery from an interrupted entry, resize or exit samples the current poses and starts the latest presentation, so transparent entrants and retired snapshots are released. No reading-position edge seat is retained.

## Tags and filter transitions

Selecting a chip reconciles against the admitted catalog and projects the selected
membership into card slots. Full Report cover HTML is requested on mount and
reused by revision and appearance. On a switch into a directory with several
standalone Report cards, the plugin schedules browser mounts across main-loop
turns so metadata and cached posters can enter with the card transition.
[Report cover contract](../../../../../internal/plugins/applications/report/README.md#cover-cards)
and [mounted switch benchmark](../../../../../tools/verification/tag-space/README.md).

Global All is pinned beside the top row of project directories and Inbox semantic
tags. Inbox is the scope for work without a persistent directory, including
managed temporary roots. Each of its exposed tags has its own top button with
an emoji and title, even when Inbox has only one tag. Inbox tags with equal
member counts sort by localized tag name, independently of their emoji. Global All includes
eligible untagged Inbox tasks. A workspace containing only those tasks shows
All by itself at the top. The empty landing hides the bar. Choosing a project
directory selects its full membership. Its top button keeps its name and folder-wide unread count when
a child is selected. A project directory named Inbox and a semantic tag named
Inbox have distinct identities, icons and memberships.

The left column starts with **Any tag** and then the selected scope's visible
semantic tags, ordered by descending member count and localized name for ties.
Any tag includes eligible untagged directory members. The column appears only
for project directories with visible children, including when a child is
selected. The three status choices on the right are shared across all scopes. Selecting a directory or tag
keeps the current status, including when the resulting card set is empty.

Semantic tag identity is a plain name with separately validated emoji. Each
scope exposes up to five semantic tags. Directory membership uses persistent
scope identity and excludes managed temporary roots. A symlink alias or linked
checkout with another label remains in its canonical directory’s All view, and
same-named directories stay separate.

The left column omits a directory's sole semantic child when its actual selected
Agent Thread ID set and application thread reference set both equal the
directory's sets. This uses eligible catalog membership after the ordinary
visibility/archive and report-coverage rules; equal member counts
alone are insufficient. Untagged members or directory-only documents that change
those sets keep the child visible. Multiple semantic names (including a name
equal to the directory label) prevent this omission.
Catalog membership changes recompute the decision. Canonical filters, navigation,
published context and stored tags remain intact. An already selected semantic
child stays visible and selected even if it becomes redundant, preserving its
filtering meaning when later threads arrive. Selecting its directory then omits
the redundant child. If a directory child leaves the catalog, its directory
becomes the selection while that directory exists. Removing a selected Inbox
tag or project directory returns to global All. If a reader covers Overview,
the published filter selection updates immediately and the canvas refreshes on
return. A change in status-filtered results alone keeps the selection.

The left and right Liquid Glass columns sit at the window's edges, each group
vertically centered. Compact controls are 42pt circles. The left controls show
the semantic emoji, 🏷️ for a tag without an emoji, or an asterisk for Any tag.
Hover expands that button inward. Its natural width is the 42pt glyph seat
plus the measured single-line title and 12pt trailing padding. The expanded
button is capped at 172pt or 15% of the window width, whichever is smaller.
A long title truncates at the trailing edge. The same title stays mounted as
the capsule reveals or clips it, including when a hover reverses mid-animation.
Selecting another tag shows its title for five seconds. A subsequent selection starts a
fresh five-second interval for the latest choice. A hovered tag keeps its title
until pointer exit, including after the selection interval expires. Expansion
and contraction use the Chief Bar’s 420ms smooth Overview capsule animation
with zero extra bounce. Reduce Motion applies the width change immediately
and preserves the display interval.

The right controls show ⏳ (Running only), 🗂️ (All statuses) and 🏁
(Completed only). Hover help gives the localized status name. Global All,
project directories and Inbox tags use native regular interactive Liquid Glass
and system primary foreground in the top row. The left tag and right status
buttons use native clear interactive Liquid Glass. Each selected button tints its glass. The unselected
buttons keep the base material.

Semantic tags and status choices take their tint from the dominant color of
the displayed emoji, including the 🏷️ fallback for a tag without its own
emoji. The renderer samples the system glyph in sRGB and averages pixels in
its most common hue cluster. When colored detail covers less than one sixth
of the visible glyph, the tint uses its average luminance as a neutral gray,
limited to the range 0.30–0.72.
This keeps the 🏁 status tint neutral. The top folder buttons, global All,
the Any tag asterisk and glyphs that yield no visible sample use the Overview
accent. The emoji keeps its original colors.
[Emoji tint sampling](NativeOverviewTagTint.swift).

Each tag's red unread count follows the upper trailing corner of the glass
at its current animated width. Increased Contrast and Reduce Transparency
strengthen the selection tint. Reduce Transparency also supplies an opaque
background. Accessibility exposes the full name and selected trait even when
the visible title is hidden or truncated. Member counts are available in tag
accessibility values.

[NativeOverviewChrome](NativeOverviewChrome.swift) keeps All pinned beside
a horizontally scrollable row of project directories and Inbox tags. The
centered bar leaves space for the window controls and actions. At viewport widths of 620pt or less, the filters
occupy a second row. The 42pt capsules share their height with the traffic-light
capsule and circular actions. The single-row bar sits 16pt from the top. In the
two-row layout the actions sit 10pt from the top and the bar sits 76pt from the
top when space permits. A short viewport moves the row up to leave room for
canvas input. Header dragging and scroll exclusion end at 60pt in the single-row
layout or 2pt below the bar in the two-row layout. See the
[shared UI motion boundaries](../../Shared/PluginUI/README.md#motion-and-materials).

## Tag activity

Directory and semantic tag chips show a diagonal sweep across a field of tiny
dots when their browsing membership contains a Thread whose public
`isExecutionActive` is true (running or waiting for user). Background work
alone does not qualify. The selection tint and red unread count remain visible
independently of activity.

A transparent 26pt disk sits behind the folder icon or Inbox tag emoji in
the top bar. A 36pt disk sits behind the semantic tag’s emoji on the left. Core
Animation sweeps the Overview accent across fixed perforations in the same
pattern as the running Agent badge. The icon and emoji stay still, including
while a tag title is expanded. Reduce Motion holds a single lit diagonal.
Hiding the workspace, scrolling the chip out of view, hiding or occluding the
window, or detaching the view stops the sweep.

The indicator follows the same archive, visibility and Report-coverage rules as
the browsing membership. A Report itself contributes no active Agent Thread.
A changed-ID cache refreshes activity when execution participation or membership
changes. Streaming content updates can reuse the cache. Global All and Any tag
expose active presence in their localized accessibility value. The visible
indicators belong to directory and individual semantic chips.
[Tag activity rendering](NativeOverviewTagActivity.swift) and
[shared badge renderer](../../Shared/PluginUI/Cards/RunningThreadBadge.swift).

## Verification boundary

The [property boundaries](#property-boundaries) describe the generated geometry
and mounted convergence checks. Geometry checks cover vertical containment and horizontal reachability at the two bounds. Mounted state reads rendered frame identities and
camera projection; it does not certify control-region geometry, Report content,
reading transitions, physical gestures or captured appearance.

## Production interaction controls

[NativeOverviewInteraction](../Interaction/NativeOverviewInteraction.swift)
exposes camera operations and actions registered by the mounted filter controls.
Directory and semantic-tag selection use the same callbacks as the visible
buttons. Filter-bar scrolling uses the mounted top row. A retiring registration
cannot remove another view's callbacks.

Runtime `state:load` supplies scope/membership facts independently of mounted card
identities, placement cells and camera bounds. Overview exposes no tag CRUD or
multi-selection controls. The PBT target does not exercise the interaction driver.

The generated geometry and mounted-state input domains, assertions and runnable
commands are defined in [Property boundaries](#property-boundaries).

The [performance tools](../../../../../tools/verification/overview-performance/README.md)
measure internal CPU paths; the [external benchmark](../../../../../tools/benchmarks/README.md)
observes fixed-count app rendering with explicit measurement limits.

For a native check of the empty-workspace handoff, use an isolated profile
with one ordinary Thread and Moku. Stop that Thread, then use its Overview
archive button. The card leaves while the Moku composer becomes available.
Mounted geometry properties do not exercise this handoff.

## Agent reading panels

Reading entry shares the 420ms emphasized panel curve with tag-chrome withdrawal
and the resident Dock. The tag controls slide upward over the canvas.
See the [reading choreography](../../../../../design/reading.md)
for secondary Sidecard admission and cancellation.

The presentation gate and prepared return apply to Agent and Report panels.
Report returns to its document card.
All sample their destination only after the refreshed canvas preparation completes.

The outer reading stack pauses Overview projection when opening begins. Cards
fade completely out during travel. Once the panel settles, it hides the separate
native host and reuses the window's existing ultra-thin material as the background;
it never rasterizes Overview or retains even blurred cards. Input, tracking and native layout
therefore do not need to traverse the retained cards for foreground reading.
Catalog installation, membership/filter context, selection validity and Moku
operation state continue at each runtime transaction. Hidden transactions coalesce
the display's sorting, plugin projections and content installs;
the mounted canvas also defers layout (including viewport changes). Existing card
snapshots, native controls, drafts and camera remain retained. Settings, Git
monitoring, runtime, notifications keep their existing lifecycles.

Before an animated return, the stack unhides the same host at the latest viewport,
resumes projection and awaits a new canvas
preparation receipt before sampling the current source frame. Removed/archived
cards cannot supply that destination. Preparation is cancelled with its route;
replacement, focus loss, disconnect/recovery and direct returns cannot let an old
waiter close a newer visit. A reversal during opening uses the participating parent
immediately. Hidden and foreground structural changes both resolve to the latest
snapshot; omitted intermediate geometry is not replayed. These reading-panel
lifecycle paths are outside the generated Overview property domain.

Opening an Agent Thread captures its displayed card frame from the stable layout
and live camera transform. The shared reading stack expands that shell into an
opaque panel with equal horizontal margins, while retaining the Overview camera
and cards beneath it. The retained Filters and Settings chrome slides upward by
its full height and fades out over 200ms without scaling its labels or changing
card positions, including in the narrow two-row layout. Closing reverses the
same transition; interrupted openings retarget the mounted chrome. Hidden chrome
remains excluded from hit testing and accessibility.
The production conversation content fades in unchanged; title, emoji and author
have no separate morph. Closing refreshes the source position after viewport
changes when available. Direct/restored entries without an eligible card use a
small centered expansion instead. Route identity and cancellation
remain owned by the shared reading stack.

Reports expand from their own card. The shell uses that identity to refresh
the return frame after layout changes. Git summaries remain read-only card metadata.

Agent card title/emoji leaves register weak native anchors with the workspace's
identity registry. Only an actual ordinary open captures text and geometry;
this adds no projection cache or per-frame catalog publication. The destination
reader owns the independent opening handoff, and return still uses the refreshed
canvas frame and actual card content.

Ordinary failed executions remain hidden by default. Interrupted executions are
hidden only when their exact latest execution ID matches the Runtime-owned
`mokuInterruptedExecutionId`. User Stop and missing/unknown historical sources
remain visible. A successor execution stops matching the old provenance. The
shared Shell predicate governs Overview, availability and ordinary
navigation; membership invalidates when its resulting visibility changes, even
if status and execution identity stay unchanged. Archive/unarchive choices,
plugin-owned application visibility and explicit result-reading links keep
their existing rules. Refresh and restart consume the retained envelope rather
than guessing from terminal status or local UI actions.

Ordinary browsing ignores retired agent-authored visibility markers. Archive, execution eligibility and Report coverage retain their own selection rules. Detail reading sends no per-thread visit or foreground-time receipts to Runtime; application collection reading remains independently owned by the desktop.

## Unread bookmarks

Folder and semantic chips show a system-red unread count at the upper trailing
edge for their exact browsing membership. Each eligible Thread contributes once
per space, after visibility, archive and execution coverage filtering and before
collection grouping. A directory chip always uses the whole directory’s count.
Inbox tags show their own counts in the top row. A project tag’s badge follows
the upper trailing corner of the left capsule as its title appears and
disappears. All and zero-count chips have no badge. The count is included
in the accessibility value independently of member count and activity. It
does not change chip width, selection, ordering or the Runtime filter context.
Receipt and catalog version changes update counts even for unselected spaces.

The emoji badge shows a system-red bookmark for each unseen Report content revision
and for an ordinary Agent Thread whose latest execution completed and has no read
receipt. Collection members use their own document revisions. An open route,
preview, loading placeholder or related-execution list cannot acknowledge content.
The key, foreground reader acknowledges the revision reported ready by WebKit or
the selected settled execution body on its active page after entrance. Reading
a completed execution in the Report's open sidecard can acknowledge that execution.

[Profile-local read receipts](NativeThreadReadHistory.swift) live in the desktop
profile's `thread-reading/` directory. The client creates one immutable file
per type, Thread ID and version. Revisiting that version is idempotent. A new
revision or completed execution starts unread. The collection visit timer and
ranking keep their independent rules.

## Viewed application collections

Report opts into one two-cell collection per selected space. The Host first applies
visibility, archive, directory/tag selection and exact execution coverage. It
uses the full individual footprints, including offscreen cards. A report with a
cover costs two cells and a coverless report costs one.

When a Chief Note link targets a Report in a visible collection, the carousel pauses automatic
advance and selects that member. The reader opens through the card’s ordinary
opening path after the target page settles. A brief visit retains that member
as the return page while it remains grouped. The [Note link contract](../MokuScene/README.md)
covers dismissal and navigation back to the Note.

The [profile-local reading record](NativeOverviewCollectionReading.swift) determines
default membership across views. At **30 minutes** from the end of the last visit
(or creation for an unvisited report), a report defaults to collection. Overview
samples age on presentation and space changes. Idle time alone does not schedule a
live canvas move. Two idle reports can share a collection even in a spacious window. A
lone idle report stays individual until there is another member to group with it.

Opening a report and reading its uniquely associated Agent Threads share one
visit. Ownership follows catalog Thread identity across execution changes and
updates on rebinding. Ambiguous standalone Agent routes have no owner. With the
reader admitted, focused, visible and connected, monotonic foreground seconds
accumulate once across the visit. Covering or losing focus pauses the clock.
Qualification occurs at 25% of the report's full static body reading estimate,
clamped to 5–45 seconds, inclusive. A second distinct visit with positive
foreground time also qualifies if it begins less than 24 hours after the
previous foreground visit closed. Page selection and report updates do not
create visits. Each visit samples its estimate on open.

Qualification restores the default individual presentation. Under pressure the
[budget](NativeOverviewCollectionBudget.swift) selects idle members first, then
members without qualified visits, then qualified members. Within each class,
creation or the latest qualified visit orders candidates, with stable ties.
The first trial keeps all reports individual except default idle groups. It uses
the same window size, creation order, footprints, packing and camera projection
as the canvas. Zero horizontal travel, including an exact fit, keeps that layout.
When it overflows, each eligible type in product order takes the shortest ranked
prefix of at least two members that fits. When every prefix still needs scrolling,
the least horizontal travel wins, with fewer members on ties. A collection occupies
its oldest member’s seat and lists its members in their original creation order.
The fully grouped trial bounds the search in dense views. A prefix can be
skipped only when its occupied cells exceed even the space reachable at the
best measured scroll distance and the smallest possible projection scale.

Resizing, changing filters or changing the selected cards or their footprints
repeats the trial from the individual cards. A pressure group releases as soon
as space allows, including after returning from a reader. Until the window has
a positive measured size, only default idle groups apply. Scrolling the canvas
moves the camera and leaves group membership alone.

Opening uses the real report identity and the current source card. Prepared
return resolves the latest placement. A returned member that remains collected
occupies the cover until the user selects another page. Diagnostics distinguish
the profile's default from actual membership in the current space. Persistence
errors are reported and the session continues with its in-memory reading facts.

The Report plugin owns `NativeReportCollection`: a cover preserving its 360:308
logical viewport ratio slides horizontally while the remaining metadata region
stays in place and switches through the shared
`ThreadCardInkMask`. Cover and ink use one 460ms ease-in-out progress; backward
paging mirrors only the mask so the reveal follows cover travel. Outgoing ink
stays above incoming ink. At the current 320×408pt grid footprint, the cover is
273.8pt high and metadata is 130.2pt high. WebKit and its poster share a centered, uniformly scaled
360×308 CSS-pixel viewport, including for existing fixed-width HTML.
The 4pt layout spacing and card shell stay fixed;
the spacing is filled by the same glass plate as the body, without an exposed
background seam or a separate body glass edge. It reuses `NativeReportCover` and `NativeReportCard`
with `showsCover: false`, rather than duplicating metadata. Coverless reports use
their emoji on the ordinary surface. Arrow/dot/menu controls use native Liquid
Glass; the collection owns its regular-glass outer plate while the Canvas
retains geometry, clipping and hit testing. During page travel,
metadata gates pointer/accessibility/actions without disabling its visual label.
Open and archive callbacks recheck the current collection pose, including an
already-open context menu; accepted archive work may finish across page changes.
Carousel buttons and menu remain natively disabled, with the disabled boundary
inside the surrounding glass surface rather than around it; this preserves
keyboard/accessibility safety without restyling the material. Their ButtonStyle
keeps the ink appearance stable during the temporary lock.
The page menu uses the button menu style to inherit that same ButtonStyle;
the native borderless menu style would dim the x/x label during every turn.
The count and navigation glass inherit the workspace color scheme; selected
page markers use primary ink and unselected markers use secondary ink, retaining
the capsule/dot shape distinction in both light and dark appearances.
The entire lower navigation capsule mounts only while the pointer hovers this
active, visible collection. It is centered in an overlay at the bottom of the
fixed cover viewport, so mounting it leaves the cover, metadata and upper-right
count in place, including when all seven page markers are visible.
A transparent SwiftUI mask cannot reliably suppress
the native Liquid Glass surface; removing the surface also removes its invisible
hit targets and accessibility children. The upper-right count stays available
for keyboard/accessibility member navigation. Opening/closing the member panel,
focus loss, leaving the card and offscreen removal clear hover; keyboard focus
and menu tracking never force the capsule visible. Carousel timing remains
independent of hover.
A native cover input region retains pointer drag and trackpad input instead of
moving the canvas; its horizontal paging and pinch region remain reserved for the
collection cover.

The upper-right page count opens a scrollable, adaptive grid of the exact ordered
collection members, using the ordinary Super Thread cards and their open actions.
The glass capsule is sized by the padded label and inset 14pt from the top and
trailing edges of the cover. A vertical offset centers the visible digits and
slash within the capsule.
The panel preserves the filtered collection order (creation time, stable ties),
including members outside the carousel's four-cover preload window. Its cards keep
the ordinary opaque surfaces, archive actions and native trackless scrolling.
The count expands from the collection card into the workspace's centered reading
panel, using `NativeCollectionPanelPresentation`, the same `NativeReadingPageStack`
compositor, window-relative margins and emphasized 420ms opening as Agent/Report
readers. Overview and Dock fade out and reject input/accessibility while the panel
is open; this is not a screen-sized popover or a zoomed canvas child. The panel
uses a rounded regular Liquid Glass backdrop throughout opening, scrolling and
return. Close floats in the upper-left corner and stays fixed as rows scroll.
Resizing reflows the open grid even if its source card temporarily leaves the
Overview viewport.
The grid uses the panel width and member count to fit 280–360pt cards with
20pt gaps. Short collections form a centered group near the top. When a card
fits between two 54pt side margins, the first row starts 20pt below the top
and the scroll viewport reaches the top edge. The leading margin clears the
32pt Close button and its 14pt inset throughout scrolling. Below 388pt wide,
the single-column viewport begins 54pt below the top and uses 14pt side
margins. Below 320pt, the 320pt layout scales to fit the panel, including its
scroll viewport and hit targets, so the cover, title and badge fit together. Cover
height preserves 360:308, with a separate metadata region. No panel dimension can
extend beyond the host viewport. Reduce Transparency gives the panel an opaque
reading surface matched to the current appearance.
The carousel pauses through opening and return; closing starts a fresh dwell.
Escape, Close and blank-margin clicks reverse the panel into the current card
frame. The count is behind the expanded surface, not a second floating control.
Activating a member gives the Report reading stack its visible card frame in
workspace coordinates. The stack expands the same native panel as an Overview
open. Back returns to the retained member grid and uses the member frame at
return time. The grid keeps its scroll position and cover playback state. Its
controls and accessibility children are inactive while the reader covers it.
Overview entries show Close and return to their current Overview card.

Reading evidence and foreground time accrue during the reader visit. The grid
holds the pre-visit grouping rank of each member read from it until panel
dismissal, when Overview applies reading-driven promotions. Archive continues
to update the open grid. The lower carousel menu and arrows select pages.

The selected ID is shared by cover, metadata, opening and semantic navigation.
Automatic advance follows an 11-second dwell while foreground, visible and not in
a cover gesture. The dwell starts after the incoming page finishes travel and
WebKit acknowledges cover playback; loading does not consume it. Manual advance
resets the dwell. Offscreen and hidden collections stop advancing. Their covers
pause the current motion/hold, and preloaded neighbors stay at their beginning.
Each cover animates for at most 6 seconds. Collection covers play once per
selection and hold their final composition until paging; standalone covers hold
for 5 seconds after animation completion before replaying. Returning to a selected
page replays from its beginning.
Standalone application cards receive foreground/presentation activity through
the shared animation environment too.
Active/visibility loss and membership replacement settle the current selection and cancel its
motion owner. Only the stateless mask identity is replaced; settled metadata
subscriptions and in-flight card actions remain mounted. Cover geometry ignores
interpolated offsets once settled, preserving
mounted WebKit identities instead of reloading them to cancel travel. Transition ownership
prevents overlapping turns and opening intermediate content. At most four covers
mount (current, retiring and neighbors), regardless of collection size; larger
collections use the page menu instead of an overflowing dot row.

The [production-backed demo](../../../../../demos/super-thread-carousel/README.md)
provides headless model exports and manual viewing without running a Runtime.

There is no Cmd+F conversation search, search menu/interaction action or Runtime
keyword index. Tag filtering and Agent `grep_threads` remain
independent capabilities; native text editing keeps its own find behavior.

Collection member cards expose an icon-only Archive Super Thread button over the
upper-right cover corner (or the equivalent corner without a cover), alongside
their existing context menu. The button retains its accessible label and help.
Pending archive work replaces the icon with a spinner in the same 32pt target;
its accessible label and help announce that work is in progress.
Both invoke the same atomic
application archive command: hide the report and its persisted associated ordinary
Threads. UI membership and counts follow the authoritative catalog, not optimistic
per-card removals. While the member panel remains open, an outgoing card keeps
its last content and grid seat for a 160ms fade and slight shrink. It immediately
stops accepting input, leaves the accessibility tree and pauses cover playback.
Other members and Close remain available. Each exit has its own deadline.
A returning reference resumes in the same mounted card with the current data.
A surviving selection is retained; removal of that selection chooses a
remaining member. If the new projection selects fewer than two eligible
members, the panel closes and each remaining report appears individually. Archive
changes no execution, background task, history or binding;
explicit archived reading and actions remain available. Errors retain the member
with retryable feedback. The panel and carousel keep their existing close, hover,
scale and cover timing contracts.
Member controls use the observable panel owner to admit drawing-time and invoked
actions. The retained panel content must not infer admission from a captured
card-local `showingMembers` State value: it can still hold the pre-opening value
and leave archive disabled. Closing, inactive and removed-member guards remain.

## Property boundaries

**PBT-OVERVIEW-COLLECTION** compares the chosen prefixes with the scroll range
of every legal prefix for each type in order. Mixed ordinary cards, one- and
two-cell reports, idle floors, up to two types, and fractional sizes around row
and column boundaries exercise packing and ties. Generated foreground spans
straddle qualification and one-day boundaries and exercise pause/resume and
distinct short visits. The [mounted journey](../../../../../tools/e2e/README.md#current-scenario-contract)
checks filtered membership, return selection, promotion and release after archive.
The [window replay](../../../../../demos/moku-landing/README.md#nested-workspace-header-replay)
checks wide, exact-fit and narrow sizes, including unavoidable scroll travel.

**PBT-COLLECTION-REGROUP** exercises the production Report catalog, Overview
projection and panel lifecycle in temporary profiles. Generated traces start
with 9–12 fresh two-cell reports and visit up to three seats in each of one or
two panel sessions. Visits span 1–7 foreground seconds with a 5-second
qualification threshold and can repeat. Reading evidence must advance while
member order stays fixed through reading, Back and the start of Close. After
dismissal, the oldest unqualified reports must fill the available group seats.
A failing trace shrinks by deleting visits and sessions with the same failure.
This checks deferred grouping across visit sequences. The grid’s mounted
scroll position, controls and animation frames require the native replay.

**PBT-OVERVIEW-GEOMETRY** calls the production pure layout solver with 0–18
unique product-ordered cards (1–3 columns, 1–2 rows), usable viewport widths
240–2,600pt, heights 1–1,600pt and origins −400…400/−200…200pt. It uses the
shipping height-limited projection. The [generated property](../../../Tests/Properties/NativeOverviewGeometryProperties.swift)
checks exact membership/order/spans and uses the specified 320×196pt cell and
16pt gap to check the frame union against the solver's production metrics.
Each nonempty input also supplies column spans for a single row in a window,
at natural or half scale. Window widths include the row and two 16pt clearances,
plus −0.5, 0, 0.5 or 16pt. The property checks centering and exactly zero
travel for a fitting row, and both endpoint insets for overflow.
It checks both vertical margins, including the 60pt height at which they yield.
At each generated window size it compares the solver's framing rectangle with
both bars absent, each bar raised independently, and both raised together.
Each generated height ranges from 1pt to the window height.
It checks finite positive nonoverlapping frames, the row limit, vertical containment, leading alignment and reachability of the trailing edge.
It independently enumerates largest-card regular grids to check the documented
quality floor within the row limit. Every fourth seed shuffles the six-cell tiling with base spans of
1–3 columns and 1–2 rows per tile. An independent area and aspect check catches
empty cells or a poorer orientation even when the regular-grid floor passes.
Every eighth seed exercises two tall cards, two wide cards and a single cell
in product order, with column spans scaled by 1–3 and room for 3–6 such
columns. An independent cell check across the generated layouts rejects
an internal row gap wide enough for a single-row card below it.
Empty membership has no camera. No oracle calls the solver's
placement/fit helpers. Failures shrink membership/spans/viewport while retaining
the first violation and print seed plus minimized JSON. The generated positive
viewport domain does not claim invalid-input, zero-viewport, large-collection,
all-policy or global-optimality coverage.

**PBT-OVERVIEW-STATE** mounts the production Canvas in a native SwiftUI window.
[Generated traces](../../../Tests/Properties/NativeOverviewStateProperties.swift)
start with independent toolbar (0–120pt) and Dock (0–180pt) clearances.
Every fourth seed starts with 8–14 single-width cards of varying heights to
exercise overflow. Each trace makes 18 attempts at insert/remove/footprint/resize/pause/visibility/scroll/content events, up to 1–2 column/row spans, 500–1,500 by 500–1,000pt sizes,
scroll distances of −1,200…1,200pt and revisions 0–5. The window supplies
its actual display backing scale for pixel comparisons.
ID selection sorts the live set before seeded sampling. After releasing pause
and restoring visibility, the latest snapshot must settle within 3s. Mounted
membership and projection agree within one physical pixel. The envelope stays
within the vertical bounds at the retained, clamped horizontal offset. For a
nonempty result, clearing the bar heights must preserve placements, transform,
scroll offset and limits without another solve. Events are submitted 4ms apart; this samples interleavings
rather than enumerating all scheduler orders. A reduced trace is
retained as property corpus. Failures print original/reduced event traces and
only shrink to the same failure category. This checks mounted convergence, not
physical gestures, captured appearance or frame pacing.

These properties live in the dedicated `ChiefProperties` SwiftPM target.
`make pbt-native` runs geometry, collection budgets and deferred regrouping with explicit seed/case
budgets. `make pbt-native-state` separately runs mounted convergence and requires
macOS 26 with a WindowServer; missing display fails. Its 3s bound is a hang guard,
not a user-experience latency threshold. Failures retain original/reduced JSON for
replay. These are scoped mathematical
and state-convergence properties; interaction coverage belongs to e2e and
experience measurements to benchmarks. See [PBT commands/evidence](../../../../../tools/verification/pbt/README.md).

## Mounted filter e2e

`E2E-OVERVIEW-003` activates the mounted status and directory buttons against an
isolated Runtime. With completed fixture tasks it checks an empty Running view
through directory selection, exact scoped Agent IDs after selecting Completed,
and the return to global All with the selected status retained. The supported
suite includes a real project directory and untagged Inbox tasks. The
Collection suite uses two project directories. `overview-filters.json` records
the public scope oracle and the mounted snapshots after each action. The
[window replay](../../../../../demos/moku-landing/README.md#overview-note-swipe-at-actual-size)
exercises native pointer input, distinguishes similarly named tags and folders,
and checks the selected tint.

## Camera interaction e2e

`E2E-OVERVIEW-002` opens an isolated product workspace. The default suite has
twelve completed tasks and requires horizontal overflow. The Collection suite uses mixed card footprints. The runner
checks the leading alignment and both scroll limits, opens Settings, checks
input exclusion and returns to the retained position. Snapshots and a socket
transcript record semantic action results. The nested-window replay adds mouse
presses and clicks, trackpad phase samples, wheel input and resizing in the
mounted workspace. It also filters a scrolled grid down to four columns,
checks their exact fit, narrows the window by 1pt and then widens it from
the trailing edge. Wheel, trackpad and momentum samples leave fitting cards centered.
Its optional keyboard check focuses a card through system
accessibility, scrolls one column per arrow key and opens the focused card with
Return. Physical device performance needs separate evidence.
[Desktop scenarios](../../../../../tools/e2e/README.md) · [Window replay](../../../../../demos/moku-landing/README.md#nested-workspace-header-replay)
