import Foundation
import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI

public struct ClaudeThreadView: View {
    @Environment(\.threadAgentDetail) private var agentDetail
    @Environment(\.threadExecutionPresence) private var presence
    let input: HarnessThreadInput
    let actions: HarnessThreadActions
    let context: HarnessRenderContext
    @Environment(\.locale) private var locale
    private var providedState: ClaudeState?
    @State private var stateCache = HarnessReadingState<ClaudeState>(decode: decodeClaudeReadingState)
    @State private var resolvedAnchor: (request: JSONText, anchor: JSONText)?
    public init(input: HarnessThreadInput, actions: HarnessThreadActions, context: HarnessRenderContext) {
        self.input = input; self.actions = actions; self.context = context; providedState = nil
    }
    init(input: HarnessThreadInput, actions: HarnessThreadActions, context: HarnessRenderContext, state: ClaudeState) {
        self.input = input; self.actions = actions; self.context = context; providedState = state
    }
    public var body: some View {
        Group {
            if let providedState {
                if case .row(let id) = context.content { row(id, state: providedState) }
                else { conversation(providedState) }
            } else if let (preparedInput, result, _) = stateCache.snapshot(input: input) {
                switch result {
                case .success(let state):
                    ClaudeThreadView(input: preparedInput, actions: actions, context: context, state: state)
                case .failure(let error):
                    let failure = claudeFailurePresentation(preparedInput, decodeError: error)
                    ThreadTranscriptFailure(message: failure.message, detail: failure.detail)
                }
            } else { NativeThreadLoadingIndicator() }
        }.task(id: HarnessReadingRequest(input: input, raw: input.thread.sessionState)) {
            if providedState == nil { await stateCache.load(input: input, raw: input.thread.sessionState) }
        }
    }
    private func conversation(_ state: ClaudeState) -> some View {
        var rows: [ThreadConversationRow] = []
        if !state.history.isEmpty { rows.append(ThreadConversationRow(id: "fork-history", createdAt: 0, history: true, node: AnyView(row("fork-history", state: state)))) }
        rows += state.turns.map { turn in
            ThreadConversationRow(id: turn.id, createdAt: turn.createdAt,
                execution: ThreadConversationExecution(id: turn.id, title: input.thread.executionTitles[turn.id]?.string, prompt: turn.visiblePrompts.first?.stringValue ?? "", answer: turn.readerAnswer, completedAt: turn.status == "completed" ? turn.finishedAt : nil, isActive: turn.status == "running"),
                node: AnyView(row(turn.id, state: state)))
        }
        if !state.tasks.isEmpty { rows.append(ThreadConversationRow(id: "native-background-tasks", createdAt: input.thread.updatedAt, node: AnyView(backgroundTasks(state.tasks)))) }
        let anchor = claudeReplyAnchor(state, message: input.readingTarget?.message) ?? (resolvedAnchor?.request == input.readingTarget?.requestID ? resolvedAnchor?.anchor : nil)
        return ThreadConversation(threadId: input.thread.id, title: agentDetail ? input.thread.title.string : claudeDocumentTitle(input.thread, state: state), icon: claudeEmoji(input.thread), rows: rows,
            readingTarget: input.readingTarget.map { ThreadConversationReadingTarget(requestId: $0.requestID, mode: $0.mode == .current ? .current : .history, executionId: $0.executionID, anchorId: anchor, position: $0.position,
                follow: input.thread.observation.isExecutionActive && input.thread.observation.latestExecution?.executionID == $0.executionID, hasMessageTarget: $0.message != nil) },
            running: input.thread.observation.latestExecution?.status == .running,
            runningTurnId: runningID(state),
            activeExecutionId: input.thread.observation.isExecutionActive ? input.thread.observation.latestExecution?.executionID : nil,
            context: context,
            renderRow: context.content == .manifest ? { key in
                if key == "native-background-tasks" { return AnyView(backgroundTasks(state.tasks)) }
                return AnyView(ClaudeLazyRow(key: key, input: input, actions: actions, context: context, onAnchor: { request, anchor in resolvedAnchor = (request, anchor) }))
            } : nil)
    }
    @ViewBuilder private func row(_ key: JSONText, state: ClaudeState) -> some View {
        if key == "fork-history" {
            if case .main = context.presentation { ThreadTranscriptHistory(id: key, items: claudeTranscript(state.history, presence: presence), createdAt: input.thread.createdAt, actions: actions, context: context) }
        } else if let turn = state.turns.first(where: { $0.id == key }), claudeVisible(key, context: context) {
            ClaudeTurnView(turn: turn, active: runningID(state) == key,
                waiting: input.thread.observation.latestExecution?.executionID == key && input.thread.observation.latestExecution?.status == .waitingForUser,
                publicInteractions: claudePublicInteractions(state, input.thread.observation), actions: actions, context: context)
        } else { ThreadTranscriptFailure(message: NativePluginLocalization.localize("历史执行不可用", locale: locale)) }
    }
    private func backgroundTasks(_ tasks: [JSONValue]) -> some View {
        ThreadBackgroundWork(id: "native-background-tasks", title: "后台任务", items: tasks.map {
            .init(id: $0.claudeID("id"), label: $0["description"]?.stringValue ?? "",
                  detail: $0["type"]?.stringValue, status: $0["status"]?.stringValue ?? "")
        })
    }

