import ChiefCore
import ChiefPluginUI
import SwiftUI

/// Shows startup and recovery until the workspace can present a catalog.
public struct NativeRuntimeSurface<Content: View>: View {
    @Bindable private var model: NativeWorkspaceModel
    private let content: Content

    public init(model: NativeWorkspaceModel, @ViewBuilder content: () -> Content) {
        self.model = model
        self.content = content()
    }

    public var body: some View {
        ZStack {
            let phase = model.runtimeSurface
            switch phase {
            case .workspace:
                content
            case .loading, .recovery:
                RuntimeStartupScreen(loading: phase == .loading,
                    state: model.waitingForInitialCatalog ? .connecting : model.connection,
                    error: model.connectionError ?? "",
                    reconnecting: model.reconnecting, locale: model.locale,
                    onReconnect: { Task { await model.retry() } }, announcementsEnabled: !model.settingsOpen)
            }
        }
    }
}

enum RuntimeSurfacePhase { case loading, recovery, workspace }

extension NativeWorkspaceModel {
    var runtimeSurface: RuntimeSurfacePhase {
        if hasInitialContent && !waitingForInitialCatalog { return .workspace }
        let status = waitingForInitialCatalog ? .connecting : connection
        return reconnecting || ((connectionError ?? "").isEmpty && (status == .connecting || status == .connected))
            ? .loading : .recovery
    }
}

extension EnvironmentValues {
    @Entry var startupLoadingSince: TimeInterval?
}

/// Supply one clock to the loading view, the Overview inside its AppKit host,
/// and the sibling Dock. Only a direct, visible loading → empty visit inherits it.
struct RuntimeSkilletAdmission: ViewModifier {
    let phase: RuntimeSurfacePhase?
    let eligible: () -> Bool
    @State private var previous: RuntimeSurfacePhase?
    @State private var loadingSince = CACurrentMediaTime()
    @State private var entrance: StartupSkilletEntrance?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Seed the very first destination layout; its nested host may draw
        // before onChange records this edge for the remaining frames.
        let arriving = previous == .loading && phase == .workspace
        let candidate = arriving ? StartupSkilletEntrance(loadingSince: loadingSince) : entrance
        let active = candidate != nil && phase == .workspace && !reduceMotion && eligible()
        content.environment(\.startupLoadingSince, loadingSince)
            .environment(\.startupSkilletEntrance, active ? candidate : nil)
            .onChange(of: phase, initial: true) { _, phase in
                previous = phase
                if phase == .loading { loadingSince = CACurrentMediaTime() }
                entrance = active ? candidate : nil
            }
            .task(id: active) {
                if active {
                    do { try await Task.sleep(for: .seconds(StartupSkilletEntrance.duration)) }
                    catch { return }
                }
                if !Task.isCancelled { entrance = nil }
            }
    }
}

private struct RuntimeStartupScreen: View {
    let loading: Bool
    let state: RuntimeConnectionStatus
    let error: String
    let reconnecting: Bool
    let locale: DesktopLocale
    let onReconnect: () -> Void
    var announcementsEnabled = true
    @Environment(\.startupLoadingSince) private var loadingSince
    @State private var mountedAt = CACurrentMediaTime()
    private var connecting: Bool { reconnecting || state == .connecting }
    private var message: String {
        state == .stopped ? locale.text("后台服务已停止", "The background service has stopped")
            : locale.text("无法连接到 Chief 的后台服务", "Unable to connect to Chief’s background service")
    }

    var body: some View {
        Group {
            if loading {
                NativeSurfaceLoading(startedAt: loadingSince ?? mountedAt)
                    .background(RuntimeLoadingDragRegion())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(locale.text("正在加载…", "Loading…"))
            } else {
                VStack(spacing: 14) {
                    Text(message).font(NativeTypography.inter(size: 14, weight: 700))
                    Text(locale.text("连接后台服务后即可继续工作。", "Reconnect to the background service to continue."))
                    if !error.isEmpty {
                        // <p> retains its normal one-em block margins in the
                        // original flex column, in addition to its 14px gap.
                        Text(error).fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled).frame(maxWidth: 480).padding(.vertical, 14)
                    }
                    HStack(spacing: 20) {
                        Button(locale.text("重新连接", "Reconnect"), action: onReconnect).disabled(connecting)

                    }.buttonStyle(RuntimeTextButtonStyle())
                }
                .font(NativeTypography.inter(size: 14))
                .foregroundStyle(NativePalette.overview.muted.swiftUI)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            RuntimeStatusAnnouncements(status: loading ? locale.text("正在加载…", "Loading…") : message,
                error: loading ? "" : error, enabled: announcementsEnabled).frame(width: 0, height: 0)
        }
    }
}

/// Announces startup status changes while the startup surface is active.
private struct RuntimeStatusAnnouncements: View {
    let status: String
    let error: String
    let enabled: Bool
    var body: some View {
        Color.clear.onChange(of: error.isEmpty ? status : error) { _, message in
            if enabled, !message.isEmpty { AccessibilityNotification.Announcement(message).post() }
        }
    }
}

private struct RuntimeTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { RuntimeTextButtonBody(label: configuration.label) }
}
private struct RuntimeTextButtonBody<Label: View>: View {
    let label: Label
    @State private var hovered = false
    var body: some View {
        label.font(NativeTypography.inter(size: 11, weight: 580))
            .padding(.horizontal, 13).frame(height: controlHeight)
            .foregroundStyle((hovered ? NativePalette.overview.ink : NativePalette.overview.muted).swiftUI)
            .background(hovered ? NativePalette.pair(0x20211e, 0xe0e5da, alpha: 0.05).swiftUI : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onHover { hovered = $0 }
    }

    private var controlHeight: CGFloat {
        32
    }
}

private struct RuntimeLoadingDragRegion: View {
    var body: some View {
        Color.clear.gesture(WindowDragGesture())
    }
}
