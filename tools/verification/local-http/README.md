# Settings HTTP latency

This headless macOS benchmark measures authenticated commands against a production
`chief-runtime serve` on loopback. A new profile, private home and deterministic
Claude control peer isolate the [configuration admission](../../../internal/core/runtime/README.md#settings)
and [HTTP](../../../internal/platform/transport/README.md) contracts. A second
run uses the same collector, seed executable, peer, workload and toolchain with
the candidate binary. Serialize builds and samplers under the shared desktop
lease described in the [benchmark guide](../../benchmarks/gate/UX.md).

Build both revisions with `./scripts/go.sh build -trimpath -o <binary> ./cmd/chief-runtime`.
The [baseline overlay helper](../runtime-performance/prepare_baseline.py) can
select the baseline production files in a detached worktree. Build the seed
once and run each side separately (the output directory must already exist).

```sh
./scripts/go.sh build -trimpath -o .build/seed ./tools/verification/local-http/seed
python3 tools/verification/local-http/run.py .build/before .build/seed > .build/before.jsonl
python3 tools/verification/local-http/run.py .build/after .build/seed > .build/after.jsonl
```

* Cold initialization captures the execution profile. Five saves then alternate
  its permission mode. Once the peer enters the save's native validation, it
  waits 1.25 s. Three independent HTTP requests read the pinned Moku presentation,
  ordinary Harness defaults and installation status. A public state read checks
  the saved revision and settings after each overlap.
* The expected improvement is causal. The initialized execution read should
  finish **during** the validation hold. The save must still wait for the peer
  and commit. Ordinary defaults and detection provide controls under the same
  load. A mutation stream records the first hello and first idle heartbeat
  separately. Disconnecting a forced-refresh reader must retire its waiting peer
  within the five-second hang guard and permit the next read to load.
* Two rounds wait 300 seconds each, with a detection request about every
  15 seconds between them. Each round requests both presentations. This drives
  the workspace's request shapes and real Harness TTL at wall-clock speed.
  The Swift scheduler, its pre-HTTP queue and any mounted foreground editor
  are outside the collector. Caller roles identify injected workload, and
  service replies must have a successful business envelope.
* JSONL contains monotonic nanoseconds for dispatch, headers and completion,
  response byte counts, peer-method entry, cancellation and process retirement.
  The header records artifact hashes and host/tool versions. No command payloads,
  account data, connection credentials or profile paths are exported.

For service attribution, [diagnostic.py](diagnostic.py) generates a build-only
overlay from the nominated revision. Build against the matching production
sources. Supply the revision and a new overlay output directory.

```sh
python3 tools/verification/local-http/diagnostic.py HEAD .build/http-diag
./scripts/go.sh build -trimpath -overlay=.build/http-diag/overlay.json -o .build/diagnostic ./cmd/chief-runtime
python3 tools/verification/local-http/run.py .build/diagnostic .build/seed --interval 0 > .build/diag.jsonl 2> .build/service.txt
```

Each `presentation-ns` line gives scope, Harness, Moku-binding flag, time inside
the settings handler, number of configuration gate acquisitions, time until
acquisition returned, and time inside the native presentation adapter. The two
subintervals are inside handler time. Record instrumented runs separately.
The interval override omits wall-clock aging and is only for attribution.

The [generated settings property](../pbt/runtime/settings_property_test.go)
covers reads finishing before, across, or cancelled during a save. Desktop
responsiveness and the frequency of these overlaps on a user's installation
require independent observation.
