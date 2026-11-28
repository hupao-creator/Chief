import Combine
import Foundation
import Observation
import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI

/// The Dock's own public interaction. Agent-thread requests stay in their
/// workspace, and the Harness remains responsible for interpreting responses.
public struct NativeMokuDockIntervention: Equatable, Sendable {
    public let threadID: JSONText
    public let harnessID: JSONText
    public let executionID: JSONText
    public let threadTitle: String
    public let request: PublicInteraction
    public let questions: [InteractionQuestionSpec]
    public let submitActionID: JSONText?
    public var isQuestion: Bool { request.kind == .question }
    public var identity: JSONText {
        JSONText(nativeMokuPresentationTuple([.string(threadID), .string(request.id)]))
    }
}

/// The production MokuDock projection boundary. Receive every installed runtime
/// transaction synchronously, after the overview has projected its operations.
/// The host decodes Harness state. The Dock follows the current execution
/// and its audited operations.
@MainActor @Observable
public final class NativeMokuWorkspacePresentation {
    private(set) var pendingConversationSend: NativeMokuConversationSend?
    let acceptedConversationSends = PassthroughSubject<NativeMokuConversationSend, Never>()

    func showConversationSend(_ submission: NativeComposerSubmission, input: JSONValue,
                              perform: () async throws -> Void) async throws {
        // Admission still owns concurrency and receipt recovery across Chief drafts.
        guard pendingConversationSend == nil, let owner = workspace.catalog.moku?.id else {
            return try await perform()
        }
        let outgoing = NativeMokuConversationSend(owner: owner, submission: submission, input: input)
        pendingConversationSend = outgoing
        defer { pendingConversationSend = nil }
        try await perform()
        acceptedConversationSends.send(outgoing)
    }

    public let workspace: NativeWorkspaceModel
    public let overview: NativeOverviewWorkspaceModel
    public var dockMode: MokuCharacterMode {
        if let activeOperation {
            return .operation(activity: activeOperation.kind.rawValue, phase: activeOperation.phase.rawValue)
        }
        return running ? .running : .idle
    }
    private(set) var executionRunning = false
    public private(set) var running = false
    public private(set) var sessionIdle = true
    public private(set) var landing = false
    public private(set) var tagAgentRunning = false
    public private(set) var talk: String?
    public private(set) var talkID: JSONText?
    public private(set) var talkMessage: NativeMokuTalkMessage?
    public private(set) var replyKey: JSONText?
    public private(set) var intervention: NativeMokuDockIntervention?
    public private(set) var activeOperation: NativeOverviewMokuOperation?
    public private(set) var activity: HarnessActivity?
    public private(set) var error: String?
    public var interactionIsQuestion: Bool { intervention?.isQuestion == true }
    public var executionKey: String? {
        guard let thread = workspace.catalog.moku, let execution = thread.observation.latestExecution else { return nil }
        return nativeMokuPresentationTuple([.string(thread.id), .string(thread.harnessID), .string(execution.executionID)])
    }
    /// Foreground reasoning is live execution content. A tool, answer,
    /// terminal state or disconnect retires it immediately.
    public var reasoning: MokuReasoningContent? {
        workspace.runtimeAvailable && activeOperation == nil ? reasoningContent : nil
    }
    private var reasoningContent: MokuReasoningContent?
    public var interaction: AnyView? {
        guard let intervention else { return nil }
        return AnyView(NativeMokuDockInteractionPanel(intervention: intervention,
            disabled: workspace.connection != .connected,
            respond: { [weak self] response in
                guard let self else { throw CancellationError() }
                try await self.respond(to: intervention, with: response)
            }).id(intervention.identity))
    }

    @ObservationIgnored private var previousThread: HarnessThread?
    @ObservationIgnored private var harnessPresentation: HarnessMokuPresentation?
    @ObservationIgnored private var landingInitialized = false

    public init(workspace: NativeWorkspaceModel, overview: NativeOverviewWorkspaceModel) {
        self.workspace = workspace; self.overview = overview
        reconcile(refreshHarness: true)
    }

    public func receive(_ event: RuntimeClientEvent) {
        switch event {
        case .snapshot: reconcile(refreshHarness: true)
        case .mutation: reconcile(refreshHarness: false)
        case .connection, .synchronizing, .failure, .overviewFilter, .threadContent: break
        }
    }

    /// Hydration and recovery catch up to the latest snapshot without replaying
    /// events that were never presented by this window.
    public func refresh() { reconcile(refreshHarness: true) }

