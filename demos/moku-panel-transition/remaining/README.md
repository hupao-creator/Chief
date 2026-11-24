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
  and running Docks. A failed bell exposes Retry bell and keeps the same pending receipt through retry.
  A pending head also moves to a route without a Dock and
  back. The fixture injects a silent bell and records its start/stop lifetime.
- `eyes` compares the compact expression layers with the original renderer at matched phases
  and during main-thread holds. Running or retiring orbit dots keep the shared display clock.
- `routes` and `routes-reduced` mount a reply, permission and questionnaire
  controls and two completed Timer operations. An external AX client restricted
  to the fixture's own PID presses the controls. The visits check first-key
  delivery, UTF-16 selection, marked-text commit and draft restoration across
  reversal and retirement. A Talk visit opens Note, reverses its return, opens
  Settings, interrupts its close and uses the restored close controls. The fixture supplies the projected requests and
  records bell callbacks. `routes-offscreen` runs the same normal-motion
  interaction checks entirely beyond the desktop and records AppKit view
  bitmaps. These images document layout and do not measure composited glass.

- `orbit-fade` mounts the production 168 × 44-point Dock entirely offscreen.
  Catalog fixtures start, interrupt, reverse, replace and complete executions.
  The replay advances the production display-frame step by 25ms. Each visible
  sample must stay on the capsule contour, advance with an uninterrupted peer
  and paint three 5-point dots at the current fade opacity. The evidence includes
  intermediate Dock images, 1-pixel-per-point decoration rasters and
  `orbit-frames.json`. This fixture checks drawing and state, not display pacing.
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

The `tag-unread` case mounts the production Overview in an offscreen panel with isolated read history. It selects Project from the header and Work from the left column. Project starts with two unread tasks, one tagged Work and one untagged. The replay checks both counts with Work selected and saves the window image before reading, after a receipt, after rereading the same version and after the final receipt.

The `tag-activity` and `tag-activity-reduced` cases select Work and Completed only. The running task is outside that card selection. They locate the perforation surfaces inside Project's folder button and Work's emoji button using the controls’ production layout anchors. The normal-motion visit requires sweeping Core Animation layers and changes in the captured pixels behind both glyphs. The Reduce Motion visit requires static perforations. Completing the active task removes both decorations. The nonactivating panel leaves an edge on screen for WindowServer composition. The evidence contains window images, a sequence of glyph crops, `tag-activity.json` and the button, AX and native-surface frames in `tag-activity-geometry.json`.

```sh
python3 demos/moku-panel-transition/remaining/run.py .build/overview-tag-activity tag-unread tag-activity tag-activity-reduced
```
