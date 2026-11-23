# Onboarding independent-role save measurement

The reported recording measured 12.9 s from confirmation to the next page for
Auto-Categorization and 11.1 s for Super Thread. Its accompanying Runtime
samples were 14.736 s and 12.497 s for `app:update-settings`, with roughly 99%
before transaction mutation. These are supplied observations from the user's
installation. The measurements below use separate disposable profiles.

## Production HTTP comparison

| Workload | Auto-Categorization baseline | Auto-Categorization candidate | Super Thread baseline | Super Thread candidate |
| --- | ---: | ---: | ---: | ---: |
| First independent copy, four profiles | 4,044 ms | 29 ms | 3,264 ms | 25 ms |
| Restore retained overrides after restarting Runtime | 298 ms | 29 ms | 245 ms | 29 ms |

The candidate prospectively loaded the selected Codex catalog in the destination
workspace in 139 and 135 ms on first use, and in 219 and 133 ms after restart.
The columns above measure dispatch through the complete save response. The
collector read back every receipt and checked both the exact destination
configuration and revision before continuing.
[Baseline samples](evidence/onboarding-before.jsonl) · [Candidate samples](evidence/onboarding-after.jsonl)

Both runs used macOS 26.5.1 arm64, Go 1.27.3 and Python 3.13.3. Codex 0.171.0,
Pi 1.3.0 and OpenCode 2.3.0 were the installed CLI packages, using fixture
credentials and loopback-only networking. The production Claude adapter used
the bundled deterministic control peer without an injected wait for this pair.
The attempt with the installed Claude 2.1.325 binary failed to obtain the
isolated model catalog, so it supplied no valid save samples. No user settings,
model requests or external accounts participated. The first profile and
restarted workload each contain one uninstrumented sample per role, with no OS
cache clearing or calibrated latency budget.

The baseline Go source was `251a65b0da1adbc98ba7cd6aec40c11585f561a6`. The
candidate binary was built from that detached worktree with the production Go
changes in this change. Its JSONL provenance includes the production-source
digest at build time, before the final Swift-only resource-reuse adjustment,
and the runtime, collector, HTTP client and Claude peer SHA-256 values.
[Collector and invocation](README.md#first-independent-role-save)

## Native snapshot attribution

A separate instrumented run added 4 seconds to every Claude fixture
`get_settings` response. Its first baseline saves took 11,120 and 11,139 ms
over HTTP. The Runtime had spent 11,094 and 11,115 ms before submitting the
store update, whose calls then took 1.55 and 1.56 ms. The baseline acquired all
four role snapshots in sequence and revisited the selected Pi slot. It also
acquired a Chief Claude snapshot at each save after its existing profile
compared changed during normalization. The candidate's corresponding saves
took 25 and 29 ms, with about 0.3 and 0.4 ms before the store update and no
native snapshots in either save. Cold initialization still acquired native
snapshots before the workload. This run selected Pi in the baseline and Codex
in the candidate, so use it for attribution and sensitivity rather than a
controlled ratio. The uninstrumented pair selected Codex on both sides.

The build-only overlay timed `SnapshotExecution` by workspace owner and Harness,
plus `UpdateSettings` entry, dispatch to `Store.Update`, and completion of that
call. The service records use monotonic nanoseconds. The three save columns
give time before the store call, time in that call, and total handler time.
[Instrumented baseline HTTP](evidence/onboarding-instrumented-before.jsonl) ·
[Instrumented candidate HTTP](evidence/onboarding-instrumented-after.jsonl) ·
[Raw service timings](evidence/onboarding-instrumented-service.txt)

## Mounted macOS replay

| From mounted confirm action to next onboarding step | Baseline | Candidate |
| --- | ---: | ---: |
| Auto-Categorization | 11,174 ms | 503 ms |
| Super Thread | 11,079 ms | 101 ms |

The actual SwiftPM app used its opt-in
[semantic controls](../../native-interaction/README.md) to enter independent
mode, wait for readiness and confirm. Both runs pre-initialized four Chief
profiles in a disposable home before mounting. They used the same three real
CLIs and the Claude control peer with a 4-second injected wait. The baseline
chose Pi and the candidate chose Codex during startup. HTTP readback returned
revisions 5 and 6 with all four saved profiles for each role. The last step
set the onboarding completion marker. The candidate's entry-to-ready
intervals were 379 ms for Auto-Categorization and 643 ms for Super Thread.
[Baseline mounted samples](evidence/onboarding-mounted-before.jsonl) ·
[Candidate mounted samples](evidence/onboarding-mounted-after.jsonl)

The mounted numbers use one semantic activation per role and end at the first
observed next-step state with 25 ms polling. They include the real UI state
machine and save gate. Pointer dispatch, pixel timing and final handoff
animation are outside the measurement. An unprepared replay hit a Chief-step
revision conflict while discovery was still publishing settings and was
excluded. A successful mounted run with an entirely unprepared cold profile
was not established. The candidate Swift source digest at the mounted build
was `13195837db21e357c49d2af5842cdeb2e922375635823550e37d23b0c854d29b`.

## Correctness and limitations

The Swift build passed with warnings treated as errors. `make lint` and
`./scripts/go.sh build ./...` passed. Both
`PBT-RUNTIME-SETTINGS` and `PBT-RUNTIME-ROLE-SETTINGS` passed 100 generated cases
with the race detector and seed `20261123`. They exercise stale source rejection,
cancellation, same-revision conflicts, losing-draft retry, retained choices and
a genuinely missing selected slot. The cold case caught omission of an explicit
empty role profile map on a subsequent save. The final run retains that map.
[Property domains and commands](../pbt/README.md)

A managed-sandbox attempt could not bind loopback. Measurements used approved
local loopback with the child sandbox and shared resource lease. The headless
collector does not measure pointer input, rendered frames, whole-app launch or
the delay of a user's live accounts.