    private func reconcile(refreshHarness: Bool) {
        let moku = workspace.catalog.moku
        let execution = moku?.observation.latestExecution
        // Unrelated agent transactions do not repeatedly decode Moku history.
        if moku != previousThread || refreshHarness {
            previousThread = moku
            do {
                harnessPresentation = try moku.flatMap { try workspace.harnessHost.mokuPresentation(input: .init(thread: $0)) }
                error = nil
            } catch {
                harnessPresentation = nil
                self.error = error.localizedDescription
                workspace.report(error)
            }
        }
        let fallbackRunning = moku.map { thread in
            workspace.catalog.executions.contains { $0["threadId"] == .string(thread.id) }
        } ?? false
        executionRunning = execution.map { $0.status == .running } ?? fallbackRunning
        running = moku?.pendingInput == true || executionRunning
        sessionIdle = moku?.pendingInput != true && !(execution.map { $0.status == .running || $0.status == .waitingForUser } ?? fallbackRunning)
        tagAgentRunning = workspace.catalog.agentRuns.contains { run in
            guard let id = run["agentId"]?.stringValue else { return false }
            return id == "tag.agent" || id.hasPrefix("tag.agent.")
        }
        activity = harnessPresentation?.activity.flatMap { value in
            execution?.status == .running && value.executionID == execution?.executionID ? value : nil
        }
        if let moku, let activity, case .reasoning(let text, let offset) = activity.body {
            reasoningContent = MokuReasoningContent(sourceText: text.string, sourceOffset: offset ?? 0,
                segmentKey: nativeMokuPresentationTuple([.string(moku.id), .string(moku.harnessID),
                    .string(activity.executionID), .integer(activity.sequence)]))
        } else { reasoningContent = nil }
        let currentTranscript = execution.map { execution in
            (moku?.transcript?.arrayValue ?? []).filter { $0["executionId"] == .string(execution.executionID) }
        } ?? []
        reconcileLanding(transcript: currentTranscript, executionActive: execution?.status == .running || execution?.status == .waitingForUser)
        // The overview also presents completed routes. Only a running route in
        // THIS execution owns the Dock, even when the next activity is delayed.
        activeOperation = overview.featuredOperation.flatMap { operation in
            guard execution?.status == .running || execution?.status == .waitingForUser,
                  operation.phase == .running,
                  currentTranscript.contains(where: { $0["id"]?.stringValue == operation.id }) else { return nil }
            return operation
        }
        talkMessage = NativeMokuTalkMessage.latest(in: moku)
        talkID = talkMessage?.id; talk = talkMessage?.text
        replyKey = moku.flatMap { thread in harnessPresentation?.reply.flatMap { value in
            let text = value.excerpt.string.replacingOccurrences(of: "[*_~`>#-]+", with: " ", options: .regularExpression)
            guard !Self.normalizeWhitespace(text).isEmpty else { return nil }
            return JSONText(nativeMokuPresentationTuple([.string(thread.id), .string(thread.harnessID), .string(value.id)]))
        } }
        intervention = moku.flatMap(Self.intervention)
    }

    private func reconcileLanding(transcript: [JSONValue], executionActive: Bool) {
        guard workspace.catalog.moku != nil, let count = overview.globalConversationCount else {
            landing = false; landingInitialized = false
            return
        }
        if count == 0 {
            landing = true; landingInitialized = true
            return
        }
        if landingInitialized && !landing { return }
        let dispatches = transcript.filter { $0["type"]?.stringValue == "tool-operation" }
            .compactMap { NativeMokuDispatch(operation: $0, executionIsActive: executionActive) }
        let pending = dispatches.contains { $0.phase == .dispatching }
        let started = dispatches.contains { dispatch in
            dispatch.threadID.map { overview.containsGlobalThread(JSONText($0)) } == true
        }
        if !landingInitialized {
            landing = pending && !overview.hasEstablishedConversation
            landingInitialized = true
        } else if landing {
            // CreateThread publishes a durable shell before native admission.
            // Keep that first shell behind landing until its public success, or
            // another admitted conversation arrives. A failed empty shell is
            // not proof that the first task was accepted.
            if started || (!pending && (dispatches.isEmpty || overview.hasEstablishedConversation)) {
                landing = false
            }
        }
    }

    private func respond(to intervention: NativeMokuDockIntervention, with response: HarnessRespondRequest) async throws {
        do {
            guard let thread = workspace.catalog.moku, thread.id == intervention.threadID,
                  thread.harnessID == intervention.harnessID,
                  thread.observation.latestExecution?.executionID == intervention.executionID else {
                throw PluginContractError("This interaction is no longer awaiting a response")
            }
            try await workspace.harnessHost.actions(for: thread).respond(response)
        } catch { workspace.report(error); throw error }
    }

