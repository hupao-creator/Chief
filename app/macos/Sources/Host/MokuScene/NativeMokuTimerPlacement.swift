import ChiefPluginUI
import SwiftUI

extension EnvironmentValues {
    @Entry var reminderScrollRegions: NativeCanvasInputRegions? = nil
    @Entry var nativeMokuDockTimer: NativeMokuTimerController? = nil
}

/// The passive Dock lends its own seat to the reminder. When another control
/// owns the shell, keep that visit mounted and reserve room for the same row.
struct NativeMokuTimerPlacement: ViewModifier {
    let timer: NativeMokuTimerController
    let scene: NativeMokuSceneState
    @State private var scrollRegions = NativeCanvasInputRegions()
    var dockAvailable: () -> Bool = { true }

    func body(content: Content) -> some View {
        let resident = timer.current != nil && dockAvailable() && scene.dockRouteVisible && !scene.dockCovered
            && !scene.inputOpen && !scene.inputLeaving && !scene.inputPinnedOpen && !scene.notePanelOpen
        content
            .environment(\.nativeMokuDockTimer, resident ? timer : nil)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ZStack {
                    if !resident, let message = timer.current {
                        NativeMokuTimerBar(timer: timer, message: message, exclusions: scene.outsideClickExclusions)
                            .frame(maxWidth: NativeMokuTimerBar.preferredWidth)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .transition(.opacity)
                    }
                }.mokuInk(value: !resident && timer.current != nil)
            }
            .environment(\.reminderScrollRegions, scrollRegions)
    }
}
