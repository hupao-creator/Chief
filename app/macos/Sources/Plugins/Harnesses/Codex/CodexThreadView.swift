import Foundation
import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI

/// Thread scope is a directory. Only visible opaque rows acquire their complete
/// native content; neither overview previews nor manifests become transcript.
public struct CodexThreadView: View {
    @Environment(\.locale) private var locale
    @Environment(\.threadAgentDetail) private var agentDetail
    public let input: HarnessThreadInput
    public let actions: HarnessThreadActions
    public let context: HarnessRenderContext
    @State private var stateCache = CodexReadingState()
    @State private var resolvedAnchor: (thread: JSONText, request: JSONText, anchor: JSONText)?

    public init(input: HarnessThreadInput, actions: HarnessThreadActions, context: HarnessRenderContext) {
        self.input = input; self.actions = actions; self.context = context
    }

    public var body: some View {
        Group {
            switch stateCache.result {
            case .success(let state):
                if case .row(let key) = context.content {
                    if let turn = (state.forkHistory + state.turns).first(where: { $0.rowID == key }) {
                        if codexTurnVisible(turn.executionId, context: context) { turnView(turn, state: state) }
                    } else { ThreadTranscriptFailure(message: codexLocalized("历史执行不可用", locale: locale)) }
                } else {
                    conversation(state)
                }
            case .failure(let error): ThreadTranscriptFailure(message: codexLocalized(error.localizedDescription, locale: locale))
            case nil:
                NativeReadingPlaceholder(placement: loadingPlacement)
                    .id(input.thread.id)
            }
        }
        .task(id: input.thread.sessionState) {
            await stateCache.load(input.thread.sessionState, createdAt: input.thread.createdAt)
        }
    }

    private var loadingPlacement: NativeReadingPlaceholder.Placement {
        if case .row = context.content { return .inline }
        return .surface
    }

    @ViewBuilder private func conversation(_ state: CodexState) -> some View {
        let ownIDs = Set(state.turns.map(\.executionId))
        let allTurns = state.forkHistory + state.turns
        let rows: [ThreadConversationRow] = allTurns.map { turn in
            ThreadConversationRow(id: turn.rowID, createdAt: turn.createdAt,
                execution: ThreadConversationExecution(id: turn.executionId, title: input.thread.executionTitles[turn.executionId]?.string,
                    prompt: turn.messages.first(where: { $0.role == "user" && !$0.isInternal })?.content ?? "",
                    // Manifests carry the selected reply; full state retains an aggregate answer.
                    answer: context.content == .manifest ? turn.answer : turn.lastReaderReply?.content ?? "", completedAt: turn.status == "completed" ? turn.finishedAt : nil,
                    readable: ownIDs.contains(turn.executionId), isActive: turn.active), node: AnyView(turnView(turn, state: state)))
        } + supplementalRows(state)
        ThreadConversation(threadId: input.thread.id,
            title: agentDetail ? input.thread.title.string : codexDocumentTitle(input.thread, state: state), icon: codexDocumentEmoji(input.thread),
            rows: rows, readingTarget: readingTarget(state),
            running: input.thread.observation.latestExecution?.status == .running,
            runningTurnId: runningTurnID(state),
            activeExecutionId: input.thread.observation.isExecutionActive ? input.thread.observation.latestExecution?.executionID : nil,
            context: context,
            renderRow: context.content == .manifest ? { key in
                if allTurns.contains(where: { $0.rowID == key }) {
                    return AnyView(CodexLazyTurnRow(key: key, input: input, actions: actions, context: context,
                        onAnchor: { request, anchor in resolvedAnchor = (input.thread.id, request, anchor) }))
                }
                return rows.first(where: { $0.id == key })?.node ?? AnyView(EmptyView())
            } : nil)
    }

    private func readingTarget(_ state: CodexState) -> ThreadConversationReadingTarget? {
        guard let target = input.readingTarget else { return nil }
        let anchor = codexMokuReplyAnchor(state: state.raw, message: target.message)
            ?? (resolvedAnchor?.thread == input.thread.id && resolvedAnchor?.request == target.requestID ? resolvedAnchor?.anchor : nil)
        return ThreadConversationReadingTarget(requestId: target.requestID,
            mode: target.mode == .current ? .current : .history, executionId: target.executionID, anchorId: anchor, position: target.position,
                follow: input.thread.observation.isExecutionActive && input.thread.observation.latestExecution?.executionID == target.executionID, hasMessageTarget: target.message != nil)
    }

    private func runningTurnID(_ state: CodexState) -> JSONText? {
        guard let execution = input.thread.observation.latestExecution, execution.status == .running else { return nil }
        return state.turns.last(where: { $0.executionId == execution.executionID && $0.status == "running" })?.executionId
    }

    private func turnView(_ turn: CodexTurn, state: CodexState) -> some View {
        CodexTurnRows(turn: turn, active: turn.executionId == runningTurnID(state),
            state: state, observation: input.thread.observation.json, actions: actions, context: context)
    }

