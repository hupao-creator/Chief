import AppKit
import ChiefComposition
import ChiefCore
import ChiefPluginAPI
@testable import ChiefPluginUI
@testable import ChiefHarnessClaude
@testable import ChiefHarnessCodex
@testable import ChiefHarnessOpenCode
@testable import ChiefHarnessPi
import SwiftUI

private struct Mismatch: Error, CustomStringConvertible {
    var description: String
    init(_ message: String) { description = message }
}

private let final = "# Result\n\nUse **café**."
private let stages = ["stream", "reply", "waiting", "done", "reopen", "failed", "retained"]

private func inspect(_ id: String, _ raw: JSONValue, _ presence: ThreadExecutionPresence) throws -> ([ThreadTranscriptItem], String) {
    switch id {
    case "codex":
        let turn = try CodexState(raw).turns[0]
        return (turn.transcript(presence: presence), turn.answer)
    case "claude":
        let turn = try ClaudeState(raw).turns[0]
        return (turn.transcript(presence: presence), turn.readerAnswer)
    case "pi":
        let state = try PiState(raw)
        let execution = state.executions[0]
        return (piTranscript(state.messages, execution: execution, presence: presence),
                state.messages.last { $0.isReaderReply(execution.status) }?.text.string ?? "")
    case "opencode":
        let state = try OpenCodeState(raw)
        return (ocTranscript(state.messages, sessionID: state.nativeSessionID, execution: state.executions.first, presence: presence),
                state.messages.last { $0.isReaderReply && ($0.nativeSessionID == nil || $0.nativeSessionID == state.nativeSessionID) }?.text ?? "")
    default: throw Mismatch("Unsupported sample \(id)")
    }
}

private func checkRows(_ items: [ThreadTranscriptItem], stage: String, deferred: Bool) throws {
    let live = ["stream", "reply", "waiting"].contains(stage)
    let layout = ThreadTranscriptLayout(items, agentDetail: true, active: live)
    var sequence: [String] = []
    for row in layout.rows {
        switch row.item.body {
        case let .user(message):
            guard row.kind == .steer, message.followUp else { throw Mismatch("Unexpected user input") }
            sequence.append(message.text)
        case let .reply(text, _, _):
            sequence.append(row.kind.rawValue + " " + text)
        case let .reasoning(text, _):
            guard row.summary?.reasoningSegments == 1, row.kind == .work, deferred || text == "check once" else {
                throw Mismatch("Missing reasoning body or summary: \(text)")
            }
            sequence.append("reasoning")
        case let .activity(tool):
            guard tool.label.contains("inspect"), tool.status == "failed", tool.countsAsTool, row.kind == .work,
                  deferred || tool.detail?.contains("tool diagnostic") == true else { throw Mismatch("Tool result \(tool)") }
            sequence.append("tool")
        case .request where stage == "waiting": break
        case let .error(text):
            guard row.kind == .attention, text == "independent failure" else { throw Mismatch("Unexpected error \(text)") }
            sequence.append("error")
        default: throw Mismatch("Unexpected occurrence \(row.item.id)")
        }
    }
    var expected = [(live ? "content" : "work") + " First note", "Retry once", "reasoning", "tool"]
    if stage != "stream" { expected.append("content " + final) }
    if stage == "failed" { expected.append("error") }
    guard sequence == expected, layout.hasWork() else { throw Mismatch("Expected \(expected), got \(sequence)") }
    let full = ThreadTranscriptLayout(items, agentDetail: false)
    guard full.rows.contains(where: { if case let .user(i) = $0.item.body { return i.text == "Initial instruction" }; return false }) else {
        throw Mismatch("Initial prompt missing from complete conversation")
    }
    if !live, let first = items.first(where: { if case let .reply(s, _, _) = $0.body { return s == "First note" }; return false }),
       case let .reply(_, _, anchor) = first.body {
        let visit = ThreadTranscriptLayout(items, agentDetail: true, target: anchor)
        guard visit.rows.filter({ $0.kind == .content }).count == 2 else { throw Mismatch("Earlier reply visit lost") }
    }
}

