# Settings HTTP latency

## First independent-role save

[onboarding.py](onboarding.py) uses the production HTTP command and the four
production Harness adapters. Point it at a baseline or candidate runtime built
with `./scripts/go.sh build -trimpath -o <binary> ./cmd/chief-runtime`.

```sh
python3 -B tools/verification/local-http/onboarding.py <binary> --revision <revision> \
  --mode candidate --cli-dir <harness-bin> --cli-dir <node-bin>
```

Run the same command with `--mode baseline` for a revision whose save performs
native snapshots. The driver uses private homes, profiles and fixture keys. It
requires macOS loopback listeners and an available shared performance and
desktop lease. A child sandbox confines writes to the temporary directory and
network traffic to loopback. Codex, Pi and OpenCode use installed executables.
Claude uses a deterministic native-control peer unless `--native-claude` is
supplied. `--claude-delay` injects a stated delay into each fixture
`get_settings` reply for a separate sensitivity run.

The driver hydrates all four Chief profiles, then saves Tag and Super Thread in
that order with their first independent copies. It returns both roles to
inheritance, restarts the Runtime and repeats from retained independent settings.
Each save must advance the revision once and return the same selected Harness
and profile map that an independent read observes. The candidate times its
selected role's entry preview separately. Save durations run from HTTP dispatch
through receipt of the entire response. There is no calibrated latency budget
for this workload. The [comparison](ONBOARDING-SAVE.md) records raw samples,
source and binary identities, and the limits of the headless timing.

## Pinned presentation under contention

The [contention report](RESULTS.md) includes source revisions, raw samples and
limits. The workload below depends on the historical revisions identified
there, whose save command still enters a native snapshot.

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
the settings handler, number of calls to acquire the configuration gate, time until
those calls returned, and time inside the native presentation adapter. The two
subintervals are inside handler time. Record instrumented runs separately.
The interval override omits wall-clock aging and is only for attribution.

The [generated settings property](../pbt/runtime/settings_property_test.go)
covers reads finishing before, across, or cancelled during a save. Desktop
responsiveness and the frequency of these overlaps on a user's installation
require independent observation.
