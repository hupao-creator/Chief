# Native motion and admission

Opening a Report from Overview or the [Super Thread member grid](../app/macos/Sources/Host/Overview/README.md#viewed-application-collections)
uses one native panel transition. The panel opens from the activated card and
returns to the card in the originating surface. The reader can show its usual loading state.
Activating an execution link in a Chief message reveals its destination in Overview.
If the active filter excludes the destination, Overview selects a matching
filter. A grouped Report turns to the requested page before the reader opens.
The settled card uses its ordinary 420ms opening, including the Agent card’s
identity handoff when its anchors are available. The Report
admits the cited execution after its document and sidebar layout are ready.
The bottom Chief Dock opens and closes its Overview input over 420ms,
carrying the eyes and Stop button with the shell. A semantic tag on the left of
Overview uses the same smooth, zero-extra-bounce timing to reveal and hide its
name. [Overview filters](../app/macos/Sources/Host/Overview/README.md#tags-and-filter-transitions) · [Dock and composer](../app/macos/Sources/Host/MokuScene/README.md#dock-and-composer)

Application-owned animations use their authored curves and completion gates.
Visibility, focus, occlusion, offscreen state, explicit pause, drag/resize and
performance gates govern when motion runs. Reduce Transparency and Increase
Contrast govern appearance. Keyboard navigation and accessibility semantics
follow the active controls.

The [PluginUI guide](../app/macos/Sources/Shared/PluginUI/README.md#motion-and-materials)
owns decorative rendering and reading carriers. Native panel/ink travel uses
Core Animation after admission; native main-thread layout can still delay
preparation, mounting and callback delivery. A scheduled tick, display-link
callback or GPU submission is not evidence of physical presentation or FPS.

Running Agent Thread cards confine their status animation to the emoji badge.
Core Animation sweeps the harness accent across fixed perforations. Reduce
Motion holds a lit diagonal. Visibility and detachment retire the animations.
The foreground emoji and the card body keep their positions. Active Overview
folders and tags use the same sweep in the Overview accent behind their icon
or emoji. [Tag activity](../app/macos/Sources/Host/Overview/README.md#tag-activity).

Source: [running badge](../app/macos/Sources/Shared/PluginUI/Cards/RunningThreadBadge.swift),
[panel transition](../app/macos/Sources/Shared/PluginUI/Conversation/NativeReadingPanelTransition.swift),
[reading return](../app/macos/Sources/Shared/PluginUI/Conversation/NativeReadingPanelReturn.swift).

The reading parent's hide operation is deferred beyond `updateNSView` to avoid
AppKit key-view traversal reentering an active SwiftUI layout graph. A cancelled
or replaced route cannot hide its successor. Showing remains synchronous for
return preparation; keyboard/focus behavior is not disabled to hide warnings.
See [parent surface](../app/macos/Sources/Shared/PluginUI/Conversation/NativeReadingParentSurface.swift).

The [mounted Dock visits](../demos/moku-panel-transition/remaining/README.md) exercise
the reply read key, permissions, questionnaires and native
input. The [transition study](research/chief-bar-remaining.md) records unshipped
candidates and the boundaries of their measurements. Physical presentation and
whole-workspace frame pacing require separate measurements.
