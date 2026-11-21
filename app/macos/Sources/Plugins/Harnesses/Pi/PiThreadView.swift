import Foundation
import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI

struct PiThreadView: View {
    let input: HarnessThreadInput
    let actions: HarnessThreadActions
    let context: HarnessRenderContext
    @Environment(\.locale) private var locale
    @State private var decoder = HarnessReadingState<PiState>(decode: { try PiState($0) })
    var body: some View {
        Group {
            if let (preparedInput, result, _) = decoder.snapshot(input: input) {
                switch result {
                case .success(let state): PiPreparedThreadView(input: preparedInput, actions: actions, context: context, state: state)
                case .failure(let failure): ThreadTranscriptFailure(message: piLocalized("Pi 状态不可用", locale) + " · " + failure.localizedDescription)
                }
            } else { NativeThreadLoadingIndicator() }
        }.task(id: HarnessReadingRequest(input: input, raw: input.thread.sessionState)) {
            await decoder.load(input: input, raw: input.thread.sessionState)
        }
    }
}

private struct PiPreparedThreadView: View {
    @Environment(\.threadAgentDetail) private var agentDetail
    let input: HarnessThreadInput
    let actions: HarnessThreadActions
    let context: HarnessRenderContext
    let state: PiState
    @State private var anchor: (request: JSONText, id: JSONText)?
    var body: some View {
        Group {
            if case .row(let id) = context.content {
                if let execution = state.executions.first(where: { $0.executionID == id }), visible(id) {
                    PiTurn(input: input, state: state, execution: execution, actions: actions, context: context)
                }
            } else { conversation(state) }
        }
    }
    private func visible(_ id: JSONText) -> Bool {
        switch context.presentation { case .main(let excluded): !excluded.contains(id); case .execution(let execution): execution == id }
    }
    private func conversation(_ state: PiState) -> some View {
        let rows = state.executions.map { execution -> ThreadConversationRow in
            let messages = state.messagesByExecution[execution.executionID] ?? []
            return ThreadConversationRow(id: execution.executionID, createdAt: execution.startedAt,
                execution: ThreadConversationExecution(id: execution.executionID, title: input.thread.executionTitles[execution.executionID]?.string,
                    prompt: messages.first { $0.role == "user" && $0.raw["presentation"] != .text("internal") }?.text.string ?? "",
                    answer: messages.last(where: { $0.isReaderReply(execution.status) })?.text.string ?? "",
                    completedAt: execution.status == .completed ? execution.finishedAt : nil,
                    isActive: execution.status == .running || execution.status == .waitingForUser),
                node: AnyView(PiTurn(input: input, state: state, execution: execution, actions: actions, context: context)))
        }
        let latest = input.thread.observation.latestExecution
        return ThreadConversation(threadId: input.thread.id,
            title: agentDetail ? input.thread.title.string : nativeGeneratedThreadDocumentTitle(metadata: input.thread.metadataState, title: input.thread.title,
                initialPrompt: state.messages.first { $0.role == "user" && $0.raw["presentation"] != .text("internal") }?.text),
            icon: nativeGeneratedThreadEmoji(metadata: input.thread.metadataState), rows: rows,
            readingTarget: readingTarget(state), running: latest?.status == .running,
            runningTurnId: latest.map { [.running, .waitingForUser].contains($0.status) ? $0.executionID : nil } ?? nil,
            activeExecutionId: input.thread.observation.isExecutionActive ? latest?.executionID : nil,
            context: context, renderRow: context.content == .manifest ? { key in
                AnyView(PiLazyRow(key: key, input: input, actions: actions, context: context,
                    onAnchor: { request, id in anchor = (request, id) }))
            } : nil)
    }
    private func readingTarget(_ state: PiState) -> ThreadConversationReadingTarget? {
        input.readingTarget.map { target in
            ThreadConversationReadingTarget(requestId: target.requestID, mode: target.mode == .current ? .current : .history,
                executionId: target.executionID,
                anchorId: piMokuAnchor(state, target.message) ?? (anchor?.request == target.requestID ? anchor?.id : nil), position: target.position,
                follow: input.thread.observation.isExecutionActive && input.thread.observation.latestExecution?.executionID == target.executionID, hasMessageTarget: target.message != nil)
        }
    }
}

