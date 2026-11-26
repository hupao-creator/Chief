import ChiefHarnessCodex
import ChiefPluginUI
import SwiftUI

enum PerforationReach: CaseIterable {
    case badge, header, passages, card

    var name: String {
        switch self {
        case .badge: "现状"
        case .header: "候选 A"
        case .passages: "候选 B"
        case .card: "候选 C"
        }
    }

    var caption: String {
        switch self {
        case .badge: "仅徽章内"
        case .header: "右上斜掠"
        case .passages: "穿过行间"
        case .card: "漫游全卡"
        }
    }

    // Measured along the flow, which runs left and down from the badge.
    var reach: CGFloat {
        switch self {
        case .badge: 0
        case .header: 146
        case .passages: 288
        case .card: 570
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
        let visibleScope = showBaseline ? PerforationReach.badge : scope
        let shell = RoundedRectangle(cornerRadius: NativeGeometry.overviewCardRadius)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(scope.name).font(.system(size: 14, weight: .semibold))
                Text(visibleScope.caption)
                Spacer()
            }
            .font(.system(size: 12))
            .foregroundStyle(palette.ink.swiftUI.opacity(0.8))
            .padding(.horizontal, 4)

            HarnessThreadCard(identity: identity, presentation: Self.presentation,
                status: .init(kind: .running, label: "运行中"), emoji: emoji,
                harnessLogo: AnyView(plugin.logo(size: 12)))
                .frame(width: NativeGeometry.overviewCard.width, height: NativeGeometry.overviewCard.height)
                .background {
                    if visibleScope != .badge {
                        CardPerforations(scope: visibleScope).clipShape(shell)
                    }
                }
                .background(shell.fill(palette.surface.swiftUI))
                .overlay(shell.strokeBorder(palette.lineSoft.swiftUI, lineWidth: 1))
                .environment(\.threadCardProviderColor, plugin.themeColor ?? palette.provider.swiftUI)
        }
        .frame(width: NativeGeometry.overviewCard.width)
    }
}

/// A fixture-only field under the transparent content of the mounted card.
/// All three crops reveal the same lattice and the same traveling crests.
private struct CardPerforations: View {
    let scope: PerforationReach
    @Environment(\.threadCardProviderColor) private var lit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.threadCardCloudAnimationsEnabled) private var enabled

    private struct Band {
        let travel: CGFloat
        let strength: Double
        let holes: Path
    }

    // Guide curves follow empty space in the fixed 320 × 196 fixture. Sample
    // their distance once, giving the sweep soft edges without fading the card.
    private struct Lane {
        let from: CGPoint
        let bend: CGPoint
        let to: CGPoint
        let halfWidth: CGFloat

        var samples: [CGPoint] {
            (0...64).map { i in
                let t = CGFloat(i) / 64, u = 1 - t
                return CGPoint(x: u*u*from.x + 2*u*t*bend.x + t*t*to.x,
                               y: u*u*from.y + 2*u*t*bend.y + t*t*to.y)
            }
        }
    }

    private static let fields: [PerforationReach: [Band]] = {
        let size = NativeGeometry.overviewCard
        let radius = ThreadCardProviderStatus.diameter / 2
        let center = CGPoint(x: size.width - 17 - radius, y: 12 + radius)
        let pitch = (radius - 1) / 4
        let lanes = [
            Lane(from: center, bend: .init(x: 210, y: 52), to: .init(x: 141, y: 78), halfWidth: 21),
            Lane(from: center, bend: .init(x: 160, y: -4), to: .init(x: 12, y: 12), halfWidth: 11),
            Lane(from: center, bend: .init(x: 322, y: 96), to: .init(x: 260, y: 185), halfWidth: 24),
            Lane(from: .init(x: 294, y: 103), bend: .init(x: 192, y: 126), to: .init(x: 16, y: 108), halfWidth: 12),
            Lane(from: .init(x: 288, y: 141), bend: .init(x: 160, y: 160), to: .init(x: 22, y: 144), halfWidth: 13),
            Lane(from: .init(x: 268, y: 182), bend: .init(x: 137, y: 195), to: .init(x: 9, y: 178), halfWidth: 14)
        ].map { (points: $0.samples, width: $0.halfWidth) }
        // Exclude the actual title, metadata and excerpt lines from the field.
        let clearText = [
            CGRect(x: 13, y: 17, width: 236, height: 21),
            CGRect(x: 13, y: 40, width: 132, height: 18),
            CGRect(x: 13, y: 60, width: 133, height: 16),
            CGRect(x: 13, y: 84, width: 249, height: 18),
            CGRect(x: 13, y: 120, width: 224, height: 18),
            CGRect(x: 13, y: 156, width: 246, height: 18)
        ]
        struct Key: Hashable { let step: Int; let weight: Int }
        var byScope: [PerforationReach: [Key: Path]] = [:]
        for row in Int(floor(-center.y / pitch))...Int(ceil((size.height - center.y) / pitch)) {
            for column in Int(floor(-center.x / pitch))...Int(ceil((size.width - center.x) / pitch)) {
                let dx = CGFloat(column) * pitch, dy = CGFloat(row) * pitch
                let p = CGPoint(x: center.x + dx, y: center.y + dy)
                guard hypot(dx, dy) > radius + 1, !clearText.contains(where: { $0.contains(p) }) else { continue }
                let weight = lanes.map { lane in
                    let distance = lane.points.map { hypot($0.x - p.x, $0.y - p.y) }.min() ?? lane.width
                    return max(0, 1 - distance / lane.width)
                }.max() ?? 0
                let travel = max(0, -dx) + max(0, dy) * 1.45 + max(0, dx) + max(0, -dy) * 0.55
                for scope in [PerforationReach.header, .passages, .card] {
                    let edge = min(1, max(0, (scope.reach - travel) / 24))
                    let opacity = Int((weight * edge * 5).rounded())
                    guard opacity > 0 else { continue }
                    let key = Key(step: Int((travel / pitch).rounded()), weight: opacity)
                    byScope[scope, default: [:]][key, default: Path()]
                        .addEllipse(in: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2))
                }
            }
        }
        return byScope.mapValues { paths in
            paths.map { Band(travel: CGFloat($0.key.step) * pitch,
                             strength: Double($0.key.weight) / 5, holes: $0.value) }
        }
    }()

    var body: some View {
        let still = reduceMotion || !enabled
        let bands = Self.fields[scope] ?? []
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { timeline in
            Canvas { context, _ in
                let t = still ? 0.8 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.8)
                let phase = min(1, t / 2.25)
                let envelope = min(1, max(0, (1 - phase) * 9), phase * 9)
                for band in bands {
                    let position = band.travel / 124 - phase
                    let distance = (position - position.rounded()) / 0.14
                    let crest = exp(-distance * distance) * envelope
                    context.fill(band.holes, with: .color(NativePalette.overview.muted.swiftUI.opacity(0.32 * band.strength)))
                    context.fill(band.holes, with: .color(lit.opacity(0.76 * crest * band.strength)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
