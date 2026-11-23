# Compact Chief eyes and input replay

Run on macOS 26 with Xcode, the resolved SwiftPM dependencies, a graphical session
and current-process ScreenCaptureKit access. Use a fresh output directory.

```sh
python3 demos/moku-panel-transition/remaining/run.py .build/compact-eyes routes routes-reduced
```

The runner acquires the shared performance and native-window leases, builds the
current Debug product and mounts the production eye layers and Dock in isolated,
non-key panels. Each visit records its PID, the foreground application and the
collector and executable fingerprints.

- `timers` and `timers-reduced` mount the compact production Timer at original
  scale in an offscreen panel. They check its bottom placement and AppKit hit
  region, explicit FIFO receipts, reading to the final line and restoring idle
  and running Docks. A pending head also moves to a route without a Dock and
  back. The fixture injects a silent bell and records its start/stop lifetime.
- The compositor expression experiment (`eyes`) uses the native modules at
  `3e355741`. Its phase and main-thread-hold checks target that layer renderer.
- `routes` and `routes-reduced` mount a reply, permission and questionnaire
  controls and two completed Timer operations. An external AX client restricted
  to the fixture's own PID presses the controls. The visits check first-key
  delivery, UTF-16 selection, marked-text commit and draft restoration across
  reversal and retirement. The fixture supplies the projected requests and
  records bell callbacks. `routes-offscreen` runs the same normal-motion
  interaction checks entirely beyond the desktop and records AppKit view
  bitmaps. These images document layout and do not measure composited glass.

- `tool-feedback` mounts the production Dock and delivers Codex catalog fixtures
  to its workspace presentation. The check observes painted dots, the mounted
  character and its animation input across consecutive named calls and reasoning.
  It checks the foreground call IDs and names, retirement on completion, failure and interruption, both
  intervention panels and the pending dispatch notification. Results are in
  `tool-feedback/tool-feedback.json`; no model or external tool runs.

The [transition study](../../../design/research/chief-bar-remaining.md) records
the separate onboarding, route lifetime, mask, Talk, Collection and identity
experiments and their limitations. Their collectors and rejected candidates are
available in Git object `9979d53b15b04243d87000e390d1d90d39d0ac6a` under
`demos/moku-panel-transition/remaining/`.

The `tag-unread` case mounts the production directory and child menu in a 1× offscreen panel with an isolated read history. It records counts and images before reading, after a receipt, after rereading the same version and after the final receipt.
