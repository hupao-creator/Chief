import Foundation
import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI

public struct OpenCodeThreadView: View {
    @Environment(\.threadAgentDetail) private var agentDetail
    @Environment(\.threadExecutionPresence) private var executionPresence
    @Environment(\.threadDetailVisibility) private var visibility
    public let input: HarnessThreadInput
    public let actions: HarnessThreadActions
    public let context: HarnessRenderContext
    @Environment(\.locale) private var locale
    private var providedState: OpenCodeState?
    @State private var stateCache = HarnessReadingState<OpenCodeState>(decode: { raw in
        try PluginJSONValidation.validate(.object(["sessionState": raw]))
        return try OpenCodeState(raw)
    })
    @State private var resolvedAnchor: (request: JSONText, anchor: JSONText)?
    public init(input: HarnessThreadInput, actions: HarnessThreadActions, context: HarnessRenderContext) {
        self.input = input; self.actions = actions; self.context = context; providedState = nil
    }
    init(input: HarnessThreadInput, actions: HarnessThreadActions, context: HarnessRenderContext, state: OpenCodeState) {
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
                    OpenCodeThreadView(input: preparedInput, actions: actions, context: context, state: state)
                case .failure(let error):
                    ThreadTranscriptFailure(message: ocLocalized("OpenCode 状态不可用", locale: locale) + " · " + error.localizedDescription)
                }
            } else { NativeHarnessLoadingIndicator(content: context.content) }
        }.task(id: HarnessReadingRequest(input: input, raw: input.thread.sessionState)) {
            if providedState == nil { await stateCache.load(input: input, raw: input.thread.sessionState) }
        }
    }
    private func conversation(_ state: OpenCodeState) -> some View {
        let latest = input.thread.observation.latestExecution
        var rows: [ThreadConversationRow] = []
        if state.messages.contains(where: \.inherited) {
            rows.append(.init(id: "opencode-fork-history", createdAt: input.thread.createdAt, history: true,
                              node: AnyView(row("opencode-fork-history", state: state))))
        }
        for execution in state.executions {
            let primary = (state.messagesByExecution[execution.executionID] ?? []).filter { !$0.inherited && ($0.nativeSessionID == nil || $0.nativeSessionID == state.nativeSessionID) }
            rows.append(.init(id: execution.executionID, createdAt: execution.startedAt,
                execution: .init(id: execution.executionID, title: input.thread.executionTitles[execution.executionID]?.string, prompt: primary.first { $0.role == "user" && $0.raw["presentation"] != .text("internal") }?.text ?? "",
                    answer: primary.last(where: \.isReaderReply)?.text ?? "", completedAt: execution.status == .completed ? execution.finishedAt : nil,
                    isActive: execution.status == .running || execution.status == .waitingForUser),
                node: AnyView(row(execution.executionID, state: state))))
        }
        if openCodeTruncationPlacement(truncated: state.contentTruncated, presentation: context.presentation) == .surface {
            rows.append(.init(id: "opencode-content-truncated", createdAt: input.thread.createdAt,
                              node: AnyView(OpenCodeTruncationNotice())))
        }
        let target = input.readingTarget.map { target in
            ThreadConversationReadingTarget(requestId: target.requestID, mode: target.mode == .current ? .current : .history,
                executionId: target.executionID, anchorId: ocMokuReplyAnchor(state, target: target.message)
                    ?? (resolvedAnchor?.request == target.requestID ? resolvedAnchor?.anchor : nil), position: target.position,
                follow: input.thread.observation.isExecutionActive && input.thread.observation.latestExecution?.executionID == target.executionID, hasMessageTarget: target.message != nil)
        }
        return ThreadConversation(threadId: input.thread.id, title: agentDetail ? input.thread.title.string : ocDocumentTitle(input.thread, state: state), icon: ocEmoji(input.thread.metadataState),
            rows: rows, readingTarget: target, running: latest?.status == .running,
            runningTurnId: input.thread.observation.isExecutionActive ? latest?.executionID : nil,
            activeExecutionId: input.thread.observation.isExecutionActive ? latest?.executionID : nil, context: context,
            renderRow: context.content == .manifest ? { key in
                if key == "opencode-content-truncated" { return AnyView(OpenCodeTruncationNotice()) }
                return AnyView(OpenCodeLazyRow(key: key, input: input, actions: actions, context: context,
                    onAnchor: { request, anchor in resolvedAnchor = (request, anchor) }))
            } : nil)
            .environment(\.threadCardProviderColor, OpenCodeLogo.themeColor)
    }
    @ViewBuilder private func row(_ key: JSONText, state: OpenCodeState) -> some View {
        if key == "opencode-fork-history" {
            let inherited = state.messages.filter(\.inherited)
            let session = state.raw["forkSource"]?.ocText("sessionId") ?? state.nativeSessionID
            ThreadTranscriptHistory(id: key, items: ocTranscript(inherited, sessionID: session, presence: executionPresence),
                createdAt: input.thread.createdAt, actions: actions, context: context)
        } else if let execution = state.executions.first(where: { $0.executionID == key }), ocExecutionVisible(key, context: context) {
            OpenCodeTurn(execution: execution, state: state, input: input, actions: actions, context: context)
        } else { ThreadTranscriptFailure(message: ocLocalized("历史执行不可用", locale: locale)) }
    }
}
private struct OpenCodeLazyRow: View {
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
                case .loading: NativeThreadLoadingIndicator(alignedLeading: true)
                case .error(let error): ThreadTranscriptFailure(message: error, retry: { try await resource.retry() })
                case .ready(let raw):
                    ThreadDeferredExecutionContent(raw: raw, rowKey: key, context: context) { value in
                        OpenCodeLoadedRow(key: key, input: input, actions: actions, context: context, onAnchor: onAnchor, raw: value)
                    }
                }
            } else { NativeThreadLoadingIndicator(alignedLeading: true) }
        }
        .task(id: key) { resource = context.contentResource(.row(key)) }
        .onDisappear { let old = resource; old?.beginRelease(); resource = nil; Task { await old?.release() } }
    }
}

