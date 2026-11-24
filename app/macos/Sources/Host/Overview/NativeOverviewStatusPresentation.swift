import ChiefPluginUI
import SwiftUI

struct NativeOverviewStatusEmptyState: View {
    let title: String
    let scrollHint: String?
    private let palette = NativePalette.overview

    var body: some View {
        Group {
            if let scrollHint {
                runningPanel(scrollHint: scrollHint)
                    .accessibilityIdentifier("overview.running.empty")
            } else {
                VStack(spacing: 8) {
                    NativeOverviewIdleMark(identifier: "overview.completed.logo", scale: 1.25)
                        .accessibilityHidden(true)
                    heading.modifier(OverviewCanvasLabelEdge())
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("overview.completed.empty")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var heading: some View {
        Text(title)
            .font(NativeTypography.inter(size: 15, weight: 650))
            .foregroundStyle(palette.ink.swiftUI)
    }

    private func runningPanel(scrollHint: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: NativeGeometry.overviewCardRadius)
        return VStack(spacing: 8) {
            NativeOverviewIdleMark(identifier: "overview.idle")
                .accessibilityHidden(true)
            VStack(spacing: 3) {
                heading
                HStack(spacing: 5) {
                    NativeIcon(name: "ArrowUp", size: 13)
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
    }
}
