import ChiefPluginUI
import SwiftUI

struct NativeOverviewStatusEmptyState: View {
    let title: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let palette = NativePalette.overview
    private let scale: CGFloat = 1.25

    var body: some View {
        VStack(spacing: 8) {
            skillet
            Text(title)
                .font(NativeTypography.inter(size: 15, weight: 650))
                .foregroundStyle(palette.ink.swiftUI)
                .modifier(OverviewCanvasLabelEdge())
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("overview.status.empty")
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var skillet: some View {
        // The bowl is centered at x ≈ 232 in the 624 × 272 artwork. Reserve
        // 160 transparent pixels on the left so its axis bisects the layout.
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let phase = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 3.6) * 2 * .pi / 3.6
            Color.clear
                .aspectRatio(784.0 / 272.0, contentMode: .fit)
                .overlay(alignment: .trailing) {
                    NativeOverviewIdleMark(identifier: "overview.status.empty.logo", scale: scale)
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
}
