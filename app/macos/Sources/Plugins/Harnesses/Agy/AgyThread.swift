import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI

struct AgyThread: View {
    let input: HarnessThreadInput
    let actions: HarnessThreadActions
    let context: HarnessRenderContext

    var body: some View {
        let turns = input.thread.sessionState["turns"]?.arrayValue ?? []
        let latest = input.thread.observation.latestExecution
        if case .row(let id) = context.content, let turn = turns.first(where: { $0["executionId"] == .string(id) }) {
            AgyTurn(turn: turn, input: input, actions: actions, context: context)
        } else {
            let rows = turns.compactMap { turn -> ThreadConversationRow? in
                guard case let .string(id) = turn["executionId"], let start = turn["startedAt"]?.numberValue else { return nil }
                let status = turn["status"]?.stringValue
                return .init(id: id, createdAt: start, execution: .init(id: id, title: input.thread.executionTitles[id]?.string,
                    prompt: turn["prompt"]?.stringValue ?? "", answer: turn["summary"]?.stringValue ?? "",
                    completedAt: status == "completed" ? turn["finishedAt"]?.numberValue : nil,
                    isActive: status == "running" || status == "waiting-for-user"),
                    node: AnyView(AgyTurn(turn: turn, input: input, actions: actions, context: context)))
            }
            ThreadConversation(threadId: input.thread.id, title: input.thread.title.string, rows: rows,
                readingTarget: input.readingTarget.map { .init(requestId: $0.requestID, mode: $0.mode == .current ? .current : .history,
                    executionId: $0.executionID, position: $0.position,
                    follow: input.thread.observation.isExecutionActive && latest?.executionID == $0.executionID, hasMessageTarget: $0.message != nil) },
                running: latest?.status == .running, runningTurnId: input.thread.observation.isExecutionActive ? latest?.executionID : nil,
                activeExecutionId: input.thread.observation.isExecutionActive ? latest?.executionID : nil,
                context: context, renderRow: context.content == .manifest ? { id in
                    AnyView(AgyScopedTurn(id: id, input: input, actions: actions, context: context))
                } : nil)
        }
    }
}

private struct AgyScopedTurn: View {
    let id: JSONText
    let input: HarnessThreadInput
    let actions: HarnessThreadActions
    let context: HarnessRenderContext
    @State private var resource: HarnessContentResource?
    var body: some View {
        Group {
            switch resource?.state {
            case .ready(let raw):
                if let turn = raw["turns"]?.arrayValue?.first(where: { $0["executionId"] == .string(id) }) {
                    AgyTurn(turn: turn, input: input, actions: actions, context: context)
                }
            case .error(let message): ThreadTranscriptFailure(message: message, retry: { try await resource?.retry() })
            default: NativeThreadLoadingIndicator()
            }
        }.task(id: id) { resource = context.contentResource(.row(id)) }.onDisappear {
            let old = resource
            old?.beginRelease()
            resource = nil
            Task { await old?.release() }
        }
    }
}

private struct AgyTurn: View {
    let turn: JSONValue
    let input: HarnessThreadInput
    let actions: HarnessThreadActions
    let context: HarnessRenderContext
    @Environment(\.threadAgentDetail) private var agentDetail
    @Environment(\.threadDetailVisibility) private var visibility
    @Environment(\.locale) private var locale
    @State private var failure: String?
    @State private var responding = false

    func transcript(_ id: JSONText, status: PublicExecution.Status) -> [ThreadTranscriptItem] {
        let userRowID = JSONText(turn["userRowId"]?.stringValue ?? id.string + "-user")
        var items: [ThreadTranscriptItem] = [.init(userRowID,
            .user(.init(turn["prompt"]?.stringValue ?? "", followUp: false, createdAt: turn["startedAt"]?.numberValue)))]
        let blocks = turn["blocks"]?.arrayValue ?? []
        for (index, block) in blocks.enumerated() {
            let anchor = JSONText("\(id.string)-\(index)")
            let text = block["text"]?.stringValue ?? ""
            switch block["kind"]?.stringValue {
            case "assistant":
                let phase: ThreadTranscriptPhase = status == .running && index == blocks.indices.last ? .streaming :
                    status == .failed && index == blocks.indices.last ? .failed : .settled
                items.append(.init(anchor, .reply(text, phase: phase, anchor: anchor)))
            case "reasoning": items.append(.init(anchor, .reasoning(text, hasContent: !text.isEmpty)))
            case "tool":
                let tool = ThreadTranscriptActivity(id: anchor, label: text, status: block["status"]?.stringValue ?? "running",
                    detail: block["detail"]?.stringValue)
                items.append(.init(anchor, .activity(tool)))
            default: break
            }
        }
        if let error = turn["error"]?.stringValue {
            items.append(.init(JSONText(id.string + "-error"), .error(error)))
        }
        return items
    }

    var body: some View {
        let id = JSONText(turn["executionId"]?.stringValue ?? "")
        let status = PublicExecution.Status(rawValue: turn["status"]?.stringValue ?? "") ?? .failed
        let latest = input.thread.observation.latestExecution
        let waiting = latest?.executionID == id && status == .waitingForUser
        let active = latest?.executionID == id && (status == .running || waiting)
        let pending = waiting ? latest?.interactions ?? [] : []
        let items = transcript(id, status: status) + pending.map { .init($0.id, .request($0.id)) }
        let layout = ThreadTranscriptLayout(items, agentDetail: agentDetail, active: active,
            waiting: waiting, completed: status == .completed, target: visibility.messageAnchorID)
        let rows = layout.detailRows(executionID: id,
            workVisible: visibility.work && (visibility.workTurnID == nil || visibility.workTurnID == id),
            active: active && status == .running, actions: actions, context: context) { key in
            pending.first(where: { $0.id == key }).map { AnyView(permission($0)) }
        }
        let start = turn["startedAt"]?.numberValue ?? 0
        let end = turn["finishedAt"]?.numberValue
        VStack(alignment: .leading, spacing: 8) {
            if let failure { ThreadTranscriptFailure(message: failure) }
            ThreadDetailTurn(id: id, author: turn["model"].map { .object(["model": $0]) }, rows: rows,
                createdAt: start, updatedAt: end ?? start,
                status: NativePluginLocalization.localize(threadExecutionStatus(status), locale: locale),
                completedAt: status == .completed ? end : nil, active: active, executionRunning: active && status == .running,
                executionTailIsWork: layout.tailIsWork, workAvailable: layout.hasWork())
                .nativeReadingExecutionReady(id, settled: end != nil)
        }
    }

    private func permission(_ request: PublicInteraction) -> some View {
        ThreadDetailRequest {
            VStack(alignment: .leading) {
                ThreadRequestHeader(request.title.string, description: request.description?.string, question: false)
                ThreadRequestActions {
                    ForEach(request.actions, id: \.id) { action in
                        Button(action.label.string) {
                            responding = true
                            Task {
                                defer { responding = false }
                                do { try await actions.respond(.init(interactionID: request.id, actionID: action.id)); failure = nil }
                                catch { failure = error.localizedDescription }
                            }
                        }.disabled(responding).buttonStyle(ThreadRequestButtonStyle())
                    }
                }
            }
        }
    }
}
