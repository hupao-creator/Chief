# Artificial Analysis context

[plugin.go](plugin.go) registers `artificial-analysis.evaluation` in the Moku `evaluation` slot at `before-send`. Enablement is `context:artificial-analysis`. The plugin has Context capabilities only; it owns no application records, background agent or native UI.

[source.go](source.go), [parser.go](parser.go), [identity.go](identity.go) and [policy.go](policy.go) own upstream acquisition, cached evaluation facts, native-model attribution and bounded advisory output. Harnesses provide model catalogs; their model/account facts remain authoritative for execution. Evaluation matching does not choose a different model or grant account availability.

The [public model roster](https://artificialanalysis.ai/models/) identifies release pages by
slug and name. A native catalog match fetches that release once. Its `initialModels`
comparison contains peers as well as the requested release. Only rows with the
requested release slug, a configuration slug, a reasoning flag and valid optional
effort enter that release. Configuration-addressed rosters use the individual
detail page and match the requested configuration. Display names alone cannot
establish an effort or a measurement.

A detail page can identify the Intelligence Index version through its chart
caption, Dataset description or named evaluation metadata. Missing, malformed
or conflicting declarations leave that page's version unknown. Every measured
configuration keeps the detail version alongside its published score and cost
per task. The roster version describes the roster alone. Historical rows take
their labels from the saved observation. Compare index scores, task costs and
component grades only for matching known versions. The routing context includes
v5 weights only for a common v5.0 or v5.0.1 cohort. [AA methodology](https://artificialanalysis.ai/methodology/intelligence-benchmarking)

Version 5.0.1 regrades CritPt v2 with upstream grading robustness improvements.
The nine v5 evaluations use these source fields. Omniscience contributes two
separate components; its hallucination rate is retained without inversion.

| Context metric | Public model field | Unit |
| --- | --- | --- |
| `aaBriefcaseV11` | `briefcaseBreakdown.overall.elo` | Elo |
| `automationBenchAA` | `automationBenchPartialScore` | Guardrail-gated objective completion, 0..1 |
| `gdpPDF` | `gdpPdfAllPass` | All-pass rate, 0..1 |
| `frontierCodeV20` | `frontierCode20` | Mean rubric score, 0..1 |
| `terminalBenchV40` | `terminalBench40` | Test-suite pass@1, 0..1 |
| `omniscienceV11Accuracy` | `omniscienceAccuracy` | Correct-answer rate, 0..1 |
| `omniscienceV11HallucinationRate` | `omniscienceHallucinationRate` | Hallucination rate, 0..1; lower is better |
| `hleDiamond` | `hleDiamond` | Pass@1 on all 1,000 HLE-Diamond questions, 0..1 |
| `critPtV2Hard` | `critptAgenticHard` | Pass@1 on the hard 40-problem subset, 0..1 |
| `terminalBenchScienceV01` | `terminalBenchScience` | Terminal-Bench-Science 0.1.0 pass@1, 0..1 |

Missing/invalid measurements remain null; measured zero remains zero. Legacy
HLE, Terminal-Bench 2.1, τ³-Banking, FrontierCode 1.1 and CritPt fields are never
substituted for v5 metrics. Elo is finite but has no proportion bounds.

Performance v3 publishes end-to-end output tokens per second at
`headline.outputSpeed` and seconds to the first **answer** token at
`headline.timeToFirstAnswerToken`. Routing labels both as headline workload
averages. The median fields require their own source measurements. Input and
output prices retain USD per million tokens. [AA performance methodology](https://artificialanalysis.ai/methodology/performance-benchmarking)

The schema-2 cache validates source, timestamps, unique identities, units and
ranges before publication and on reopen. It stores the roster version, each
row's version and the version common to all measured rows, if any. An empty
version represents unknown. A schema-2 cohort with a single historical label
keeps that label on its rows. An unlabeled cohort stays unknown. Detailed,
compact and cached routing text label individual rows.

A change between two known roster versions triggers an unconditional refresh
of the cached releases. A detail failure in this refresh preserves the previous
snapshot. A successful release response updates the observed configurations
together. Configurations omitted from a comparison sample keep their original
observations and labels. A failed request retains the previous rows,
and HTTP 404/410 removes the requested release or configuration. A configuration
response of 304 reuses the observation with its saved version only after a
conditional request. Release-page ETags belong to the entire comparison and
are never reused on configuration URLs.

Services sharing a cache root share acquisition with reference-counted ownership. Within one methodology version, refresh deadlines and failure backoff belong to each catalog identity set: refreshing one catalog cannot postpone another's stale facts or trigger acquisition of a still-fresh catalog. Equal pending identity sets share one generation, while different generations remain serialized; at most 4096 deadline keys are retained. A warm cache returns immediately while its due generation refreshes in the background.

Collection and cached fallback use the declared 21-second timeout. Unavailable measurements remain explicitly unknown. Collection failure follows `abort-send`; cancellation or host closure cancels collection rather than invoking fallback. Catalog callbacks must honor their context; each collection joins all callbacks, including their cancellation cleanup, before returning. Closing a service is idempotent and drains its catalog callbacks and acquisition ownership. The [Context host](../../../hosts/contexthost/README.md) enforces contribution and aggregate bounds, including merged-slot separators.

Source closure stops pending detail dispatch and joins the active workers.
Real acquisition failures retain the existing cache fallback and refresh backoff.

## Verification

[PBT-AA-VERSION](../../../../tools/verification/pbt/README.md) varies roster,
detail and historical labels independently to exercise combinations a single
public page cannot supply. It checks attribution, nulls, measured zero,
conditional reuse, compact routing and schema-2 reopen.
The [public-response replay](../../../../tools/e2e/README.md#aa-evaluation-context)
exercises the registered before-send slot from a missing cache directory and
again after the host reopens it.
