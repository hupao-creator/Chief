import ChiefPluginUI
import SwiftUI

struct NativeOverviewStatusEmptyState: View {
    let title: String
    let scrollHint: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let palette = NativePalette.overview

    var body: some View {
        Group {
            if let scrollHint {
                runningPanel(scrollHint: scrollHint)
                    .accessibilityIdentifier("overview.running.empty")
            } else {
                VStack(spacing: 8) {
                    skillet(identifier: "overview.completed.logo", scale: 1.25)
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

    private func skillet(identifier: String, scale: CGFloat = 1) -> some View {
        // The bowl is centered at x ≈ 232 in the 624 × 272 artwork. Reserve
        // 160 transparent pixels on the left so its axis bisects the layout.
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let phase = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 3.6) * 2 * .pi / 3.6
            Color.clear
                .aspectRatio(784.0 / 272.0, contentMode: .fit)
                .overlay(alignment: .trailing) {
                    NativeOverviewIdleMark(identifier: identifier, scale: scale)
                        .offset(y: scale * 1.6 * sin(phase))
                }
                .overlay {
                    GeometryReader { geometry in
                        let unit = geometry.size.width / 196
                        ForEach(0..<3) { index in
                            let step = CGFloat(index)
                            let drift = reduceMotion ? 0 : sin(phase - step * 0.7)
                            Text(verbatim: "z")
                                .font(.system(size: (11 + 2 * step) * unit, weight: .bold, design: .rounded))
                                .foregroundStyle(palette.ink.swiftUI)
                                .shadow(color: palette.surface.swiftUI, radius: unit)
                                .rotationEffect(.degrees(-9))
                                .position(x: (125 + step * 11 + drift) * unit,
                                          y: (-1 - step * 6 - 2 * drift) * unit)
                        }
                    }
                }
                .frame(maxWidth: 196 * scale, maxHeight: 68 * scale)
                .padding(.top, 25 * scale)
        }
        .accessibilityHidden(true)
    }

    private var heading: some View {
        Text(title)
            .font(NativeTypography.inter(size: 15, weight: 650))
            .foregroundStyle(palette.ink.swiftUI)
    }

    private func runningPanel(scrollHint: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: NativeGeometry.overviewCardRadius)
        return VStack(spacing: 8) {
            skillet(identifier: "overview.idle")
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