private struct PiLazyRow: View {
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
                case .error(let message): ThreadTranscriptFailure(message: message, retry: { try await resource.retry() })
                case .ready(let raw):
                    ThreadDeferredExecutionContent(raw: raw, rowKey: key, context: context) { value in
                        PiLoadedRow(key: key, input: input, actions: actions, context: context, onAnchor: onAnchor, raw: value)
                    }
                }
            } else { NativeThreadLoadingIndicator() }
        }
        .task(id: key) { resource = context.contentResource(.row(key)) }
        .onDisappear {
            let old = resource; old?.beginRelease(); resource = nil
            Task { await old?.release() }
        }
    }
}

private struct PiLoadedRow: View {
    let key: JSONText
    let input: HarnessThreadInput
    let actions: HarnessThreadActions
    let context: HarnessRenderContext
    let onAnchor: (JSONText, JSONText) -> Void
    let raw: JSONValue
    @State private var decoder = HarnessReadingState<PiState>(decode: { try PiState($0) })
    @Environment(\.threadExecutionPresence) private var presence
    @Environment(\.threadExecutionLoader) private var loader
    private var readingEnvironment: HarnessReadingEnvironment { .init(presence: presence, loader: loader) }
    @ViewBuilder var body: some View {
        Group {
            if let (preparedInput, result, preparedEnvironment) = decoder.snapshot(input: input) {
                if case .success(let state) = result, let execution = state.executions.first(where: { $0.executionID == key }) {
                    let anchor = piMokuAnchor(state, preparedInput.readingTarget?.message)
                    PiTurn(input: preparedInput, state: state, execution: execution, actions: actions, context: context.row(key))
                        .environment(\.threadExecutionPresence, preparedEnvironment?.presence ?? ThreadExecutionPresence())
                        .environment(\.threadExecutionLoader, preparedEnvironment?.loader)
                        .onChange(of: AnchorRequest(request: preparedInput.readingTarget?.requestID, anchor: anchor), initial: true) { _, request in
                            if let id = request.request, let anchor = request.anchor { onAnchor(id, anchor) }
                        }
                } else { ThreadTranscriptFailure(message: "Invalid Pi session state") }
            } else { NativeThreadLoadingIndicator() }
        }.task(id: HarnessReadingRequest(input: input, raw: raw, presence: presence, hasLoader: loader != nil)) { await decoder.load(input: input, raw: raw, environment: readingEnvironment) }
    }
    private struct AnchorRequest: Hashable { let request: JSONText?; let anchor: JSONText? }
}

