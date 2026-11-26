import ChiefHarnessCodex
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI

/// Cover the actual composer's outputs, including the narrow-column capability
/// used by other card hosts. Prefer the Git fixture for equal-size solutions.
struct CardSizeSample: Identifiable {
    let presentation: ThreadCardPresentation
    let inOverview: Bool
    var id: String { "\(presentation.size.cols)×\(presentation.size.rows)" }
    var points: CGSize {
        let cell = NativeGeometry.overviewCard, gap = NativeGeometry.overviewCardGap
        return CGSize(width: CGFloat(presentation.size.cols) * (cell.width + gap) - gap,
                      height: CGFloat(presentation.size.rows) * (cell.height + gap) - gap)
    }

    static let all: [Self] = {
        let git = HarnessGitStatus(id: "git", root: "/fixture", branch: nil, head: "cecbf805", upstream: nil,
            ahead: nil, behind: nil, changed: 4, staged: 0, unstaged: 4, untracked: 0, conflicts: 0, additions: 69, deletions: 0)
        let components: [ThreadCardExtensionProjection] = [
            .git(git), .todo(steps: [.init(step: "Map navigation keys", status: .completed),
                                     .init(step: "Verify keyboard focus", status: .inProgress)]),
            .derived(rows: [.init(id: "layout", label: "Check keyboard layout", status: .running, kind: .agent)])
        ]
        let permission = ThreadCardIntervention(id: "review", title: "Review keyboard shortcuts",
            actions: [.init(id: "approve", label: "Approve")])
        let question = ThreadCardIntervention(id: "layout", title: "Choose a keyboard layout", actions: [],
            questions: [.init(id: "keyboard", prompt: "Which layout should we verify?", options: [
                .init(id: "us", label: "US", value: "us"), .init(id: "iso", label: "ISO", value: "iso")])])
        let identity = ThreadCardIdentityProjection(usage: .init(parts: [
            .init(suffix: "tokens", id: "tokens", value: "115.7K", numericValue: 115_700)]))
        var combinations: [[ThreadCardExtensionProjection]] = [[]]
        for component in components {
            combinations += combinations.map { $0 + [component] }
        }
        let prompted = combinations.flatMap { choices in
            [permission, question].map { choices + [.intervention($0)] }
        }
        let fixtures = (combinations + prompted).sorted { $0.count < $1.count }
        var samples = [ThreadCardSize: Self]()
        for columns in (1...HarnessOverviewCapacity.maximumColumns).reversed() {
            for extensions in fixtures {
                let card = try! composeThreadCard(.standard(identity: identity, extensions: extensions),
                                                  layoutContext: .init(availableCols: columns))
                if samples[card.size] == nil {
                    samples[card.size] = Self(presentation: card, inOverview: columns == HarnessOverviewCapacity.maximumColumns)
                }
            }
        }
        return samples.values.sorted {
            let a = $0.presentation.size, b = $1.presentation.size
            return ($0.inOverview ? 0 : 1, a.rows * a.cols, a.rows) < ($1.inOverview ? 0 : 1, b.rows * b.cols, b.rows)
        }
    }()
}

struct CardSizePreview: View {
    let sample: CardSizeSample
    let actualSize: Bool
    let status: ThreadCardStatusKind
    let still: Bool
    private let palette = NativePalette.overview
    private let plugin = CodexHarnessPlugin()

    var body: some View {
        GeometryReader { proxy in
            let size = sample.points
            let zoom = actualSize ? 1 : min(1, (proxy.size.width - 20) / size.width, (proxy.size.height - 20) / size.height)
            ScrollView([.horizontal, .vertical]) {
                card.frame(width: size.width, height: size.height)
                    .scaleEffect(zoom)
                    .frame(width: size.width * zoom, height: size.height * zoom)
                    .padding(10)
                    .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
        }
        .transformEnvironment(\._accessibilityReduceMotion) { if still { $0 = true } }
    }

    private var card: some View {
        let brand = ThreadCardHarnessBrand(brandKey: plugin.descriptor.id.string, label: plugin.descriptor.displayName.string,
                                          logoSource: plugin.logoSource)
        let identity = ThreadCardIdentityView(title: "添加 Tag Space 左右切换快捷键", harness: brand, model: "gpt-6.2-sol",
            effort: "high", runtime: .init(startedAt: 0, endedAt: 266_000),
            excerpt: "Testing keyboard layout handling\n\nVerifying filter and focus behavior.")
        let shell = RoundedRectangle(cornerRadius: NativeGeometry.overviewCardRadius)
        let state = ThreadCardStatusProjection(kind: status, label: status == .running ? "运行中" : status == .idle ? "空闲" : "完成",
                                              terminal: status == .completed ? .completed : nil)
        return HarnessThreadCard(identity: identity, presentation: sample.presentation, status: state,
                                 emoji: "⌨️", harnessLogo: AnyView(plugin.logo(size: 12)))
            .clipShape(shell)
            .background(shell.fill(palette.surface.swiftUI))
            .overlay(shell.strokeBorder(palette.lineSoft.swiftUI, lineWidth: 1))
            .threadCardRunningEdge()
            .environment(\.threadCardProviderColor, plugin.themeColor ?? palette.provider.swiftUI)
    }
}
