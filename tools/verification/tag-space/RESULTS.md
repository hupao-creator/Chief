# Mounted tag-switch measurements

On 2026-11-23 the collector in the [sample manifests](samples.json.gz) ran in a 2048 × 1225 panel on an Apple M1 Pro
(10 cores, 16 GB), macOS 26.5.1 (25F80), Swift 6.3.2, Release with testing
access. Four pairs alternated baseline/candidate and candidate/baseline. Each
binary ran in four fresh processes, each with one cold visit, three revisits
and four returns. Values are medians of the four process medians, with their
minimum and maximum in brackets. All endpoints start at the input event.

| Route | Observed endpoint | Baseline (ms) | Candidate (ms) |
| --- | --- | ---: | ---: |
| First visit | Placement | 495 [464–517] | 138 [119–155] |
| First visit | Cards activatable | 924 [892–932] | 628 [597–650] |
| First visit | All covers ready and cards activatable | 924 [892–933] | 863 [810–913] |
| Repeat visit | Scope selected | 21 [18–28] | 19 [14–24] |
| Repeat visit | Placement | 465 [451–475] | 105 [94–107] |
| Repeat visit | Cards activatable | 877 [865–888] | 575 [573–615] |
| Repeat visit | All covers ready and cards activatable | 877 [865–889] | 770 [765–798] |
| Return to stock | Single card activatable | 484 [483–487] | 481 [480–486] |

The baseline uses the Swift sources at `50d80d9a84c04ac65cc9f8eb31deb00cc43822b7`.
The candidate changes the standalone Report card and cover mount path only.
Both compiled with the same collector. The [raw samples and build manifests](samples.json.gz)
contain the source differences against that base, SHA-256 digests of the source
inputs, collector and executables, run order, individual observations and the
revisited cover identities. Both builds include the same engineering guide in
the source digest.

## Diagnosis and scope

The selection callback projects admitted membership, checks redirects, applies
Report collection budgeting and installs slots. The baseline's median synchronous
callback was 0.31ms and the independent solver was 0.042ms on this fixture.
The cover query ran twelve times on first entry, zero times on the three
revisits, then once for the changed revision. Caching the markup still requires
creating a browser and navigating it when a standalone card remounts.

An eight-second, 2ms-interval `/usr/bin/sample` of the baseline's own process
caught `ReportCoverHTML.updateNSView` calling `WKWebView.loadRequest` during a
SwiftUI update. Two main-thread branches had 130 and 131 inclusive samples in
the update. The stacks descend through WebKit process launch, creation
parameters and installed font registration. The recording alone cannot identify
a call stack. [Stack excerpt, collector identities and exploratory samples](diagnosis.json.gz)

In one exploratory warm process per variant, sharing an ephemeral data store
gave 536ms to observed placement, and queuing just navigation on the run loop
gave 698ms, against 527ms for their baseline. Neither was retained. Spacing
the **browser mounts** lets the existing metadata, pending surface or cached
poster participate in the original card transition. Admission does not shorten
the transition or make WebKit initialization itself cheaper. The table separates
the cost still needed to make every live cover ready from the point when the
user can act on the cards.

Every paired latency process settled on the second same-named directory after an
interrupted transition, reflected the moved task in both directories, and read
all twelve matching HTML headings, including the replaced cover revision.
Initial local AX discovery exposed only the hosting group. The measured input
used the window-local mouse path. The rapid sequence in those samples waits for
selection admission and separates the last two clicks by 40ms.

## Same-turn clicks and accepted selections

A separate [diagnostic replay](burst.json.gz) reproduced the exploratory
baseline timeout on both builds. One fresh process per build sent four pairs
of synthetic clicks during dense-directory entry. Each pair targeted 股票行情
in Inbox and then the other Chief directory, with no yield between dispatches.
Both builds produced the same observations.

| Input | Result in each build |
| --- | --- |
| Two window-local clicks | In two rounds the model recorded zero filter actions and the original 17 cards settled. In two rounds it recorded only the second action and the single personal card settled. |
| Two direct selection callbacks | In all four rounds the model recorded both actions in order. Its scope changed to Inbox and then to the personal directory. Only the personal card was placed and mounted, layout completed and its activation gate opened. |

On the first missed target in each build, the selection journal and observed
scope stayed unchanged through the full timeout. The failed predicate waited
for a selection that never reached the model. No round showed an accepted
final selection with stale cards. These observations locate the miss before
selection admission in this synthetic dispatch path. They do not distinguish
AppKit hit testing from SwiftUI gesture handling or establish physical-click
delivery. The raw evidence includes the original failure, collector source,
build identities and each round's journal, scopes and mounted IDs.

These are local semantic upper bounds under the shared verification leases.
There is no calibrated pass threshold, optical frame timing, real provider,
user database, or hosted CI measurement in this campaign.
