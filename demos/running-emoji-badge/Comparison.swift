import ChiefHarnessCodex
import ChiefPluginUI
import SwiftUI

@MainActor @Observable final class ComparisonState {
    var running = true
    var dots = true
}

struct Comparison: View {
    @Bindable var state: ComparisonState
    private let palette = NativePalette.overview
    private let size = NativeGeometry.overviewCard
    private let accent = CodexHarnessPlugin().themeColor ?? NativePalette.overview.provider.swiftUI
    private let identity = ThreadCardIdentityView(title: "梳理工作区导航",
        harness: .init(brandKey: "codex", label: "Codex", logoSource: ""), model: "GPT-6", effort: "High",
        runtime: .init(startedAt: 0, endedAt: 84_000),
        excerpt: "已整理侧栏中的常用入口。接下来核对键盘焦点和返回路径，再复查紧凑窗口下的布局。")
    private let presentation: ThreadCardPresentation = {
        let cell = ThreadCardSize(cols: 1, rows: 1)
        let projection = ThreadCardProjection.standard(identity: .init(usage: .init(parts: [
            .init(suffix: "tokens", id: "tokens", value: "12.8K", numericValue: 12_800)
        ])), extensions: [])
        return .init(projection: projection, composition: .slots(size: cell, identitySize: cell, slots: [],
                     key: "fixture"), size: cell, key: "fixture")
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("运行态徽章").font(.system(size: 23, weight: .semibold))
                    Text("Agent Thread  ·  320 × 196 pt  /  徽章 44 pt").font(.system(size: 12))
                        .foregroundStyle(palette.muted.swiftUI)
                }
                Spacer()
                Picker("候选组", selection: $state.dots) {
                    Text("点阵候选").tag(true)
                    Text("材质对照").tag(false)
                }
                .pickerStyle(.menu).labelsHidden().frame(width: 106)
                Picker("候选状态", selection: $state.running) {
                    Text("空闲").tag(false)
                    Text("运行中").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 144)
            }
            Grid(alignment: .leading, horizontalSpacing: NativeGeometry.overviewCardGap, verticalSpacing: 18) {
                GridRow {
                    sample(state.dots ? .matrix : .orbit)
                    sample(state.dots ? .split : .titanium)
                }
                GridRow {
                    sample(state.dots ? .duet : .latitude)
                    sample(state.dots ? .steps : .matrix)
                }
            }
        }
        .padding(24)
        .foregroundStyle(palette.ink.swiftUI)
        .background(palette.canvas.swiftUI)
        .environment(\.scenePhase, .active)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
    }

    private func sample(_ style: BadgeStyle) -> some View {
        let running = state.running
        let shell = RoundedRectangle(cornerRadius: NativeGeometry.overviewCardRadius)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(style.rawValue).font(.system(size: 14, weight: .semibold))
                Text(style.caption).font(.system(size: 11)).foregroundStyle(palette.muted.swiftUI)
            }
            .padding(.leading, 4)
            HarnessThreadCard(identity: identity, presentation: presentation,
                status: .init(kind: running ? .running : .idle, label: running ? "运行中" : "空闲"),
                providerStatus: AnyView(CandidateBadge(style: style, running: running)),
                harnessLogo: AnyView(CodexLogo(size: 12)))
                .environment(\.threadCardProviderColor, accent)
                .environment(\.threadCardCloudPalette, nil)
                .frame(width: size.width, height: size.height)
                .background(shell.fill(palette.surface.swiftUI))
                .overlay(shell.strokeBorder(palette.lineSoft.swiftUI, lineWidth: 1))
        }
    }
}
