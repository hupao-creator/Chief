import ChiefPluginUI
import SwiftUI

public struct NativeMokuScene<Outside: View, Dock: View, Settings: View>: View {
    public let state: NativeMokuSceneState
    private let outside: Outside
    private let dock: Dock
    private let settings: Settings
    private let closeSettings: () -> Void
    public init(state: NativeMokuSceneState, @ViewBuilder outside: () -> Outside,
                @ViewBuilder dock: () -> Dock,
                onCloseSettings: (() -> Void)? = nil,
                @ViewBuilder settings: () -> Settings) {
        self.state = state; self.outside = outside(); self.dock = dock(); self.settings = settings()
        self.closeSettings = onCloseSettings ?? { state.closeSettings() }
    }
    public var body: some View {
        ZStack {
            outside
                .allowsHitTesting(!state.settingsOpen)
                .accessibilityHidden(state.settingsOpen)
                .blur(radius: state.settingsExpanded ? 12 : 0)
            if state.settingsOpen {
                Color.black.opacity(state.settingsExpanded ? 0.08 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { if !state.settingsClosing { closeSettings() } }
                    .accessibilityHidden(true)
            }
            // One resident instance spans Overview and reading panels. Other
            // application pages and covering routes remain ineligible for the Dock.
            if !state.dockCovered || state.settingsOpen {
                Group {
                    if state.dockRouteVisible {
                        NativeMokuHorizontalTravel {
                            dock.environment(\.nativeMokuSettingsContent, AnyView(settings))
                        }
                        .transition(.opacity)
                    }
                }
                .allowsHitTesting(state.dockRouteVisible)
                .accessibilityHidden(!state.dockRouteVisible)
                .disabled(!state.dockRouteVisible)
                .animation(.smooth(duration: 0.42, extraBounce: 0), value: state.dockRouteVisible)
            }
        }
        .background { NativeExecutionDockRegion(placement: state.executionDockPlacement, isScene: true) }
        .modifier(NativeSettingsTransition(state: state))
        .environment(\.nativeExecutionDockPlacement, state.executionDockPlacement)
        .environment(\.nativeCanvasInputRegions, state.canvasInputRegions)
        .environment(\.nativeReadingInputCancellation, { state.dismissInputForEscape() })
        .onAppear { state.setWindowVisible(true) }
        .onDisappear { state.setWindowVisible(false) }
    }
}