private struct PiTurn: View {
    @Environment(\.threadAgentDetail) private var agentDetail
    @Environment(\.threadExecutionPresence) private var executionPresence
    @Environment(\.threadDetailVisibility) private var visibility
    let input: HarnessThreadInput
    let state: PiState
    let execution: PublicExecution
    let actions: HarnessThreadActions
    let context: HarnessRenderContext
    @Environment(\.locale) private var locale
    @State private var busy = false
    @State private var failure: String?
    private var messages: [PiMessage] { state.messagesByExecution[execution.executionID] ?? [] }
    private var current: Bool { input.thread.observation.latestExecution?.executionID == execution.executionID }
    private var active: Bool { current && [.running, .waitingForUser].contains(input.thread.observation.latestExecution?.status ?? .completed) }
    var body: some View {
        let usage = state.executionUsage[execution.executionID]
        let waiting = current && input.thread.observation.latestExecution?.status == .waitingForUser
        let pending = waiting ? input.thread.observation.latestExecution?.interactions ?? [] : []
        var items = piTranscript(messages, execution: execution, presence: executionPresence)
        for interaction in pending { items.append(.init(interaction.id, .request(interaction.id))) }
        let layout = ThreadTranscriptLayout(items, agentDetail: agentDetail, active: execution.status == .running || execution.status == .waitingForUser,
                                            waiting: waiting, completed: execution.status == .completed, target: visibility.messageAnchorID)
        let rows = layout.detailRows(executionID: execution.executionID,
            workVisible: visibility.work && (visibility.workTurnID == nil || visibility.workTurnID == execution.executionID),
            active: current && execution.status == .running, actions: actions, context: context) { id in
            guard let interaction = pending.first(where: { $0.id == id }) else { return nil }
            return AnyView(PiInteraction(interaction: interaction, busy: busy) { actionID, answers in
                guard !busy else { return }
                busy = true
                failure = nil
                defer { busy = false }
                do { try await actions.respond(HarnessRespondRequest(interactionID: id, actionID: actionID, answers: answers)) }
                catch { failure = error.localizedDescription }
            }.id(id))
        }
        return VStack(alignment: .leading, spacing: 8) {
            if let failure { ThreadTranscriptFailure(message: failure) }
            ThreadDetailTurn(id: execution.executionID, author: author, rows: rows,
                reasoningUsage: usage?.reasoning.map { ThreadReasoningUsage(tokens: $0, scope: .turn) },
                createdAt: execution.startedAt, updatedAt: execution.finishedAt ?? execution.startedAt,
                status: NativePluginLocalization.localize(threadExecutionStatus(waiting ? .waitingForUser : execution.status), locale: locale), completedAt: execution.status == .completed ? execution.finishedAt : nil,
                usage: usage.map { AnyView(ThreadTokenUsage(input: $0.prompt, output: $0.output, cached: $0.cacheRead,
                    cacheWrite: $0.cacheWrite, reasoning: $0.reasoning)) }, active: active, executionRunning: execution.status == .running && input.thread.observation.latestExecution?.status == .running,
                    executionTailIsWork: layout.tailIsWork, workAvailable: layout.hasWork(reasoningTokens: usage?.reasoning))
                .nativeReadingExecutionReady(execution.executionID, settled: ![.running, .waitingForUser].contains(execution.status))
        }
    }
    private var author: JSONValue {
        var author = state.authors[execution.executionID]?.objectValue ?? [:]
        if let native = messages.last(where: { $0.role == "assistant" && !piTrim($0.model ?? "").codeUnits.isEmpty }) {
            let components = [native.provider, native.model].compactMap { $0 }.filter { !$0.codeUnits.isEmpty }
            var units: [UInt16] = []
            for (index, component) in components.enumerated() {
                if index > 0 { units.append(47) }; units += component.codeUnits
            }
            author["model"] = .string(JSONText(codeUnits: units))
        }
        return .object(author)
    }
}

private struct PiInteraction: View {
    let interaction: PublicInteraction
    let busy: Bool
    let respond: (JSONText, [JSONText: HarnessResponseAnswer]?) async -> Void
    @State private var answers = InteractionAnswers()
    private var questions: [InteractionQuestionSpec] {
        interaction.questions.map { q in InteractionQuestionSpec(id: q.id, prompt: q.prompt.string, header: q.header?.string,
            multiple: q.multiple, allowOther: q.allowOther, secret: q.secret,
            options: q.options.map { InteractionQuestionOption(value: $0.value, label: $0.label.string, description: $0.description?.string) }) }
    }
    var body: some View {
        ThreadDetailRequest {
            VStack(alignment: .leading, spacing: 0) {
                ThreadRequestHeader(interaction.title.string, description: interaction.description?.string, question: interaction.kind != .permission)
                ForEach(questions) { question in InteractionQuestionField(question: question, answers: $answers, disabled: busy) }
                ThreadRequestActions {
                    ForEach(interaction.actions, id: \.id) { action in
                        Button(action.label.string) {
                            let values = action.intent == .submit ? answers.answersFor(questions).mapValues { answer -> HarnessResponseAnswer in
                                switch answer { case .single(let v): .text(v); case .multiple(let v): .multiple(v) }
                            } : nil
                            Task { await respond(action.id, values) }
                        }.buttonStyle(ThreadRequestButtonStyle(primary: action.intent == .submit || action.intent == .allow))
                            .disabled(busy || (action.intent == .submit && !questions.allSatisfy { answers.answered($0) }))
                    }
                }.padding(.top, 22)
            }
        }
    }
}

struct PiFailure: View {
    let message: String
    var retry: (() async throws -> Void)?
    @State private var failure: String?
    @State private var retrying = false
    @Environment(\.locale) private var locale
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(failure ?? message).textSelection(.enabled)
            if let retry { Button(piLocalized("重试", locale)) { Task {
                retrying = true; defer { retrying = false }
                do { try await retry(); failure = nil } catch { failure = error.localizedDescription }
            } }.disabled(retrying) }
        }.font(NativeTypography.inter(size: 12)).foregroundStyle(NativePalette.thread.danger.swiftUI)
            .nativeThreadDocumentMargins()
            .nativeReadingContentReady()
    }
}
