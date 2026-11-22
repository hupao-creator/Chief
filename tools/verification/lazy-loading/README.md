# Lazy loading measurements

These component workloads exercise three production boundaries. Compare the
same collectors on the two revisions. Record source and binary hashes, macOS
and toolchain versions, and retain every sample. Directional timings have no
calibrated threshold.

- The [native workload](Native.swift) links the SwiftPM debug products. Each of
  five fresh processes registers fonts, times plugin composition, constructs
  four native logo views, and requests each encoded logo and translation table
  twice. It mounts the production Agent conversation and sidebar in a private
  panel with 256 synchronous fixture rows. It waits for both the mounted body
  and the settled semantic selection on current and first history entry. The
  fallback builder counts actual calls during directory construction, mounted
  scoped reads and two inline reads of one row. Compare counts, logo digests,
  catalog sizes and mounted IDs. The clocks include SwiftUI layout, polling
  and native transitions. The panel uses fixture bodies without transport.
  [Registry](../../../app/macos/Sources/Shared/PluginAPI/README.md) ·
  [Reading](../../../design/reading.md)
- The [directory workload](directories/main.go) seeds a private SQLite store
  with 256 Codex Threads of 16 completed executions each. Default cwd and all
  Thread cwds identify one directory. It calls the public Runtime after normal
  catalog initialization, five more times, then immediately after insertion and
  deletion of an unlisted Thread. It checks the full sorted response and
  cancellation. The Harness supplies its real projections and exposes no
  external discovery interface. Wall time and Go process allocations cover
  the call, including any concurrent publication. [Runtime](../../../internal/core/runtime/README.md)
- The [OpenCode workload](renderer/main.go) projects one saved history with 128
  completed executions, each with an 8 KiB tool result and a settled reply. It
  requests Overview, manifest, latest turn, historical turn, full historical
  execution and manifest again. Compare the exact response length and SHA-256
  at each step as well as allocated bytes, allocation count and wall time.
  Each call includes canonical-state decoding. [OpenCode](../../../internal/plugins/harness/opencode/README.md)

Build before sampling. The native launcher holds the project performance and
desktop leases and stages the linked app in temporary storage. Coordinate
builds and Go runs with the same leases. Use a fresh output directory.

```sh
xcrun swift build --package-path app/macos
python3 tools/verification/lazy-loading/native.py --output /private/tmp/chief-lazy-native
./scripts/go.sh build -trimpath -o /private/tmp/chief-directories ./tools/verification/lazy-loading/directories
./scripts/go.sh build -trimpath -o /private/tmp/chief-renderer ./tools/verification/lazy-loading/renderer
GOMAXPROCS=2 /private/tmp/chief-directories
GOMAXPROCS=2 /private/tmp/chief-renderer
```

For an older product, compile the same Swift collector against that revision's
built modules. For Go, pass a `-overlay` JSON file mapping each changed
production Go file's absolute path to the corresponding `git show REV:path`
contents. Alternate baseline/candidate process order between pairs.
