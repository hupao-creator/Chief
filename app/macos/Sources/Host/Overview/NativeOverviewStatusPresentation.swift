import ChiefPluginUI
import SwiftUI

struct NativeOverviewStatusEmptyState: View {
    let title: String
    let scrollHint: String
    let up: Bool
    private let palette = NativePalette.overview

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: NativeGeometry.overviewCardRadius)
        VStack(spacing: 8) {
            NativeOverviewIdleMark(identifier: up ? "overview.completed.logo" : "overview.idle")
                .accessibilityHidden(true)
            VStack(spacing: 3) {
                Text(title)
                    .font(NativeTypography.inter(size: 15, weight: 650))
                    .foregroundStyle(palette.ink.swiftUI)
                HStack(spacing: 5) {
                    NativeIcon(name: up ? "ArrowUp" : "ArrowDown", size: 13)
                    Text(scrollHint)
                }
                .font(NativeTypography.inter(size: 12, weight: 520))
                .foregroundStyle(palette.ink.swiftUI.opacity(0.90))
            }
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            // Keep the text's adaptive fill above the glass, with more translucency around the artwork.
            LinearGradient(stops: [
                .init(color: palette.surfaceStrong.swiftUI.opacity(0.30), location: 0),
                .init(color: palette.surfaceStrong.swiftUI.opacity(0.92), location: 0.62)
            ], startPoint: .top, endPoint: .bottom)
            .clipShape(shape)
        }
        .background {
            Color.clear.nativeRegularCardGlass(in: shape, opaque: palette.surfaceStrong.swiftUI)
        }
        .overlay { shape.strokeBorder(palette.line.swiftUI.opacity(0.7), lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(up ? "overview.completed.empty" : "overview.running.empty")
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

struct NativeOverviewCompletedFilterBadge: View {
    let title: String
    private let palette = NativePalette.overview

    var body: some View {
        HStack(spacing: 5) {
            NativeIcon(name: "Check", size: 12)
            Text(title).font(NativeTypography.inter(size: 11, weight: 620))
        }
        .foregroundStyle(palette.ink.swiftUI)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(palette.accentSoft.swiftUI, in: Capsule())
        .overlay { Capsule().strokeBorder(palette.line.swiftUI, lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("overview.completed.filter")
        .allowsHitTesting(false)
    }
}
