import ChiefCore
import ChiefPluginAPI
import Foundation

/// Authored observations, materialized once at demo launch. No working tree or conversation is opened.
struct DemoThread {
    let input: HarnessThreadInput
    let execution: PublicExecution
    var thread: HarnessThread { input.thread }
    var reference: ApplicationExecutionRef {
        .init(thread: .init(threadID: thread.id, typeID: "agent"), executionID: execution.id)
    }

    init(_ sample: DemoSample, at time: Double) throws {
        let base = time - Double(sample.history.count) * 600_000 - 94_000
        let scope = JSONText("/Demo/" + sample.topic.folder)
        let git = sample.git.map { $0.observation(scope: scope, id: sample.id, at: time) }
        let exchanges = sample.history + [.init(sample.title, sample.prompt, sample.reply)]
        var executions: [PublicExecution] = []
        var turns: [JSONValue] = []
        var titles: [JSONText: JSONText] = [:]
        for (index, exchange) in exchanges.enumerated() {
            let latest = index == sample.history.count
            let start = base + Double(index) * 600_000
            let end = start + 94_000
            let running = latest && !sample.plan.isEmpty
            let execution = try PublicExecution(executionID: JSONText("run-\(sample.id)-\(index + 1)"),
                status: running ? .running : .completed, startedAt: start, finishedAt: running ? nil : end)
            titles[execution.id] = JSONText(exchange.title)
            executions.append(execution)
            turns.append(exchange.turn(execution: execution, start: start, end: end, plan: latest ? sample.plan : []))
        }
        // exchanges always includes the current request.
        execution = executions[exchanges.count - 1]
        let tag = JSONText(sample.topic.rawValue)
        let thread = try HarnessThread(id: JSONText(sample.id), harnessID: "codex", revision: 1,
            sessionState: .object(["schema": .text("mokusei.harness.codex.thread.v1"), "updatedAt": .number(time),
                                   "backgroundTerminals": .array([]), "turns": .array(turns)]),
            observation: .init(latestExecution: execution), cwd: git?.root ?? scope,
            settings: .object(["model": .text("GPT-5.4"), "thinking": .object(["mode": .text("effort"), "effort": .text("medium")])]),
            createdAt: base, updatedAt: time, title: JSONText(sample.title), tags: [tag],
            executionTitles: titles, metadataState: .object([
                "kind": .text("generated-thread-metadata"), "title": .text(sample.title), "emoji": .text(sample.emoji)]),
            tagEmojis: [tag: JSONText(sample.topic.emoji)], directoryTag: JSONText(sample.topic.folder), directoryScope: scope)
        input = .init(thread: thread, git: git)
    }
}

struct DemoExchange {
    let title: String
    let prompt: String
    let reply: String

    init(_ title: String, _ prompt: String, _ reply: String) {
        self.title = title
        self.prompt = prompt
        self.reply = reply
    }

    fileprivate func turn(execution: PublicExecution, start: Double, end: Double, plan: [String]) -> JSONValue {
        let message: JSONValue = .object(["id": .text("request"), "kind": .text("prompt"), "role": .text("user"),
            "content": .text(prompt), "createdAt": .number(start), "attachments": .array([])])
        // In each recorded plan the first item finished and the second is currently underway.
        let steps: [JSONValue] = plan.enumerated().map { index, label in
            .object(["step": .text(label), "status": .text(index == 0 ? "completed" : index == 1 ? "inProgress" : "pending")])
        }
        var turn: [JSONText: JSONValue] = ["executionId": .string(execution.id), "createdAt": .number(start),
            "updatedAt": .number(end), "status": .text(execution.status.rawValue), "answer": .text(reply),
            "messages": .array([message]), "timeline": .array([
                .object(["id": .text("prompt"), "kind": .text("user-message"), "messageId": .text("request"), "createdAt": .number(start)]),
                .object(["id": .text("reply"), "kind": .text("assistant"), "itemId": .text("answer"),
                         "content": .text(reply), "status": .text("complete"), "createdAt": .number(end)])]),
            "reasoning": .text(""), "plan": .array(steps), "activities": .array([]), "interactions": .array([]), "notices": .array([]),
            "author": .object(["model": .text("GPT-5.4"), "effort": .text("medium")])]
        if let finished = execution.finishedAt { turn["finishedAt"] = .number(finished) }
        return .object(turn)
    }
}

struct DemoGit {
    let branch: String
    let staged: Int
    let unstaged: Int
    let additions: Int
    let deletions: Int

    init(_ branch: String, staged: Int, unstaged: Int, additions: Int, deletions: Int) {
        self.branch = branch
        self.staged = staged
        self.unstaged = unstaged
        self.additions = additions
        self.deletions = deletions
    }

    fileprivate func observation(scope: JSONText, id: String, at time: Double) -> HarnessGitStatus {
        .init(id: JSONText(id + "-worktree"), root: JSONText(scope.string + "/" + id), branch: JSONText(branch),
              head: nil, upstream: nil, ahead: nil, behind: nil, changed: staged + unstaged, staged: staged,
              unstaged: unstaged, untracked: 0, conflicts: 0, additions: additions, deletions: deletions, observedAt: time)
    }
}

struct DemoSample {
    let id: String
    let topic: DemoTopic
    let emoji: String
    let title: String
    let prompt: String
    let reply: String
    let history: [DemoExchange]
    let plan: [String]
    let git: DemoGit?
    let report: DemoReportStory?

    init(_ id: String, _ topic: DemoTopic, _ emoji: String, _ title: String, _ prompt: String, _ reply: String,
         history: [DemoExchange] = [], plan: [String] = [], git: DemoGit? = nil, report: DemoReportStory? = nil) {
        self.id = id
        self.topic = topic
        self.emoji = emoji
        self.title = title
        self.prompt = prompt
        self.reply = reply
        self.history = history
        self.plan = plan
        self.git = git
        self.report = report
    }
}

enum DemoTopic: String {
    case address = "Address form", checks = "Release checks", payments = "Payments", receipts = "Receipts"
    case access = "Access", billing = "Billing", delivery = "Webhooks", exports = "Exports"
    case onboarding = "First week", languages = "Localization", editorial = "Release notes", support = "Help center"

    var folder: String {
        switch self {
        case .address, .checks, .payments, .receipts: "Checkout"
        case .access, .billing, .delivery, .exports: "API Platform"
        case .onboarding, .languages, .editorial, .support: "Launch Desk"
        }
    }

    var emoji: String {
        switch self {
        case .address: "📮"
        case .checks: "🧪"
        case .payments: "💳"
        case .receipts: "🧾"
        case .access: "🔑"
        case .billing: "🔔"
        case .delivery: "📨"
        case .exports: "📦"
        case .onboarding: "👋"
        case .languages: "🌐"
        case .editorial: "📰"
        case .support: "📚"
        }
    }
}