    private static func intervention(_ thread: HarnessThread) -> NativeMokuDockIntervention? {
        guard thread.moku == true, let execution = thread.observation.latestExecution,
              execution.status == .waitingForUser else { return nil }
        for interaction in execution.interactions where !interaction.actions.isEmpty {
            let submit = interaction.kind == .question ? interaction.actions.first { $0.intent == .submit } : nil
            if interaction.kind == .question && (interaction.questions.isEmpty || submit == nil) { continue }
            let questions = submit == nil ? [] : PublicInteractionQuestionnaire.specs(for: interaction)
            return NativeMokuDockIntervention(threadID: thread.id, harnessID: thread.harnessID,
                executionID: execution.executionID, threadTitle: thread.title.string, request: interaction,
                questions: questions, submitActionID: submit?.id)
        }
        return nil
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        // ECMAScript \s includes FEFF, but excludes Foundation's NEL (0085).
        var result = "", pendingSpace = false
        for scalar in text.unicodeScalars {
            let whitespace: Bool
            switch scalar.value {
            case 0x0009...0x000D, 0x0020, 0x00A0, 0x1680, 0x2000...0x200A,
                 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: whitespace = true
            default: whitespace = false
            }
            if whitespace { pendingSpace = !result.isEmpty }
            else { if pendingSpace { result.append(" "); pendingSpace = false }; result.unicodeScalars.append(scalar) }
        }
        return result
    }
}

