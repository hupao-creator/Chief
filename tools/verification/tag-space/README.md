# Overview tag-space switch

The [Overview contract](../../../app/macos/Sources/Host/Overview/README.md#tags-and-filter-transitions)
defines directory identity, membership and card motion. The [Report contract](../../../internal/plugins/applications/report/README.md#cover-cards)
defines cover loading and playback.

## Workload and observations

The [collector](main.swift) mounts the production Overview, tag controls, canvas,
Codex cards and Report renderer in a nonactivating 2048 × 1225 point dark panel.
A fresh temporary profile contains five Agent cards and twelve recent 1×2
reports tagged 共享 in one Chief directory, a second same-named directory, and one Inbox
card tagged 股票行情. The local Report query serves a distinct HTML/CSS chart for
each report. The renderer uses real WebKit. The fixture does not start a Runtime
or contact a provider.

The probe locates the two Chief directory buttons and the top-level Inbox tag
股票行情 through their production layout anchors and sends paired mouse events
to its own panel. The probe checks that
the floating filters leave the full 2048 points available to the cards and
that all twelve recent covers appear individually in Chief.
The monotonic samples start immediately before mouse-down. The probe records
dispatch return, observed selected scope, exact destination placement IDs, then
the exact mounted set with input restored after the transition. For the dense
directory it also waits for all twelve WebKit views to finish loading and reveal
their rendered surface. Polls run on the main actor at 4ms intervals and give upper
bounds on semantic readiness. They do not timestamp presented display frames.
The first visit has cold covers, subsequent visits reuse the revision-keyed cache.
Separate samples time the production selection callback before mounting and the pure layout solver at the mounted Chief canvas size.

After four round trips the probe interrupts an in-flight transition, selects the
other Chief directory and moves a task between the directories in an admitted
catalog snapshot. Both the selected and revisited scopes must settle with the
expected card IDs. The snapshot also changes one report’s cover revision. After
revisiting, the probe reads the rendered HTML headings from WebKit and verifies
the identities and revisions of all twelve covers. A timeout or stale cover makes
the sample fail.

## Reproduce

Build one artifact per production revision with identical collector source.
Both revisions must expose the same project directories and top-level Inbox
tag so the collector can target the same buttons.
Run the baseline build from a separate checkout with the verification directory
copied in. The [measured campaign](RESULTS.md) used a 2048 × 1225 panel and its own
collector. The [sample manifests](samples.json.gz) identify the exact builds and
collector for that workload. Compare fresh runs made with the same collector
and panel size. Running both builds in the same checkout without changing
the production sources would measure the same implementation twice.

Builds and samples take the shared host and native UI leases. Each sample runs
a new staged process. The driver checks the executable and collector hashes and
requires a new result path. Alternate the order of the two builds across pairs.

```sh
# In the baseline checkout
python3 tools/verification/tag-space/run.py build /private/tmp/tag-baseline
# In the candidate checkout
python3 tools/verification/tag-space/run.py build /private/tmp/tag-candidate
python3 tools/verification/tag-space/run.py measure /private/tmp/tag-baseline /private/tmp/a1.json
python3 tools/verification/tag-space/run.py measure /private/tmp/tag-candidate /private/tmp/b1.json
```

## Same-turn input diagnostic

The [burst evidence](burst.json.gz) includes the exact Swift collector and the
raw observations for each build. It uses the campaign’s 2048 × 1225 panel, fixture, mouse helper
and four warm-up round trips. While the dense directory is entering, it sends
two window-local clicks without yielding. It records the model's filter-action
journal, the observed scopes and the final mounted cards. A separate interruption
calls the production selection callback twice in the same main-actor turn and
checks the selected scope after each call. The last selection must settle with
exact placement and mounted IDs, layout complete and activation enabled.

To repeat the diagnostic, extract its collector and pass it to both driver
commands in the corresponding production checkout from its build manifest. Use a fresh artifact and result path.

```sh
gzip -dc tools/verification/tag-space/burst.json.gz | jq -j .collectorSource > /private/tmp/tag-burst.swift
python3 tools/verification/tag-space/run.py --collector /private/tmp/tag-burst.swift build /private/tmp/tag-burst-build
python3 tools/verification/tag-space/run.py --collector /private/tmp/tag-burst.swift measure /private/tmp/tag-burst-build /private/tmp/tag-burst.json
```

This local diagnostic has no calibrated latency budget. Display hitches, exact
first pixels, physical clicks and end-to-end Runtime/IPC latency need separate
collection.
