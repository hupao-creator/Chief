import ChiefHarnessCodex
import ChiefPluginUI
import SwiftUI

enum PerforationReach: Int {
    case badge = 0, near = 42, corner = 88, edge = 156

    var name: String {
        switch self {
        case .badge: "对照"
        case .near: "A · 徽章旁"
        case .corner: "B · 正式版"
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
                .threadCardRunningEdge(reach: CGFloat(reach))
                .environment(\.threadCardProviderColor, plugin.themeColor ?? palette.provider.swiftUI)
        }
        .frame(width: NativeGeometry.overviewCard.width)
    }
}
