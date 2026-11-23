import ChiefPluginUI
import SwiftUI

enum BadgeStyle: String {
    case orbit = "游弧"
    case titanium = "拉丝钛"
    case latitude = "纬光"
    case matrix = "微孔点阵"
    case split = "对开"
    case duet = "双拍"
    case steps = "折线"

    var caption: String {
        switch self {
        case .orbit: "短弧沿圆周匀速绕行"
        case .titanium: "一束冷光掠过哑光金属"
        case .latitude: "亮色沿球面逐层下行"
        case .matrix: "一列微孔点亮，斜向传递"
        case .split: "从中轴向两侧展开"
        case .duet: "左边短亮，右边缓缓应答"
        case .steps: "两枚亮点逐格折行，留下短尾"
        }
    }
}

struct CandidateBadge: View {
    let style: BadgeStyle
    let brand: ThreadCardHarnessBrand
    @Environment(\.threadCardProviderColor) private var ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let emoji = "🧭"

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            runningBadge(at: reduceMotion ? 0.8 : timeline.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: ThreadCardProviderStatus.diameter, height: ThreadCardProviderStatus.diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(brand.label + " · 运行中")
    }

    private var original: some View {
        ThreadCardProviderStatus(label: brand.label, brandKey: brand.brandKey, emoji: emoji)
    }

    private var glyph: some View { Text(emoji).font(.system(size: 21)).fixedSize() }

    @ViewBuilder private func runningBadge(at t: Double) -> some View {
        switch style {
        case .orbit:
            original.overlay {
                ZStack {
                    Circle().inset(by: 1).stroke(ink.opacity(0.14), lineWidth: 1)
                    Circle().inset(by: 1).trim(from: 0, to: 0.22)
                        .stroke(ink.opacity(0.85), style: .init(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 2.8) / 2.8 * 360))
                }
            }
        case .matrix:
            ThreadCardProviderStatus(label: brand.label, brandKey: brand.brandKey, emoji: emoji, running: true)
        case .titanium, .latitude, .split, .duet, .steps:
            ZStack {
                BadgeFinish(style: style, time: t)
                glyph
            }
        }
    }
}