private struct OpenCodeLoadedRow: View {
    let key: JSONText
    let input: HarnessThreadInput
    let actions: HarnessThreadActions
    let context: HarnessRenderContext
    let onAnchor: (JSONText, JSONText) -> Void
    let raw: JSONValue
    @State private var stateCache = HarnessReadingState<OpenCodeState>(decode: { raw in
        try PluginJSONValidation.validate(.object(["sessionState": raw]))
        return try OpenCodeState(raw)
    })
    @Environment(\.threadExecutionPresence) private var presence
    @Environment(\.threadExecutionLoader) private var loader
    private var readingEnvironment: HarnessReadingEnvironment { .init(presence: presence, loader: loader) }
    @ViewBuilder var body: some View {
        Group {
            if let (preparedInput, result, preparedEnvironment) = stateCache.snapshot(input: input) {
                switch result {
                case .failure(let error): ThreadTranscriptFailure(message: error.localizedDescription)
                case .success(let state):
                    let anchor = ocMokuReplyAnchor(state, target: preparedInput.readingTarget?.message)
                    OpenCodeThreadView(input: preparedInput, actions: actions, context: context.row(key), state: state)
                        .environment(\.threadExecutionPresence, preparedEnvironment?.presence ?? ThreadExecutionPresence())
                        .environment(\.threadExecutionLoader, preparedEnvironment?.loader)
                            .task(id: AnchorRequest(request: preparedInput.readingTarget?.requestID, anchor: anchor)) {
                                if let target = preparedInput.readingTarget, let anchor { onAnchor(target.requestID, anchor) }
                            }
                }
            } else { NativeThreadLoadingIndicator() }
        }.task(id: HarnessReadingRequest(input: input, raw: raw, presence: presence, hasLoader: loader != nil)) { await stateCache.load(input: input, raw: raw, environment: readingEnvironment) }
    }
    private struct AnchorRequest: Hashable { let request: JSONText?; let anchor: JSONText? }
}
private struct OpenCodeTurn: View {
    @Environment(\.threadAgentDetail) private var agentDetail
    @Environment(\.threadExecutionPresence) private var executionPresence
    @Environment(\.threadDetailVisibility) private var visibility
    let execution: PublicExecution
    let state: OpenCodeState
    let input: HarnessThreadInput
    let actions: HarnessThreadActions
    let context: HarnessRenderContext
    var steerReader = ThreadSteerReader()
    @Environment(\.locale) private var locale
    var body: some View {
        let messages = (state.messagesByExecution[execution.executionID] ?? []).filter { !$0.inherited }
        let latest = input.thread.observation.latestExecution
        let current = latest?.executionID == execution.executionID
        let waiting = current && latest?.status == .waitingForUser
        let executionActive = [.running, .waitingForUser].contains(execution.status)
        let usage = ocExecutionUsage(messages, auxiliary: state.auxiliary.filter { $0.ocText("executionId") == execution.executionID })
        var items = ocTranscript(messages, sessionID: state.nativeSessionID, execution: execution, presence: executionPresence)
        let pending = waiting ? latest?.interactions ?? [] : []
        for interaction in pending { items.append(.init(interaction.id, .request(interaction.id))) }
        for record in state.interactions where record.ocID("executionId") == execution.executionID && record["status"] != .text("pending") {
            let id = ocPublicID("interaction", [execution.executionID, record.ocID("id")])
            items.append(.init(id, .resolution(title: record["title"]?.stringValue ?? "", status: threadRequestResolution(record["status"]?.stringValue ?? ""))))
        }
        let transcript = steerReader.transcript(items, execution: execution.executionID)
        let layout = ThreadTranscriptLayout(transcript, agentDetail: agentDetail, active: executionActive,
                                            waiting: waiting, completed: execution.status == .completed, target: visibility.messageAnchorID)
        let workVisible = visibility.work && (visibility.workTurnID == nil || visibility.workTurnID == execution.executionID)
        var rows = layout.detailRows(executionID: execution.executionID, workVisible: workVisible, active: current && execution.status == .running,
                                     actions: actions, context: context) { id in
            guard let interaction = pending.first(where: { $0.id == id }) else { return nil }
            return AnyView(OpenCodeInteractionPanel(interaction: interaction, native: state.nativeInteraction(id), actions: actions).id(id))
        }
        if openCodeTruncationPlacement(truncated: state.contentTruncated, presentation: context.presentation) == .inline {
            rows.insert(.init(id: "opencode-content-truncated", kind: .content, node: AnyView(OpenCodeTruncationNotice())), at: 0)
        }
        let nativeAuthor = messages.last { $0.role == "assistant" && !ocTrim($0.raw["model"]?.stringValue ?? "").isEmpty && ($0.nativeSessionID == nil || $0.nativeSessionID == state.nativeSessionID) }
        var author = state.raw["executionAuthors"]?.objectValue?[execution.executionID]?.objectValue ?? [:]
        if let effort = nativeAuthor?.raw["variant"], effort.stringValue?.isEmpty == false { author["effort"] = effort }
        if let nativeAuthor {
            author["model"] = .text([nativeAuthor.raw["provider"]?.stringValue, nativeAuthor.raw["model"]?.stringValue].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "/"))
        }
        return ThreadDetailTurn(id: execution.executionID, author: author.isEmpty ? nil : .object(author), rows: rows,
            reasoningUsage: usage.map { .init(tokens: $0.reasoning, scope: .turn) }, createdAt: execution.startedAt,
            updatedAt: execution.finishedAt ?? execution.startedAt, status: NativePluginLocalization.localize(threadExecutionStatus(waiting ? .waitingForUser : execution.status), locale: locale),
            completedAt: execution.status == .completed ? execution.finishedAt : nil,
            usage: usage.map { AnyView(ThreadTokenUsage(input: $0.input + $0.cacheRead + $0.cacheWrite,
                output: $0.output + $0.reasoning, cached: $0.cacheRead, cacheWrite: $0.cacheWrite, reasoning: $0.reasoning)) },
            active: current && input.thread.observation.isExecutionActive,
            executionRunning: execution.status == .running && latest?.status == .running,
            executionTailIsWork: layout.tailIsWork, workAvailable: layout.hasWork(reasoningTokens: usage?.reasoning))
            .nativeReadingExecutionReady(execution.executionID, settled: !executionActive)
    }

}
struct OpenCodeToolOutput: View {
    let text: String
    @State private var contentHeight: CGFloat = 18
    var body: some View {
        NativeScrollView(.vertical) {
            Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }.frame(height: min(360, max(18, contentHeight)))
    }
}
enum OpenCodeTruncationPlacement: Equatable { case none, surface, inline }
func openCodeTruncationPlacement(truncated: Bool, presentation: HarnessConversationPresentation) -> OpenCodeTruncationPlacement {
    guard truncated else { return .none }
    if case .execution = presentation { return .inline }
    return .surface
}
private struct OpenCodeTruncationNotice: View {
    @Environment(\.locale) private var locale
    var body: some View {
        ThreadTranscriptNotice(ocLocalized("部分内容因体积限制被省略或截断；完整内容仍保存在会话记录中。", locale: locale))
    }
}
@MainActor private func ocExecutionVisible(_ id: JSONText, context: HarnessRenderContext) -> Bool {
    switch context.presentation { case .main(let excluded): !excluded.contains(id); case .execution(let selected): id == selected }
}
private func ocDocumentTitle(_ thread: HarnessThread, state: OpenCodeState) -> String {
    let initial = state.messages.first { $0.role == "user" && $0.raw["presentation"] != .text("internal") && !$0.inherited && ($0.nativeSessionID == nil || $0.nativeSessionID == state.nativeSessionID) }?.raw.ocText("text")
    return nativeGeneratedThreadDocumentTitle(metadata: thread.metadataState, title: thread.title, initialPrompt: initial)
}
