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
                        EdgeReflection(reach: CGFloat(reach)).padding(-EdgeReflection.inset)
                    }
                }
                .environment(\.threadCardProviderColor, plugin.themeColor ?? palette.provider.swiftUI)
        }
        .frame(width: NativeGeometry.overviewCard.width)
    }
}

/// Keep the corner's footprint fixed and sweep light across it in badge coordinates.
private struct EdgeReflection: View {
    let reach: CGFloat
    @Environment(\.threadCardProviderColor) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.threadCardCloudAnimationsEnabled) private var enabled

    static let inset: CGFloat = 6
    private static let pitch = (ThreadCardProviderStatus.diameter / 2 - 1) / 4
    // ThreadCardBrand places the 44pt badge 17pt from the right and 12pt from the top.
    private static let badgeCenter = CGPoint(
        x: inset + NativeGeometry.overviewCard.width - 17 - ThreadCardProviderStatus.diameter / 2,
        y: inset + 12 + ThreadCardProviderStatus.diameter / 2)

    private static let metalwork: (rim: Path, lip: Path, holes: Path) = {
        let size = NativeGeometry.overviewCard
        let paper = CGRect(origin: CGPoint(x: inset, y: inset), size: size)
        let radius = NativeGeometry.overviewCardRadius
        func outline(inset: CGFloat) -> Path {
            Path(roundedRect: paper.insetBy(dx: inset, dy: inset), cornerRadius: radius - inset, style: .continuous)
        }
        var lip = outline(inset: 3)
        lip.addPath(outline(inset: 12))
        var holes = Path()
        let firstX = badgeCenter.x - floor((badgeCenter.x - paper.minX) / pitch) * pitch
        let firstY = badgeCenter.y - floor((badgeCenter.y - paper.minY) / pitch) * pitch
        for y in stride(from: firstY, to: paper.maxY, by: pitch) {
            for x in stride(from: firstX, to: paper.maxX, by: pitch)
            where y < paper.minY + 15 || x > paper.maxX - 15 {
                holes.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
            }
        }
        return (outline(inset: 0.5), lip, holes)
    }()

    var body: some View {
        let still = reduceMotion || !enabled
        let tint = accent
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { timeline in
            Canvas { context, size in
                let time = still ? 0.8 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.8)
                let phase = min(1, time / 2.25)
                guard phase < 1 else { return }
                // The production CA bands peak at column + row = 20 * phase - 10.
                // Past the outermost badge diagonal, extend the travel smoothly
                // so one crest can also enter and leave the longest card edge.
                let diagonal = 20 * phase - 10
                let outside = max(0, abs(diagonal) - 6) / 4
                let extra = CGFloat(PerforationReach.edge.rawValue) * outside * outside
                let travel = Self.pitch * diagonal + (diagonal < 0 ? -extra : extra)
                let crest = CGPoint(x: Self.badgeCenter.x + travel / 2,
                                    y: Self.badgeCenter.y + travel / 2)
                // A soft wash keeps each approved footprint visible while the
                // stronger moving crest reads as the continuation of the badge.
                func band(halfWidth: CGFloat, wash: Double = 0) -> GraphicsContext.Shading {
                    let shoulder = tint.opacity(wash + (1 - wash) * 0.4)
                    let highlight = Gradient(colors: [tint.opacity(wash), shoulder, tint, shoulder, tint.opacity(wash)])
                    let tail = halfWidth / 2
                    return .linearGradient(highlight, startPoint: CGPoint(x: crest.x - tail, y: crest.y - tail),
                        endPoint: CGPoint(x: crest.x + tail, y: crest.y + tail))
                }
                let paper = CGRect(origin: .zero, size: size).insetBy(dx: Self.inset, dy: Self.inset)
                let cornerInset = NativeGeometry.overviewCardRadius * (1 - sqrt(0.5))
                let corner = CGPoint(x: paper.maxX - cornerInset, y: paper.minY + cornerInset)
                context.clipToLayer { mask in
                    mask.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(Gradient(stops: [
                        .init(color: .white.opacity(0.86), location: 0),
                        .init(color: .white.opacity(0.53), location: 0.42),
                        .init(color: .white.opacity(0.15), location: 0.78),
                        .init(color: .white.opacity(0), location: 1)
                    ]), center: corner, startRadius: 0, endRadius: reach))
                }
                let geometry = Self.metalwork
                let ink = band(halfWidth: 8 * Self.pitch, wash: 0.45 * pow(sin(.pi * phase), 2))
                context.drawLayer { bloom in
                    bloom.opacity = 0.46
                    bloom.addFilter(.blur(radius: 3.5))
                    bloom.stroke(geometry.rim, with: ink, lineWidth: 5)
                }
                context.stroke(geometry.rim, with: ink, lineWidth: 1.2)
                var texture = context
                texture.clip(to: geometry.lip, style: FillStyle(eoFill: true))
                texture.opacity = 0.48
                texture.fill(geometry.holes, with: band(halfWidth: 2.5 * Self.pitch))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
