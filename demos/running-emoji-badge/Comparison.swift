import ChiefHarnessClaude
import ChiefHarnessCodex
import ChiefHarnessOpenCode
import ChiefHarnessPi
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI

enum PreviewHarness: CaseIterable {
    case codex, claude, pi, openCode

    @MainActor var plugin: any HarnessPlugin {
        switch self {
        case .codex: CodexHarnessPlugin()
        case .claude: ClaudeHarnessPlugin()
        case .pi: PiHarnessPlugin()
        case .openCode: OpenCodeHarnessPlugin()
        }
    }
}

enum ComparisonGroup: String, CaseIterable {
    case colors = "Harness 配色"
    case dots = "点阵候选"
    case materials = "材质对照"
}

@MainActor @Observable final class ComparisonState {
    var running = true
    var group = ComparisonGroup.colors
    var harness = PreviewHarness.codex
    var pattern = BadgeStyle.matrix
}

struct Comparison: View {
    @Bindable var state: ComparisonState
    private let palette = NativePalette.overview
    private let size = NativeGeometry.overviewCard
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
                Picker("候选组", selection: $state.group) {
                    ForEach(ComparisonGroup.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().frame(width: 118)
                if state.group == .colors {
                    Picker("点阵动效", selection: $state.pattern) {
                        ForEach([BadgeStyle.matrix, .split, .duet, .steps], id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu).labelsHidden().frame(width: 104)
                } else {
                    Picker("Harness", selection: $state.harness) {
                        ForEach(PreviewHarness.allCases, id: \.self) { Text($0.plugin.descriptor.displayName.string).tag($0) }
                    }.pickerStyle(.menu).labelsHidden().frame(width: 104)
                }
                Picker("候选状态", selection: $state.running) {
                    Text("空闲").tag(false)
                    Text("运行中").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 144)
            }
            Grid(alignment: .leading, horizontalSpacing: NativeGeometry.overviewCardGap, verticalSpacing: 18) {
                if state.group == .colors {
                    GridRow { sample(state.pattern, .codex); sample(state.pattern, .claude) }
                    GridRow { sample(state.pattern, .pi); sample(state.pattern, .openCode) }
                } else {
                    GridRow {
                        sample(state.group == .dots ? .matrix : .orbit, state.harness)
                        sample(state.group == .dots ? .split : .titanium, state.harness)
                    }
                    GridRow {
                        sample(state.group == .dots ? .duet : .latitude, state.harness)
                        sample(state.group == .dots ? .steps : .matrix, state.harness)
                    }
                }
            }
        }
        .padding(24)
        .foregroundStyle(palette.ink.swiftUI)
        .background(palette.canvas.swiftUI)
        .environment(\.scenePhase, .active)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
    }

    private func sample(_ style: BadgeStyle, _ harness: PreviewHarness) -> some View {
        let plugin = harness.plugin
        let name = plugin.descriptor.displayName.string
        let brand = ThreadCardHarnessBrand(brandKey: plugin.descriptor.id.string, label: name, logoSource: plugin.logoSource)
        let identity = ThreadCardIdentityView(title: "梳理工作区导航", harness: brand,
            model: harness == .claude ? "Claude Sonnet" : "GPT-6", effort: "High",
            runtime: .init(startedAt: 0, endedAt: 84_000),
            excerpt: "已整理侧栏中的常用入口。接下来核对键盘焦点和返回路径，再复查紧凑窗口下的布局。")
        let running = state.running
        let shell = RoundedRectangle(cornerRadius: NativeGeometry.overviewCardRadius)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(state.group == .colors ? name : style.rawValue).font(.system(size: 14, weight: .semibold))
                Text(state.group == .colors ? style.rawValue : style.caption).font(.system(size: 11)).foregroundStyle(palette.muted.swiftUI)
            }
            .padding(.leading, 4)
            HarnessThreadCard(identity: identity, presentation: presentation,
                status: .init(kind: running ? .running : .idle, label: running ? "运行中" : "空闲"),
                providerStatus: AnyView(CandidateBadge(style: style, running: running, brand: brand)),
                harnessLogo: AnyView(plugin.logo(size: 12)))
                .environment(\.threadCardProviderColor, plugin.themeColor ?? palette.provider.swiftUI)
                .environment(\.threadCardCloudPalette, nil)
                .frame(width: size.width, height: size.height)
                .background(shell.fill(palette.surface.swiftUI))
                .overlay(shell.strokeBorder(palette.lineSoft.swiftUI, lineWidth: 1))
        }
    }
}
