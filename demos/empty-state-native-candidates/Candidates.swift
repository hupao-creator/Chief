import ChiefCore
import ChiefHarnessClaude
import ChiefHarnessCodex
import ChiefHarnessOpenCode
import ChiefHarnessPi
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI
@testable import ChiefUI

struct StatusWithRecentThreads<Status: View>: View {
    let status: Status
    let scenario: EmptyScenario
    let threads: [RecentThread]
    let open: (SampleThread) -> Void

    var body: some View {
        if threads.isEmpty {
            status
        } else {
            VStack(spacing: 0) {
                status.frame(height: NativeOverviewStatusEmptyState.markHeight)
                NativeOverviewRecentThreadList(title: scenario.recentTitle,
                    threads: threads.map { activity in
                        .init(id: JSONText(activity.id), title: activity.thread.title,
                              harness: activity.thread.harness.plugin, date: activity.date)
                    }, usesTintedGlass: scenario == .unread) { id in
                        if let activity = threads.first(where: { JSONText($0.id) == id }) { open(activity.thread) }
                    }
                    .frame(width: NativeOverviewRecentThreadList.idealWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ThreadRow: View {
    let thread: SampleThread
    let open: () -> Void

    var body: some View {
        NativeOverviewRecentThreadRow(title: thread.title, harness: thread.harness.plugin,
                                      metadata: thread.status, open: open)
    }
}

@MainActor
private extension SampleHarness {
    var plugin: AnyHarnessPlugin {
        switch self {
        case .codex: AnyHarnessPlugin(CodexHarnessPlugin())
        case .claude: AnyHarnessPlugin(ClaudeHarnessPlugin())
        case .pi: AnyHarnessPlugin(PiHarnessPlugin())
        case .openCode: AnyHarnessPlugin(OpenCodeHarnessPlugin())
        }
    }
}

struct SampleConversationBody: View {
    let thread: SampleThread

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(thread.request).font(NativeTypography.inter(size: 14, weight: 560))
            Divider()
            Text(thread.status)
                .font(.caption)
                .foregroundStyle(palette.provider.swiftUI)
            Text(thread.reply).font(NativeTypography.inter(size: 14))
                .textSelection(.enabled)
        }
    }
}
