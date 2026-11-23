# Overview glass evidence tools

`run.py` unconditionally refuses live build/trials. No all-on/shell-off/all-off
product experiment is available in this source tree.

The retained [measurement report](REPORT.md), evidence manifest and raw data
identify the measured source revision. `analyze.py` reads those artifacts without
running the product. Existing baseline/candidate data cannot establish current
flat-card behavior or GPU/FPS/energy results.

The independent geometry probe builds current Release objects under the shared host and native leases, then links the production
`NativeOverviewLayout.solve` and horizontal scroll geometry. It measures geometry without a
visible window and does not measure glass, GPU or real input:

```sh
python3 tools/verification/overview-glass/geometry.py
```

It writes `.build/overview-glass/geometry.json` and `geometry-build.json`, retaining
link inputs and source identity. The [Release comparison](../overview-ci-performance/README.md)
and [external benchmark](../../benchmarks/README.md) have separate measurement
contracts and their own capability limits. No correctness suite is configured here.