    private func supplementalRows(_ state: CodexState) -> [ThreadConversationRow] {
        var rows: [ThreadConversationRow] = []
        if !state.backgroundTerminals.isEmpty {
            rows.append(ThreadConversationRow(id: "codex:background-terminals", createdAt: state.updatedAt,
                node: AnyView(ThreadBackgroundWork(id: "codex:background-terminals", title: "后台终端", items: state.backgroundTerminals.map {
                    .init(id: $0.codexIdentity("id"), label: $0["command"]?.stringValue ?? "", detail: $0["cwd"]?.stringValue, status: "running")
                }))))
        }
        if state.nativeActivity?["status"]?.stringValue?.contains("systemError") == true {
            rows.append(ThreadConversationRow(id: "codex:system-error", createdAt: state.nativeActivity?["updatedAt"]?.numberValue ?? state.updatedAt,
                node: AnyView(ThreadTranscriptFailure(message: codexLocalized("Codex 线程发生系统错误", locale: locale)))))
        }
        return rows
    }
}

private struct CodexLazyTurnRow: View {
    @Environment(\.locale) private var locale
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
                case .loading: NativeReadingPlaceholder(placement: .inline).id(key)
                case .error(let message): ThreadTranscriptFailure(message: codexLocalized("读取对话内容失败。", locale: locale) + " " + codexLocalized(message, locale: locale), retry: { try await resource.retry() })
                case .ready(let raw):
                    ThreadDeferredExecutionContent(raw: raw, rowKey: key, context: context) { value in
                        CodexLoadedTurnRow(key: key, input: input, actions: actions, context: context, onAnchor: onAnchor, raw: value)
                    }
                }
            } else { NativeReadingPlaceholder(placement: .inline).id(key) }
        }
        .nativeReadingObservation("load", role: "row.load", value: loadState)
        .task(id: key) {
            guard !Task.isCancelled else { return }
            resource = context.contentResource(.row(key))
        }
        .onDisappear {
            let old = resource; old?.beginRelease(); resource = nil
            Task { await old?.release() }
        }
    }
    private var loadState: JSONValue {
        let state: String
        var error: JSONValue = .null
        switch resource?.state {
        case .ready?: state = "ready"
        case .error(let message)?: state = "error"; error = .text(message)
        default: state = "loading"
        }
        return .object(["rowId": .string(key), "state": .text(state), "error": error])
    }
}

private struct CodexLoadedTurnRow: View {
    @Environment(\.locale) private var locale
    let key: JSONText
    let input: HarnessThreadInput
    let actions: HarnessThreadActions
    let context: HarnessRenderContext
    let onAnchor: (JSONText, JSONText) -> Void
    let raw: JSONValue
    @State private var stateCache = CodexReadingState()
    @ViewBuilder var body: some View {
        Group {
            if case .success(let state) = stateCache.result,
               let turn = (state.forkHistory + state.turns).first(where: { $0.rowID == key }) {
                let active = input.thread.observation.latestExecution?.status == .running &&
                    input.thread.observation.latestExecution?.executionID == turn.executionId && turn.status == "running"
                if codexTurnVisible(turn.executionId, context: context) {
                    let anchor = codexMokuReplyAnchor(state: state.raw, message: input.readingTarget?.message)
                    CodexTurnRows(turn: turn, active: active, state: state,
                                  observation: input.thread.observation.json, actions: actions, context: context.row(key))
                        .nativeReadingContentReady()
                        .task(id: AnchorRequest(request: input.readingTarget?.requestID, anchor: anchor)) {
                            guard !Task.isCancelled else { return }
                            if let target = input.readingTarget, target.executionID == turn.executionId, let anchor {
                                onAnchor(target.requestID, anchor)
                            }
                        }
                }
            } else if case .some = stateCache.result { ThreadTranscriptFailure(message: codexLocalized("Codex sessionState 无效", locale: locale)) }
            else { NativeReadingPlaceholder(placement: .inline).id(key) }
        }
        .task(id: raw) { await stateCache.load(raw) }
    }

    private struct AnchorRequest: Hashable { let request: JSONText?; let anchor: JSONText? }
}

@MainActor private func codexTurnVisible(_ executionID: JSONText, context: HarnessRenderContext) -> Bool {
    switch context.presentation {
    case .main(let excluded): !excluded.contains(executionID)
    case .execution(let id): id == executionID
    }
}

private func codexDocumentEmoji(_ thread: HarnessThread) -> String? {
    nativeGeneratedThreadEmoji(metadata: thread.metadataState)
}

private func codexDocumentTitle(_ thread: HarnessThread, state: CodexState) -> String {
    nativeGeneratedThreadDocumentTitle(metadata: thread.metadataState, title: thread.title,
        initialPrompt: state.turns.first?.messages.first(where: { $0.role == "user" && !$0.isInternal })?.raw["content"].flatMap { value in
            if case let .string(text) = value { return text }; return nil
        })
}