struct NativeMokuDockInteractionPanel: View {
    let intervention: NativeMokuDockIntervention
    let disabled: Bool
    let respond: (HarnessRespondRequest) async throws -> Void
    @State private var answers: InteractionAnswers
    @State private var step = 0
    @State private var busyActionID: JSONText?
    @Environment(\.locale) private var locale
    init(intervention: NativeMokuDockIntervention, disabled: Bool, respond: @escaping (HarnessRespondRequest) async throws -> Void) {
        self.intervention = intervention; self.disabled = disabled; self.respond = respond
        _answers = State(initialValue: PublicInteractionQuestionnaire.initialAnswers(for: intervention.request))
    }
    private var questionnaire: PublicInteractionQuestionnaire { .init(interaction: intervention.request, answers: answers) }
    private var questions: [InteractionQuestionSpec] { questionnaire.questions }
    private var current: InteractionQuestionSpec? { questions.isEmpty ? nil : questions[min(step, questions.count - 1)] }
    private var currentAnswered: Bool { current.map { questionnaire.errors[$0.id] == nil } ?? true }
    private var lastStep: Bool { step >= questions.count - 1 }
    private var busy: Bool { disabled || busyActionID != nil }
    private let ink = Color(red: 247 / 255, green: 245 / 255, blue: 238 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: intervention.isQuestion ? 7 : 5) {
                Circle().fill(Color(red: 242 / 255, green: 191 / 255, blue: 89 / 255))
                    .frame(width: intervention.isQuestion ? 7 : 6, height: intervention.isQuestion ? 7 : 6)
                    .shadow(color: Color(red: 242 / 255, green: 191 / 255, blue: 89 / 255).opacity(0.1), radius: 4)
                Text(intervention.isQuestion ? "USER QUESTION" : "PERMISSION").tracking(intervention.isQuestion ? 1.1 : 0.88)
                Text(intervention.threadTitle).lineLimit(1).foregroundStyle(ink.opacity(0.38))
                Spacer(minLength: 0)
                if questions.count > 1 { Text("\(step + 1) / \(questions.count)").foregroundStyle(ink.opacity(0.42)) }
            }.font(.system(size: intervention.isQuestion ? 10 : 8, weight: .bold, design: .monospaced))
                .foregroundStyle(ink.opacity(0.56)).padding(.bottom, intervention.isQuestion ? 9 : 4)
            if let current {
                NativeScrollView {
                    if intervention.request.questions.contains(where: { $0.form != nil }) {
                        InteractionQuestionField(question: current, answers: $answers, disabled: busy, style: .form)
                            .id(current.id)
                    } else { NativeMokuDockQuestionField(question: current, answers: $answers, disabled: busy).id(current.id) }
                }
                    .mokuInk(value: current.id)
                    .scrollIndicators(.automatic).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                GeometryReader { geometry in
                    NativeScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(intervention.request.title.string).font(.system(size: 20, weight: .bold)).tracking(-0.9)
                                .foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                            if let detail = intervention.request.description {
                                Text(detail.string).font(.system(size: 10)).lineSpacing(3.5).lineLimit(2)
                                    .foregroundStyle(ink.opacity(0.68)).textSelection(.enabled)
                            }
                        }.frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .leading)
                    }.scrollIndicators(.automatic)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Group {
                if !intervention.isQuestion {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        actionButtons
                    }
                } else {
                    HStack(spacing: 7) {
                        actionButtons
                        if !lastStep {
                            if step > 0 { previousButton }
                            Button(localize("下一步", "Next")) { step += 1 }
                                .buttonStyle(NativeMokuInteractionButtonStyle(primary: true, question: true))
                                .disabled(busy || !currentAnswered)
                                .accessibilityIdentifier("moku-interaction-next")
                        } else {
                            if step > 0 { previousButton }
                        }
                    }
                }
            }.padding(.top, intervention.isQuestion ? 9 : 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(ink)
        .environment(\.colorScheme, .dark)
        .onChange(of: questions.map(\.id)) { previous, next in
            let currentID = previous.isEmpty ? nil : previous[min(step, previous.count - 1)]
            step = currentID.flatMap { next.firstIndex(of: $0) } ?? min(step, max(0, next.count - 1))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(intervention.isQuestion ? localize("用户问题", "User question") : localize("权限请求", "Permission request"))
    }
    private var actionButtons: some View {
        ForEach(intervention.request.actions.filter { !intervention.isQuestion || $0.id != intervention.submitActionID || lastStep }, id: \.id) { action in
            let label = busyActionID == action.id ? localize("处理中…", "Working…") : action.label.string
            let button = Button(label) { submit(action.id) }
            button
                .buttonStyle(NativeMokuInteractionButtonStyle(primary: action.intent == .allow || action.intent == .submit || action.id == intervention.submitActionID,
                    question: intervention.isQuestion))
                // The custom style dims its ink, but macOS needs a standard button to expose AXEnabled.
                .accessibilityRepresentation { button.buttonStyle(.bordered) }
                .accessibilityIdentifier("moku-interaction-action-\(action.id.string)")
                .disabled(busy || (action.id == intervention.submitActionID && !questionnaire.canSubmit))
        }
    }
    private var previousButton: some View {
        Button(localize("上一步", "Previous")) { step -= 1 }
            .buttonStyle(NativeMokuInteractionButtonStyle(primary: false, question: true)).disabled(busy)
    }
    private func submit(_ actionID: JSONText) {
        guard !busy, actionID != intervention.submitActionID || questionnaire.canSubmit else { return }
        busyActionID = actionID
        let response = HarnessRespondRequest(interactionID: intervention.request.id, actionID: actionID,
            answers: actionID == intervention.submitActionID ? questionnaire.answers.mapValues { value in
                switch value { case .single(let text): .text(text); case .multiple(let values): .multiple(values) }
            } : nil)
        Task {
            defer { busyActionID = nil }
            // The workspace owns the operation-error surface; retaining this
            // local draft makes a rejected response safely retryable.
            try? await respond(response)
        }
    }
    private func localize(_ zh: String, _ en: String) -> String { locale.language.languageCode?.identifier == "zh" ? zh : en }
}