    private func runningID(_ state: ClaudeState) -> JSONText? {
        guard let execution = input.thread.observation.latestExecution, execution.status == .running else { return nil }
        return state.turns.last(where: { $0.id == execution.executionID && $0.status == "running" })?.id
    }
}
private struct ClaudeLazyRow: View {
    let key: JSONText
    let input: HarnessThreadInput
    let actions: HarnessThreadActions
    let context: HarnessRenderContext
    let onAnchor: (JSONText, JSONText) -> Void
    @State private var resource: HarnessContentResource?
    var body: some View {
        Group {
            if let resource {
                switch resource.state {
                case .loading: NativeThreadLoadingIndicator()
                case .error(let message): ThreadTranscriptFailure(message: claudeRedacted(message), retry: { try await resource.retry() })
                case .ready(let raw):
                    ThreadDeferredExecutionContent(raw: raw, rowKey: key, context: context) { value in
                        ClaudeLoadedRow(key: key, input: input, actions: actions, context: context, onAnchor: onAnchor, raw: value)
                    }
                }
            } else { NativeThreadLoadingIndicator() }
        }.task(id: key) { resource = context.contentResource(.row(key)) }
            .onDisappear { let old = resource; old?.beginRelease(); resource = nil; Task { await old?.release() } }
    }
}

