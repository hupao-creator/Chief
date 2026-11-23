import ChiefPluginAPI
import SwiftUI

public extension EnvironmentValues {
    /// Use the Agent reader's loading presentation in place of compact indicators.
    @Entry var nativeThreadUsesLoadingSkeleton = false
}

/// Presentation only: the owner still decides whether content is loading.
public struct NativeReadingPlaceholder: View {
    public enum Placement {
        case surface, inline
        /// Whole reader, already inside ThreadConversation; never rebuild its heading here.
        case admission
    }

    private let placement: Placement
    @Environment(\.nativeThreadUsesLoadingSkeleton) private var usesLoadingSkeleton
    @Environment(\.nativeThreadIdentityVisit) private var identityVisit
    @Environment(\.locale) private var locale
    @State private var visible = false

    public init(placement: Placement = .surface) {
        self.placement = placement
    }

    private var loadingText: String {
        locale.language.languageCode?.identifier == "zh" ? "正在读取…" : "Loading…"
    }

    public var body: some View {
        Group {
            if usesLoadingSkeleton && placement == .surface && identityVisit != nil {
                NativeThreadOpeningContent(showsLoading: visible)
            } else if placement != .inline {
                if visible {
                    NativeSurfaceLoading(usesLoadingSkeleton ? nil : loadingText)
                } else {
                    Color.clear
                }
            } else if usesLoadingSkeleton {
                NativeThreadLoadingSkeleton().frame(maxWidth: NativeGeometry.readingWidth)
                    .nativeThreadDocumentMargins()
            } else {
                Text(loadingText)
                    .font(NativeTypography.inter(size: 13))
                    .foregroundStyle(NativePalette.thread.muted.swiftUI)
                    .padding(.vertical, 16)
                    .nativeThreadDocumentMargins()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
            .transformPreference(NativeReadingContentStatusKey.self) { status in
                // A loaded sibling (for example a system error) cannot admit
                // auxiliary input while this document is still being acquired.
                // Readiness starts waiting before the visual grace period ends.
                status.pending = status.pending || usesLoadingSkeleton
            }
            // Reserve the same geometry during the grace period. Inline loading
            // must never claim viewport height or change the reader's scroll extent.
            .opacity(visible || (usesLoadingSkeleton && placement == .surface && identityVisit != nil) ? 1 : 0)
            .accessibilityHidden(!visible)
            .allowsHitTesting(false)
            .task {
                visible = false
                do { try await Task.sleep(for: .milliseconds(180)) }
                catch { return }
                guard !Task.isCancelled else { return }
                visible = true
            }
            .onDisappear { visible = false }
    }
}

/// Initial Harness decoding can own the viewport or a single materialized row.
public struct NativeHarnessLoadingIndicator: View {
    private let content: HarnessContentMode
    public init(content: HarnessContentMode) { self.content = content }
    public var body: some View {
        if case .row = content { NativeThreadLoadingIndicator() }
        else { NativeReadingPlaceholder() }
    }
}

/// Keep each scoped row's compact spinner outside the main Agent reader.
public struct NativeThreadLoadingIndicator: View {
    @Environment(\.nativeThreadUsesLoadingSkeleton) private var usesLoadingSkeleton
    private let alignedLeading: Bool
    public init(alignedLeading: Bool = false) { self.alignedLeading = alignedLeading }
    public var body: some View {
        if usesLoadingSkeleton { NativeReadingPlaceholder(placement: .inline) }
        else {
            ProgressView().controlSize(.small)
                .frame(maxWidth: alignedLeading ? .infinity : nil, alignment: .leading)
                .padding(.vertical, 16)
        }
    }
}
