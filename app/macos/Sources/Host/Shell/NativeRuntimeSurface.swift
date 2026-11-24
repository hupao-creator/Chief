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
            if model.hasInitialContent && !model.waitingForInitialCatalog {
                content
            }
            else {
                RuntimeStartupScreen(state: model.waitingForInitialCatalog ? .connecting : model.connection,
                    error: model.connectionError ?? "",
                    reconnecting: model.reconnecting, locale: model.locale,
                    onReconnect: { Task { await model.retry() } },
                    announcementsEnabled: !model.settingsOpen)
            }
        }
    }
}

private struct RuntimeStartupScreen: View {
    let state: RuntimeConnectionStatus
    let error: String
    let reconnecting: Bool
    let locale: DesktopLocale
    let onReconnect: () -> Void
    var announcementsEnabled = true
    private var connecting: Bool { reconnecting || state == .connecting }
    private var loading: Bool { reconnecting || (error.isEmpty && (connecting || state == .connected)) }
    private var message: String {
        state == .stopped ? locale.text("后台服务已停止", "The background service has stopped")
            : locale.text("无法连接到 Chief 的后台服务", "Unable to connect to Chief’s background service")
    }

    var body: some View {
        Group {
            if loading {
                NativeSurfaceLoading()
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