private struct ClaudeLoadedRow: View {
    let key: JSONText
    let input: HarnessThreadInput
    let actions: HarnessThreadActions
    let context: HarnessRenderContext
    let onAnchor: (JSONText, JSONText) -> Void
    let raw: JSONValue
    @State private var stateCache = HarnessReadingState<ClaudeState>(decode: decodeClaudeReadingState)
    @Environment(\.threadExecutionPresence) private var presence
    @Environment(\.threadExecutionLoader) private var loader
    private var readingEnvironment: HarnessReadingEnvironment { .init(presence: presence, loader: loader) }
    @ViewBuilder var body: some View {
        Group {
            if let (preparedInput, result, preparedEnvironment) = stateCache.snapshot(input: input) {
                switch result {
                case .success(let state):
                    let anchor = claudeReplyAnchor(state, message: preparedInput.readingTarget?.message)
                    ClaudeThreadView(input: preparedInput, actions: actions, context: context.row(key), state: state)
                        .environment(\.threadExecutionPresence, preparedEnvironment?.presence ?? ThreadExecutionPresence())
                        .environment(\.threadExecutionLoader, preparedEnvironment?.loader)
                        .task(id: Anchor(request: preparedInput.readingTarget?.requestID, anchor: anchor)) {
                            if let request = preparedInput.readingTarget?.requestID, let anchor { onAnchor(request, anchor) }
                        }
                case .failure(let error):
                    let failure = claudeFailurePresentation(preparedInput, decodeError: error)
                    ThreadTranscriptFailure(message: failure.message, detail: failure.detail)
                }
            } else { NativeThreadLoadingIndicator() }
        }.task(id: HarnessReadingRequest(input: input, raw: raw, presence: presence, hasLoader: loader != nil)) { await stateCache.load(input: input, raw: raw, environment: readingEnvironment) }
    }
    private struct Anchor: Hashable { let request: JSONText?; let anchor: JSONText? }
}
@MainActor func claudeVisible(_ id: JSONText, context: HarnessRenderContext) -> Bool {
    switch context.presentation { case .main(let excluded): !excluded.contains(id); case .execution(let execution): execution == id }
}
struct ClaudeTurnView: View {
    @Environment(\.threadAgentDetail) private var agentDetail
    @Environment(\.threadExecutionPresence) private var executionPresence
    @Environment(\.threadDetailVisibility) private var visibility
    let turn: ClaudeTurn
    let active: Bool
    let waiting: Bool
    let publicInteractions: [JSONText: PublicInteraction]
    let actions: HarnessThreadActions
    let context: HarnessRenderContext
    var steerReader = ThreadSteerReader()
    @Environment(\.locale) private var locale
    var body: some View {
        let usage = turn.raw["usage"]
        let inputs = [usage?["inputTokens"]?.numberValue, usage?["cachedTokens"]?.numberValue, usage?["cacheWriteTokens"]?.numberValue]
        let transcript = steerReader.transcript(turn.transcript(presence: executionPresence), execution: turn.id)
        let layout = ThreadTranscriptLayout(transcript, agentDetail: agentDetail,
            active: turn.status == "running", waiting: waiting, completed: turn.status == "completed", target: visibility.messageAnchorID)
        let workVisible = visibility.work && (visibility.workTurnID == nil || visibility.workTurnID == turn.id)
        let rows = layout.detailRows(executionID: turn.id, workVisible: workVisible, active: active, actions: actions, context: context) { id in
            guard let interaction = turn.interactions.first(where: { $0.claudeID("id") == id }) else { return nil }
            return AnyView(ClaudeInteractionView(interaction: interaction, publicInteraction: publicInteractions[id], actions: actions))
        }
        return ThreadDetailTurn(id: turn.id, author: turn.raw["author"], rows: rows,
            reasoningUsage: usage?["reasoningTokens"]?.numberValue.map { ThreadReasoningUsage(tokens: $0, scope: .reportedTurn) },
            createdAt: turn.createdAt, updatedAt: turn.finishedAt ?? turn.updatedAt,
            status: claudeLocalized(waiting ? "等待输入" : turn.status == "interrupted" ? "已取消" : turn.raw["statusLabel"]?.stringValue ?? claudeStatus(turn.status), locale: locale),
            completedAt: turn.status == "completed" ? turn.finishedAt : nil,
            usage: AnyView(ThreadTokenUsage(input: inputs.allSatisfy { $0 != nil } ? inputs.compactMap { $0 }.reduce(0,+) : nil,
                output: usage?["outputTokens"]?.numberValue, cached: usage?["cachedTokens"]?.numberValue,
                cacheWrite: usage?["cacheWriteTokens"]?.numberValue, reasoning: usage?["reasoningTokens"]?.numberValue)), active: active, executionRunning: turn.status == "running" && !waiting,
                executionTailIsWork: layout.tailIsWork, workAvailable: layout.hasWork(reasoningTokens: usage?["reasoningTokens"]?.numberValue))
            .nativeReadingExecutionReady(turn.id, settled: turn.status != "running")
    }
}

private func decodeClaudeReadingState(_ raw: JSONValue) throws -> ClaudeState {
    do {
        try PluginJSONValidation.validate(.object(["sessionState": raw]))
        return try ClaudeState(raw)
    }
    catch {
        throw error
    }
}
