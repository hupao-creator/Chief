import ChiefHarnessCodex
import ChiefPluginUI
import SwiftUI

enum PerforationReach: Int {
    case badge = 0, near = 42, corner = 88, edge = 156

    var name: String {
        switch self {
        case .badge: "现状"
        case .near: "A · 徽章旁"
        case .corner: "B · 右上角"
        case .edge: "C · 两侧卡边"
        }
    }
}

struct PerforationRangeSample: View {
    let scope: PerforationReach
    let showBaseline: Bool
    private let palette = NativePalette.overview
    private let plugin = CodexHarnessPlugin()
    private let emoji = "🎞️"

    private static let presentation: ThreadCardPresentation = {
        let cell = ThreadCardSize(cols: 1, rows: 1)
        let projection = ThreadCardProjection.standard(identity: .init(usage: .init(parts: [
            .init(suffix: "tokens", id: "tokens", value: "81.2K", numericValue: 81_200)
        ])), extensions: [])
        return .init(projection: projection, composition: .slots(size: cell, identitySize: cell,
            slots: [], key: "range"), size: cell, key: "range")
    }()

    var body: some View {
        let brand = ThreadCardHarnessBrand(brandKey: plugin.descriptor.id.string,
            label: plugin.descriptor.displayName.string, logoSource: plugin.logoSource)
        let identity = ThreadCardIdentityView(title: "让启动动画无缝过渡到 Overview 页面", harness: brand,
            model: "gpt-6.2-astra", effort: "high", runtime: .init(startedAt: 0, endedAt: 186_000),
            excerpt: "Optimizing geometry and state management\n\nRefining state initialization and lifecycle\n\nDesigning state management with closures")
        let reach = showBaseline ? 0 : scope.rawValue
        let shell = RoundedRectangle(cornerRadius: NativeGeometry.overviewCardRadius)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(scope.name).font(.system(size: 14, weight: .semibold))
                Text(reach == 0 ? "仅徽章内" : "\(reach) pt").monospacedDigit()
                Spacer()
            }
            .font(.system(size: 12))
            .foregroundStyle(palette.ink.swiftUI.opacity(0.8))
            .padding(.horizontal, 4)

            HarnessThreadCard(identity: identity, presentation: Self.presentation,
                status: .init(kind: .running, label: "运行中"), emoji: emoji,
                harnessLogo: AnyView(plugin.logo(size: 12)))
                .frame(width: NativeGeometry.overviewCard.width, height: NativeGeometry.overviewCard.height)
                .background(shell.fill(palette.surface.swiftUI))
                .overlay(shell.strokeBorder(palette.lineSoft.swiftUI, lineWidth: 1))
                .overlay {
                    if reach > 0 {
                        EdgeReflection(reach: CGFloat(reach)).padding(-6)
                    }
                }
                .environment(\.threadCardProviderColor, plugin.themeColor ?? palette.provider.swiftUI)
        }
        .frame(width: NativeGeometry.overviewCard.width)
    }
}

/// One light grazes the card edge. The same gradient reveals the perforations
/// in the paper lip, so the dots never need individual animation clocks.
private struct EdgeReflection: View {
    let reach: CGFloat
    @Environment(\.threadCardProviderColor) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.threadCardCloudAnimationsEnabled) private var enabled

    private static let metalwork: (rim: Path, lip: Path, holes: Path) = {
        let size = NativeGeometry.overviewCard
        let paper = CGRect(origin: CGPoint(x: 6, y: 6), size: size)
        let radius = NativeGeometry.overviewCardRadius
        func outline(inset: CGFloat) -> Path {
            Path(roundedRect: paper.insetBy(dx: inset, dy: inset), cornerRadius: radius - inset, style: .continuous)
        }
        var lip = outline(inset: 3)
        lip.addPath(outline(inset: 12))
        var holes = Path()
        let pitch = (ThreadCardProviderStatus.diameter / 2 - 1) / 4
        for y in stride(from: paper.minY + 2, to: paper.maxY, by: pitch) {
            for x in stride(from: paper.minX + 2, to: paper.maxX, by: pitch)
            where y < paper.minY + 15 || x > paper.maxX - 15 {
                holes.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
            }
        }
        return (outline(inset: 0.5), lip, holes)
    }()

    var body: some View {
        let still = reduceMotion || !enabled
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { timeline in
            Canvas { context, size in
                let time = still ? 1.12 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.8)
                let phase = min(1, time / 2.25)
                let lift = pow(sin(.pi * phase), 2)
                guard lift > 0.001 else { return }
                // The highlight travels round the corner while both its reach
                // and intensity ease away. Text is always outside the drawn lip.
                let angle = (1 - phase) * .pi / 2
                let radius = NativeGeometry.overviewCardRadius
                let light = CGPoint(x: size.width - 6 - radius + radius * cos(angle),
                                    y: 6 + radius - radius * sin(angle))
                let gradient = Gradient(stops: [
                    .init(color: accent.opacity(0.86 * lift), location: 0),
                    .init(color: accent.opacity(0.53 * lift), location: 0.42),
                    .init(color: accent.opacity(0.15 * lift), location: 0.78),
                    .init(color: accent.opacity(0), location: 1)
                ])
                let ink = GraphicsContext.Shading.radialGradient(gradient, center: light,
                    startRadius: 0, endRadius: reach * (0.6 + 0.4 * lift))
                let geometry = Self.metalwork
                context.drawLayer { bloom in
                    bloom.opacity = 0.46
                    bloom.addFilter(.blur(radius: 3.5))
                    bloom.stroke(geometry.rim, with: ink, lineWidth: 5)
                }
                context.stroke(geometry.rim, with: ink, lineWidth: 1.2)
                var texture = context
                texture.clip(to: geometry.lip, style: FillStyle(eoFill: true))
                texture.opacity = 0.48
                texture.fill(geometry.holes, with: ink)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
