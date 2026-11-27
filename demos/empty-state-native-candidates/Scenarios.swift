import Foundation
import ChiefPluginUI

let palette = NativePalette.overview

enum Candidate: String, CaseIterable {
    case current = "Current"
    case recent = "Recent threads"
}

enum EmptyScenario: String, CaseIterable, Identifiable {
    case running = "Running"
    case unread = "Unread"

    var id: Self { self }
    var title: String { self == .running ? "No running conversations" : "No unread conversations" }
    var recentTitle: String { self == .running ? "Recently completed" : "Recently read" }
    var railIcon: String { self == .running ? "hourglass" : "bookmark" }

    func recentThreads(in threads: [SampleThread]) -> [RecentThread] {
        let activity = threads.compactMap { thread in
            let date = self == .running ? thread.completedAt : thread.lastReadAt
            return date.map { RecentThread(thread: thread, date: $0) }
        }
        return Array(activity.sorted { $0.date > $1.date }.prefix(3))
    }
}

struct RecentThread: Identifiable {
    let thread: SampleThread
    let date: Date
    var id: SampleThread.ID { thread.id }
}

enum SampleHarness: String {
    case codex = "Codex"
    case claude = "Claude Code"
    case pi = "Pi Agent"
    case openCode = "OpenCode"
}

struct SampleThread: Identifiable {
    let id: String
    let title: String
    let harness: SampleHarness
    let request: String
    let reply: String
    let completedAt: Date?
    var lastReadAt: Date?

    var status: String { completedAt == nil ? "Idle" : "Completed" }

    static func samples(at now: Date) -> [Self] {
        // Completion and reading deliberately have different orderings.
        [
            .init(id: "invite", title: "Polish the Alpha invite copy", harness: .claude,
                request: "Review the first-run invite copy for Alpha testers.",
                reply: "The invite now gives the setup steps in order and says which permissions Chief asks for on first launch.",
                completedAt: now.addingTimeInterval(-190 * 60), lastReadAt: now.addingTimeInterval(-14 * 60)),
            .init(id: "keyboard", title: "Review keyboard navigation", harness: .codex,
                request: "Review keyboard navigation in Overview.",
                reply: "Return opens the selected conversation. Closing the reader currently moves focus to the first card. Restoring focus to the originating card is the remaining issue.",
                completedAt: now.addingTimeInterval(-24 * 60), lastReadAt: now.addingTimeInterval(-21 * 60)),
            .init(id: "feedback", title: "Summarize Alpha feedback", harness: .pi,
                request: "Group feedback from this week’s Alpha invites.",
                reply: "The most repeated requests were a clearer setup checklist and a faster way to find recently read work.",
                completedAt: now.addingTimeInterval(-4 * 3_600), lastReadAt: now.addingTimeInterval(-17 * 60)),
            .init(id: "filter", title: "Polish Overview filters", harness: .openCode,
                request: "Review how Overview represents the selected filter.",
                reply: "The selected filter stays open when it returns no cards. Its position and keyboard focus survive switching between Running and Unread.",
                completedAt: now.addingTimeInterval(-65 * 60), lastReadAt: now.addingTimeInterval(-8 * 60)),
            .init(id: "checklist", title: "Plan the next Alpha checklist", harness: .codex,
                request: "Prepare a checklist for the next invite wave.",
                reply: "The checklist is ready for a follow-up. No new run has been started.",
                completedAt: nil, lastReadAt: nil),
        ]
    }
}
