# Tag Space trackpad haptics

Build the demo on macOS from the repository root.

```sh
python3 demos/tag-space-haptics/build.py
```

The script builds Chief, runs a windowless replay and prints the path to
`TagSpaceHaptics.app`. Open that app to try the production Overview with a
fixture folder containing Design and Review. Move the pointer over a card or
the canvas and swipe up or down with two fingers. Watch the expanded label on
the left. A supported trackpad may tap once as that label changes, including
when it wraps. Keep your fingers down after the switch, then lift them. The
rest of that gesture stays on the same choice. Try a mouse-wheel step or
click a left label to change the selection silently.

The windowless replay sends synthetic AppKit phases directly to the
[production recognizer](../../app/macos/Sources/Host/Overview/NativeOverviewVerticalSwipe.swift)
with the real Overview selection model. Its feedback callback counts requests.
It prints the resulting rail and cumulative count at each step and exits with
an error on a routing, selection or count mismatch. The interactive app uses
the system performer and a private temporary profile. Window hit testing,
physical input and felt feedback require a manual run.
