import ChiefPluginUI
import SwiftUI

struct NativeOverviewCompletedState: View {
    let title: String
    let swipeHint: String
    private let palette = NativePalette.overview
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: NativeGeometry.overviewCardRadius)
        VStack(spacing: 8) {
            NativeOverviewIdleMark(identifier: "overview.completed.logo")
                .accessibilityHidden(true)
            VStack(spacing: 3) {
                Text(title)
                    .font(NativeTypography.inter(size: 15, weight: 650))
                    .foregroundStyle(palette.ink.swiftUI)
                HStack(spacing: 5) {
                    NativeIcon(name: "ArrowUp", size: 13)
                    Text(swipeHint)
                }
                .font(NativeTypography.inter(size: 12, weight: 520))
                .foregroundStyle(palette.ink.swiftUI.opacity(0.90))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            // Keep the adaptive fill above the material so the backdrop cannot wash out the text.
            .background(palette.surfaceStrong.swiftUI.opacity(reduceTransparency ? 1 : 0.90), in: shape)
            .background { if !reduceTransparency { shape.fill(.regularMaterial) } }
            .overlay { shape.strokeBorder(palette.line.swiftUI, lineWidth: 1) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("overview.completed.empty")
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
