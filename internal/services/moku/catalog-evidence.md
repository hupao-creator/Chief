# Native model catalog evidence

Chief consumes [published dispatch configurations](../dispatchconfig/README.md).
A native inventory describes the options observed by its adapter and can be
partial or outdated. Selected targets remain addressable through their static tool
arguments when the adapter has no published inventory. Permission checks and
actual execution outcomes belong to the selected destination.

## Harness capability limits

| Harness | Current directory boundary | Limit |
| --- | --- | --- |
| [Codex](../../plugins/harness/codex/README.md) | Full paginated native inventory, matching originator at spawn/initialize; best-effort 3s ChatGPT cache-refresh hint | Shared cache timestamp is not account attestation; enrichment failure does not discard a usable routing list |
| [Claude](../../plugins/harness/claude/README.md) | Native initialized nonempty list from the CLI | Does not prove later gateway/provider discovery complete; ordinary/custom execution validation is separate |
| [OpenCode](../../plugins/harness/opencode/README.md) | Native catalog with account filtering, captured source checked before publication | Advisory plugin inventory has a 3s budget; working response does not prove every remote provider finished |
| [Pi](../../plugins/harness/pi/README.md) | Successful completed nonempty RPC observation, offline native discovery | RPC does not expose every SDK load error/publication receipt; a usable list is not formal source proof |

A cold reader can recapture a changed native source once in all four Harnesses.
OpenCode also retries brief SQLite contention while identifying a required
account source and transient gateway/service failures on required catalog GETs.
The [OpenCode routing property](../../../tools/verification/pbt/README.md)
covers its account-switch and retry boundaries with a real SQLite writer and
scripted native replies.

Owned probe work budgets per acquisition are Codex 60s, Claude 45s, OpenCode 55s (30s native
cancellation timer), Pi 30s, plus joined cleanup. These are code budgets, not
measured startup times. Adapters retain separate diagnostic discovery and execution-profile reads. Codex strict reads also expire a completed
observation early after a compatible native cache write. No sleep/stable-list
heuristic establishes remote completeness.

Source: [shared cache](../../platform/discovery/cache.go),
[source identity](../../platform/discovery/source.go),
[static target schema](tool_schema.go), and the Harness guides above.
The [desktop e2e runner](../../../tools/e2e/README.md) uses an installed Codex
CLI and a private provider during preparation. The [Codex catalog property](../../plugins/harness/codex/catalog_property_test.go)
checks compatible cache writes around a strict read. Live account directories
and refreshes of other Harnesses need separate evidence.
