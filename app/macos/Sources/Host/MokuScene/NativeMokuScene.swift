import ChiefPluginUI
import SwiftUI

public struct NativeMokuScene<Outside: View, Dock: View, Settings: View>: View {
    public let state: NativeMokuSceneState
    private let outside: Outside
    private let dock: Dock
    private let settings: Settings
    private let closeSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var dockMounted: Bool
    @State private var visibilityGeneration = 0
    @State private var inkVisible: Bool
    private var showsDock: Bool { state.dockRouteVisible && (!state.dockCovered || state.settingsOpen) }

    public init(state: NativeMokuSceneState, @ViewBuilder outside: () -> Outside,
                @ViewBuilder dock: () -> Dock,
                onCloseSettings: (() -> Void)? = nil,
                @ViewBuilder settings: () -> Settings) {
        self.state = state; self.outside = outside(); self.dock = dock(); self.settings = settings()
        let visible = state.dockRouteVisible && (!state.dockCovered || state.settingsOpen)
        _dockMounted = State(initialValue: visible)
        _inkVisible = State(initialValue: visible)
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
            ZStack {
                if dockMounted || showsDock {
                    NativeMokuHorizontalTravel {
                        dock.environment(\.nativeMokuSettingsContent, AnyView(settings))
                    }
                    .transition(.identity)
                }
            }
            .opacity(inkVisible ? 1 : 0)
            .allowsHitTesting(showsDock)
            .accessibilityHidden(!showsDock)
            .disabled(!showsDock)
            .onChange(of: showsDock) { _, visible in
                // The AppKit host must survive its last visible frame. A return
                // redirects the same opacity and keeps the mounted editor.
                if visible { dockMounted = true }
                visibilityGeneration &+= 1
                let generation = visibilityGeneration
                let motion: Animation? = reduceMotion || scenePhase != .active ? nil : .mokuInk
                withAnimation(motion, completionCriteria: .removed) {
                    inkVisible = visible
                } completion: {
                    if visibilityGeneration == generation && !inkVisible { dockMounted = false }
                }
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
