import ChiefPluginUI
import SwiftUI

struct NativeOverviewCompletedState: View {
    let title: String
    let swipeHint: String
    private let palette = NativePalette.overview

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: NativeGeometry.overviewCardRadius)
        VStack(spacing: 10) {
            NativeIcon(name: "CircleCheck", size: 21)
                .foregroundStyle(palette.accent.swiftUI)
                .frame(width: 40, height: 40)
                .background(palette.accentSoft.swiftUI, in: Circle())
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
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background {
            // Stabilize the text contrast when the material samples a bright or dark desktop.
            shape.fill(palette.surfaceStrong.swiftUI.opacity(0.90))
                .nativeRegularCardGlass(in: shape, opaque: palette.surfaceStrong.swiftUI)
        }
        .overlay { shape.strokeBorder(palette.line.swiftUI, lineWidth: 1) }
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