private func checkRetained(_ id: String, _ items: [ThreadTranscriptItem], sample: JSONValue) throws {
    let layout = ThreadTranscriptLayout(items, agentDetail: true)
    let answers = layout.rows.compactMap { row -> String? in
        guard row.kind == .content, case let .reply(text, _, _) = row.item.body else { return nil }
        return text
    }
    guard answers == ["Saved **answer**."] else { throw Mismatch("Retained result \(answers)") }
    let diagnostics = layout.rows.compactMap { row -> String? in
        guard row.kind == .attention, case let .error(text) = row.item.body else { return nil }
        return text
    }
    let count = id == "codex" ? 2 : id == "pi" ? 1 : 0
    guard diagnostics == Array(repeating: "saved diagnostic", count: count) else { throw Mismatch("Retained diagnostics \(diagnostics)") }
    switch id {
    case "pi":
        let complete = ThreadTranscriptLayout(items, agentDetail: false)
        guard complete.rows.contains(where: { if case .notice("extension status") = $0.item.body { return true }; return false }),
              !layout.rows.contains(where: { $0.summary?.toolCalls == 1 }) else { throw Mismatch("Extension notification counted as a tool") }
    case "opencode":
        guard let child = items.first(where: { $0.delegated }), case let .reply(_, _, anchor) = child.body else { throw Mismatch("Missing child") }
        let visit = ThreadTranscriptLayout(items, agentDetail: true, target: anchor)
        let parts = visit.rows.compactMap { row -> String? in
            guard row.kind == .content, row.item.delegated, case let .reply(text, _, _) = row.item.body else { return nil }
            return text
        }
        guard parts == ["Delegated ", "answer"], layout.hasWork() else { throw Mismatch("Missing child parts: \(parts)") }
    case "claude":
        let history = try ClaudeState(sample["fork"]!).history
        let inherited = ThreadTranscriptLayout(claudeTranscript(history, presence: .init()), agentDetail: false, inheritedTurns: true)
        guard inherited.rows.map(\.kind) == [.user, .work, .content],
              case let .activity(tool) = inherited.rows[1].item.body, tool.detail == "saved output" else { throw Mismatch("Incomplete inherited history") }
    default: break
    }
}

@MainActor private func textViews(_ view: NSView) -> [NSTextView] {
    if let text = view as? NSTextView { return [text] }
    return view.subviews.flatMap(textViews)
}

@MainActor private func mount(_ plugin: AnyHarnessPlugin, sample: JSONValue, id: String, stage: String) async throws -> [String] {
    let observation = try ThreadPublicObservation(json: sample["observation"]!)
    let key = JSONText(sample["rowKey"]!.stringValue!)
    let thread = try HarnessThread(id: "offline", harnessID: JSONText(id), revision: 1,
        sessionState: sample["execution"]!, observation: observation, cwd: "/tmp", settings: .object([:]),
        createdAt: 1, updatedAt: 2, title: "Offline replay", tags: [])
    let actions = HarnessThreadActions(interrupt: { fatalError() }, respond: { _ in fatalError() },
        invokeHarnessExtension: { _, _ in fatalError() }, forkThread: { _ in fatalError() },
        openExternal: { _ in fatalError() }, openFollowUp: { _ in fatalError() })
    let context = HarnessRenderContext(content: .row(key), presentation: .execution("run"),
                                      contentResource: { _ in fatalError() }, onIndexChange: { _ in })
    let content = try plugin.threadView(input: .init(thread: thread), actions: actions, context: context)
    let registry = NativeReadingInteractions()
    let visit = UUID()
    let host = NSHostingView(rootView: content.environment(\.nativeReadingInteractions, registry)
        .environment(\.nativeReadingInteractionVisit, visit).environment(\.locale, Locale(identifier: "en")).frame(width: 690, height: 700))
    let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 690, height: 700),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.alphaValue = 0
    window.orderBack(nil)
    defer { window.orderOut(nil); window.contentView = nil }
    let live = ["stream", "reply", "waiting"].contains(stage)
    var seen = [String]()
    var visibleRows: Int?
    for _ in 0..<80 {
        try await Task.sleep(for: .milliseconds(25))
        host.layoutSubtreeIfNeeded()
        let views = textViews(host)
        seen = views.map(\.string)
        let body = seen.joined(separator: "\n")
        let finalShown = body.contains("Result") && body.contains("Use café.")
        if stage == "retained", seen == ["Saved answer."] { return seen }
        if stage == "parts", seen == [id == "pi" ? "Body 🌲" : "Body 🌲 updated", "Tail"] { return seen }
        if stage != "retained", stage != "parts", body.contains("First note") == live, finalShown == (stage != "stream"),
           !body.contains("# Res"), !body.contains("**"), !body.contains("Initial instruction") {
            if stage == "failed" || stage == "waiting" {
                visibleRows = registry.snapshot(visit: visit).first { $0["role"] == .text("turn") }?["value"]?["visibleRowCount"]?.intValue
                guard visibleRows == (stage == "failed" ? 2 : 3) else { continue }
            }
            return seen
        }
    }
    throw Mismatch("Mounted text \(seen), visible rows \(String(describing: visibleRows))")
}

