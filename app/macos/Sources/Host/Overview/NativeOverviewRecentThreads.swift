import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI

struct NativeOverviewRecentThread: Identifiable {
    let id: JSONText
    let title: String
    let harness: AnyHarnessPlugin
    let date: Date
}

struct NativeOverviewRecentThreadList: View {
    static let idealWidth: CGFloat = 344
    static let minimumWidth: CGFloat = 222
    static let rowHeight: CGFloat = 32
    // The label, gap and surface padding outside the rows.
    static let verticalChrome: CGFloat = 32

    let title: String
    let threads: [NativeOverviewRecentThread]
    let open: (JSONText) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.threadCardUsesFlatMaterials) private var flatMaterials
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    private let shell = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(NativeTypography.inter(size: 12, weight: 620))
                .foregroundStyle(NativePalette.overview.ink.swiftUI)
                .padding(.horizontal, 8)
                .background {
                    Capsule().fill(NativePalette.overview.surface.swiftUI)
                        .padding(.vertical, -2)
                }
                .accessibilityAddTraits(.isHeader)
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                let format = Date.RelativeFormatStyle(presentation: .numeric, unitsStyle: .narrow, locale: locale)
                VStack(spacing: 0) {
                    ForEach(threads) { thread in
                        NativeOverviewRecentThreadRow(title: thread.title, harness: thread.harness,
                            metadata: format.format(thread.date),
                            first: thread.id == threads.first?.id,
                            last: thread.id == threads.last?.id) { open(thread.id) }
                    }
                }
            }
            .clipShape(shell)
            .background {
                if !flatMaterials && !reduceTransparency && contrast != .increased {
                    Color.clear.nativeRegularCardGlass(in: shell,
                        opaque: NativePalette.overview.surface.swiftUI,
                        tint: NativePalette.overview.surface.swiftUI.opacity(0.82))
                        .allowsHitTesting(false)
                } else {
                    shell.fill(NativePalette.overview.surface.swiftUI)
                        .strokeBorder(NativePalette.overview.lineSoft.swiftUI)
                }
            }
        }
    }
}

struct NativeOverviewRecentThreadRow: View {
    let title: String
    let harness: AnyHarnessPlugin
    let metadata: String
    var first = false
    var last = false
    let open: () -> Void

    var body: some View {
        let name = harness.descriptor.displayName.string
        Button(action: open) {
            HStack(spacing: 8) {
                harness.logo(size: 17)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(title)
                    .font(NativeTypography.inter(size: 13, weight: 560))
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(metadata)
                    .font(NativeTypography.inter(size: 11, weight: 480))
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: NativeOverviewRecentThreadList.rowHeight)
            // Include the end insets in the row's fill and hit area.
            .padding(.top, first ? 4 : 0)
            .padding(.bottom, last ? 4 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(NativeOverviewRecentThreadButtonStyle(first: first, last: last))
        .help(name)
        .accessibilityLabel("\(title), \(name)")
        .accessibilityValue(metadata)
    }
}

private struct NativeOverviewRecentThreadButtonStyle: ButtonStyle {
    let first: Bool
    let last: Bool
    @Environment(\.isFocused) private var focused
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let palette = NativePalette.overview
        let focusShape = UnevenRoundedRectangle(
            topLeadingRadius: first ? 15 : 7, bottomLeadingRadius: last ? 15 : 7,
            bottomTrailingRadius: last ? 15 : 7, topTrailingRadius: first ? 15 : 7)
        return configuration.label
            .foregroundStyle(palette.ink.swiftUI)
            .background {
                if hovered || configuration.isPressed {
                    palette.accentSoft.swiftUI.opacity(0.62)
                        .overlay(palette.ink.swiftUI.opacity(configuration.isPressed ? 0.06 : 0))
                }
            }
            .overlay {
                if focused {
                    focusShape
                        .strokeBorder(NativePalette.overviewAccentText.swiftUI, lineWidth: 2)
                        .padding(1)
                        .allowsHitTesting(false)
                }
            }
            .onHover { hovered = $0 }
    }
}