/// Dock-specific option grid, sharing the same answer reducer as Harness forms.
/// This content is painted inside Moku's dark question body, without card chrome.
private struct NativeMokuDockQuestionField: View {
    let question: InteractionQuestionSpec
    @Binding var answers: InteractionAnswers
    let disabled: Bool
    @Environment(\.locale) private var locale
    @FocusState private var inputFocused: Bool
    private let ink = Color(red: 247 / 255, green: 245 / 255, blue: 238 / 255)
    private var otherOpen: Bool { answers.otherOpen(question) }
    private var input: Binding<String> { Binding(get: { answers.otherText(question) }, set: { answers.writeOther(question, text: $0) }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(question.header.flatMap { $0.isEmpty ? nil : $0 } ?? question.prompt)
                .font(.system(size: 31, weight: .bold)).tracking(-1.4).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if let header = question.header, !header.isEmpty {
                Text(question.prompt).font(.system(size: 12)).lineSpacing(6).foregroundStyle(ink.opacity(0.68))
                    .lineLimit(3).padding(.top, 10)
            }
            if !question.options.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(question.options) { option in
                        choice(label: option.label, detail: option.description, selected: answers.picked(question).contains(option.value)) {
                            answers.toggle(question, value: option.value)
                        }
                    }
                    if question.allowOther {
                        choice(label: localize("其它…", "Other…"), detail: localize("输入自己的回答", "Enter your own answer"), selected: otherOpen) {
                            answers.toggleOther(question)
                        }
                    }
                }.padding(.top, 14).accessibilityElement(children: .contain)
                    .accessibilityLabel(question.header ?? question.prompt)
            }
            if otherOpen {
                Group {
                    if question.secret { SecureField(localize("输入回答", "Enter an answer"), text: input) }
                    else { TextField(localize("输入回答", "Enter an answer"), text: input) }
                }.textFieldStyle(.plain).font(.system(size: 11)).foregroundStyle(ink)
                    .padding(.horizontal, 12).frame(height: 34)
                    .background(ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ink.opacity(0.18)))
                    .focused($inputFocused).disabled(disabled).padding(.top, 7)
                    .accessibilityLabel(question.prompt)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .mokuInk(value: otherOpen)
            .onChange(of: otherOpen, initial: true) { _, open in inputFocused = open && !disabled }
    }
    private func choice(label: String, detail: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: question.multiple ? 4 : 6.5)
                    .fill(selected ? Color(red: 16 / 255, green: 17 / 255, blue: 15 / 255) : .clear)
                    .overlay(RoundedRectangle(cornerRadius: question.multiple ? 4 : 6.5).strokeBorder(ink.opacity(selected ? 1 : 0.48), lineWidth: selected ? 4 : 1))
                    .frame(width: 13, height: 13).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 11, weight: .bold)).lineLimit(1)
                    if let detail { Text(detail).font(.system(size: 9)).lineLimit(1).foregroundStyle(ink.opacity(0.42)) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, 9).padding(.vertical, 7).frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(selected ? .white : ink.opacity(0.65))
                .background(ink.opacity(selected ? 0.1 : 0.045), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(ink.opacity(selected ? 0.42 : 0.12)))
                .mokuInk(value: selected)
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.48 : 1).mokuInk(value: disabled)
            .accessibilityLabel(label).accessibilityValue(selected ? localize("已选", "Selected") : localize("未选", "Not selected"))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func localize(_ zh: String, _ en: String) -> String { locale.language.languageCode?.identifier == "zh" ? zh : en }
}

private struct NativeMokuInteractionButtonStyle: ButtonStyle {
    let primary: Bool
    let question: Bool
    @Environment(\.isEnabled) private var enabled
    private let ink = Color(red: 247 / 255, green: 245 / 255, blue: 238 / 255)
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: question ? 11 : 10, weight: .bold)).lineLimit(1)
            .padding(.horizontal, question ? 14 : 10).frame(maxWidth: .infinity, minHeight: question ? 44 : 36)
            .foregroundStyle(primary ? Color(red: 16 / 255, green: 17 / 255, blue: 15 / 255) : ink)
            .background(primary ? ink : .clear, in: RoundedRectangle(cornerRadius: question ? 13 : 11))
            .overlay(RoundedRectangle(cornerRadius: question ? 13 : 11).strokeBorder(ink.opacity(primary ? 1 : 0.18)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1).opacity(enabled ? 1 : 0.34)
            .mokuInk(value: configuration.isPressed).mokuInk(value: enabled)
    }
}

/// JSON.stringify tuples, including short control escapes and isolated UTF-16
/// surrogates, for parity with persisted reply keys.
private func nativeMokuPresentationTuple(_ values: [JSONValue]) -> String {
    func encode(_ value: JSONValue) -> String {
        if let integer = value.intValue { return String(integer) }
        guard case .string(let text) = value else {
            return (try? value.encodedData()).map { String(decoding: $0, as: UTF8.self) } ?? "null"
        }
        var output = "\"", index = 0
        while index < text.codeUnits.count {
            let unit = text.codeUnits[index]; index += 1
            switch unit {
            case 0x22: output += "\\\""
            case 0x5C: output += "\\\\"
            case 0x08: output += "\\b"
            case 0x0C: output += "\\f"
            case 0x0A: output += "\\n"
            case 0x0D: output += "\\r"
            case 0x09: output += "\\t"
            case 0x00...0x1F: output += String(format: "\\u%04x", unit)
            case 0xD800...0xDBFF:
                if index < text.codeUnits.count, (0xDC00...0xDFFF).contains(text.codeUnits[index]) {
                    output += String(decoding: [unit, text.codeUnits[index]], as: UTF16.self); index += 1
                } else { output += String(format: "\\u%04x", unit) }
            case 0xDC00...0xDFFF: output += String(format: "\\u%04x", unit)
            default: output.unicodeScalars.append(UnicodeScalar(unit)!)
            }
        }
        return output + "\""
    }
    return "[" + values.map(encode).joined(separator: ",") + "]"
}