@main struct Replay {
    @MainActor static func main() async {
        do {
            try prepareIsolatedNativeReplay()
            NSApplication.shared.setActivationPolicy(.prohibited)
            let directory = URL(fileURLWithPath: CommandLine.arguments[1])
            let registry = try NativePlugins.make().harnesses
            var results: [[String: Any]] = []
            for id in ["codex", "claude", "pi", "opencode"] {
                let plugin = try registry.require(JSONText(id))
                for stage in stages + (["pi", "claude"].contains(id) ? ["parts"] : []) {
                    do {
                        let sample = try JSONValue(data: Data(contentsOf: directory.appendingPathComponent("\(id)-\(stage).json")))
                        let preview = try inspect(id, sample["thread"]!, .init()).1
                        let expectedPreview = ["retained": "Saved **answer**.", "parts": id == "pi" ? "Body 🌲\nTail" : "Body 🌲 updatedTail", "stream": "First note"][stage] ?? final
                        guard preview == expectedPreview else { throw Mismatch("Directory reply \(preview)") }
                        for scope in ["execution", "turn"] {
                            let resource = sample[scope]!
                            let presence = try ThreadExecutionPresence(resource["nonempty"]?.arrayValue ?? [])
                            let items = try inspect(id, resource["state"] ?? resource, presence).0
                            if stage == "parts", id == "claude" {
                                let rows = ThreadTranscriptLayout(items, agentDetail: true).rows
                                guard rows.map(\.kind) == [.content, .work, .content, .content],
                                      case .review("settled review") = rows[2].item.body,
                                      case let .reasoning(text, present) = rows[1].item.body, present,
                                      resource["state"] != nil || text == "two" else { throw Mismatch("Misplaced corrected Claude block") }
                            } else if stage == "parts" {
                                let rows = ThreadTranscriptLayout(items, agentDetail: true).rows
                                guard rows.map(\.kind) == [.content, .work, .work, .content],
                                      case let .activity(tool) = rows[2].item.body, tool.kind == "command", tool.status == "completed",
                                      resource["state"] != nil || (tool.input?.contains("pwd") == true && tool.detail == "workspace")
                                else { throw Mismatch("Lost interleaved Pi call or output") }
                            } else if stage == "retained" { try checkRetained(id, items, sample: sample) }
                            else { try checkRows(items, stage: stage, deferred: resource["kind"] == .text("deferred-execution")) }
                        }
                        let mounted = try await mount(plugin, sample: sample, id: id, stage: stage)
                        results.append(["harness": id, "stage": stage, "markdown": mounted, "directory": preview])
                    } catch { throw Mismatch("\(id)/\(stage): \(error)") }
                }
            }
            try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }
}
