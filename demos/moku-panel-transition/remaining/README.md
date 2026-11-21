# Compact Chief eyes and input replay

Run on macOS 26 with Xcode, the resolved SwiftPM dependencies, a graphical session
and current-process ScreenCaptureKit access. Use a fresh output directory.

```sh
python3 demos/moku-panel-transition/remaining/run.py .build/compact-eyes eyes routes routes-reduced
```

The runner acquires the shared performance and native-window leases, builds the
current Debug product and mounts the production eye layers and Dock in isolated,
non-key panels. Each visit records its PID, the foreground application and the
collector and executable fingerprints.

- `eyes` builds the original controller and renderer from commit `9b61af09`.
  Six 420 ms legs compare original and submitted paths at identical device
  coordinates, including fractional phases and a reversal. A separate capture
  queue samples the two originals and production eyes while the main thread is
  held. Hiding the face, interrupting a blink and redirecting to a third pose
  check the handoff to the display link.
- `routes` and `routes-reduced` mount a reply, permission and questionnaire
  controls and two completed Timer operations. An external AX client restricted
  to the fixture's own PID presses the controls. The visits check first-key
  delivery, UTF-16 selection, marked-text commit and draft restoration across
  reversal and retirement. The fixture supplies the projected requests and
  records bell callbacks.

The [transition study](../../../design/research/chief-bar-remaining.md) records
the separate onboarding, route lifetime, mask, Talk, Collection and identity
experiments and their limitations. Their collectors and rejected candidates are
available in Git object `9979d53b15b04243d87000e390d1d90d39d0ac6a` under
`demos/moku-panel-transition/remaining/`.
