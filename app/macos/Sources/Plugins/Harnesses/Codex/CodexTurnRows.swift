import Foundation
import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI

struct CodexTurnRows: View {
    @Environment(\.threadAgentDetail) private var agentDetail
    @Environment(\.threadDetailVisibility) private var visibility
    let turn: CodexTurn
    let active: Bool
    let state: CodexState
    let observation: JSONValue
    let actions: HarnessThreadActions
    let context: HarnessRenderContext
    @Environment(\.locale) private var locale
    var steerReader = ThreadSteerReader()
    @Environment(\.threadExecutionPresence) private var executionPresence
    @State private var busyInteractionID: JSONText?
    @State private var actionError: (id: JSONText, message: String)?

    var body: some View {
        let transcript = steerReader.transcript(turn.transcript(presence: executionPresence), execution: turn.executionId)
        let layout = ThreadTranscriptLayout(transcript, agentDetail: agentDetail,
            active: turn.active, waiting: turn.status == "waiting-input", completed: turn.status == "completed", target: visibility.messageAnchorID)
        let workVisible = visibility.work && (visibility.workTurnID == nil || visibility.workTurnID == turn.executionId)
        let interactions = firstByID(turn.interactions)
        let rows = layout.detailRows(executionID: turn.executionId, workVisible: workVisible,
                                     active: active, actions: actions, context: context) { id in
            guard let interaction = interactions[id] else { return nil }
            return AnyView(CodexInteractionPanel(interaction: interaction, publicInteraction: publicInteractions[id],
                busy: busyInteractionID == id, error: actionError?.id == id ? actionError?.message : nil,
                respond: { action, answers in respond(interaction: interaction, actionID: action, answers: answers) }))
        }
        return ThreadDetailTurn(id: turn.executionId, author: author, rows: rows,
            reasoningUsage: executionReasoningTokens.map { ThreadReasoningUsage(tokens: $0, scope: .turn) },
            createdAt: turn.createdAt, updatedAt: turn.finishedAt ?? turn.updatedAt,
            status: statusLabel, completedAt: turn.status == "completed" ? turn.finishedAt : nil,
            usage: AnyView(ThreadTokenUsage(input: turn.usage?["inputTokens"]?.numberValue,
                output: turn.usage?["outputTokens"]?.numberValue, cached: turn.usage?["cachedInputTokens"]?.numberValue,
                reasoning: turn.usage?["reasoningTokens"]?.numberValue)), active: active, executionRunning: turn.status == "running",
            executionTailIsWork: layout.tailIsWork,
            workAvailable: layout.hasWork(reasoningTokens: executionReasoningTokens))
            .nativeReadingExecutionReady(turn.executionId, settled: !["running", "waiting-input"].contains(turn.status))
            .onChange(of: turn.interactions) { _, interactions in
                if let busyInteractionID, !interactions.contains(where: { $0.id == busyInteractionID && $0.status == "pending" && $0.blocksTurn }) {
                    self.busyInteractionID = nil
                }
            }
    }

    private var executionReasoningTokens: Double? {
        guard let samples = turn.raw["reasoningTokensByGeneration"]?.objectValue, !samples.isEmpty,
              samples.values.allSatisfy({ $0.numberValue != nil }) else { return nil }
        return samples.values.reduce(0) { $0 + ($1.numberValue ?? 0) }
    }

    private var author: JSONValue {
        var value = turn.author?.objectValue ?? [:]
        if let runtimeModel = turn.runtimeModel, !codexTrim(.text(runtimeModel)).codeUnits.isEmpty { value["model"] = .string(codexTrim(.text(runtimeModel))) }
        return .object(value)
    }

    private var statusLabel: String {
        switch turn.status {
        case "waiting-input": return codexLocalized("等待输入", locale: locale)
        case "completed": return codexLocalized("已完成", locale: locale)
        case "failed": return codexLocalized("失败", locale: locale)
        case "interrupted": return codexLocalized("已取消", locale: locale)
        default:
            let label = turn.statusLabel.flatMap { $0.isEmpty ? nil : $0 } ?? "运行中"
            switch label {
            case "运行中", "正在连接 Codex": return codexLocalized(label, locale: locale)
            default: return label
            }
        }
    }

    private var publicInteractions: [JSONText: JSONValue] {
        codexPublicInteractionsByNativeId(state: state.raw, observation: observation)
    }

    private func respond(interaction: CodexInteraction, actionID: JSONText, answers: JSONValue?) {
        let matches = state.turns.flatMap(\.interactions).filter { $0.id == interaction.id && $0.status == "pending" && $0.blocksTurn }
        guard matches.count == 1, let owned = matches.first, let publicInteraction = publicInteractions[interaction.id],
              owned.actions.contains(where: { $0["id"] == .string(actionID) }),
              publicInteraction["actions"]?.arrayValue?.contains(where: { $0["id"] == .string(actionID) }) == true else {
            actionError = (interaction.id, codexLocalized("该 Codex 请求已失效。", locale: locale)); return
        }
        guard busyInteractionID != interaction.id else { return }
        busyInteractionID = interaction.id; actionError = nil
        var request: [String: JSONValue] = ["interactionId": publicInteraction["id"] ?? .null, "actionId": .string(actionID)]
        request["answers"] = answers
        Task {
            do { try await actions.respond(HarnessRespondRequest(json: codexObject(request))) }
            catch {
                actionError = (interaction.id, error.localizedDescription)
                if busyInteractionID == interaction.id { busyInteractionID = nil }
            }
        }
    }
}

private func firstByID<T: Identifiable>(_ items: [T]) -> [T.ID: T] {
    var result: [T.ID: T] = [:]
    for item in items where result[item.id] == nil { result[item.id] = item }
    return result
}

extension CodexTurn {
    func transcript(presence: ThreadExecutionPresence) -> [ThreadTranscriptItem] {
        let messages = firstByID(messages)
        let activities = firstByID(activities)
        let interactions = firstByID(interactions)
        let notices = Dictionary(self.notices.map { ($0.codexIdentity("id"), $0) }, uniquingKeysWith: { first, _ in first })
        var seenActivities = Set<JSONText>()
        var seenNotices = Set<JSONText>()
        // The reducer stores an error notice for each occurrence plus one
        // turn-level marker. The marker points to the current terminal error.
        let errorHasNotice = error.map { message in
            self.notices.contains { $0["level"] == .text("error") && $0["message"]?.stringValue == message }
        } ?? false
        var hasError = errorHasNotice
        var items: [ThreadTranscriptItem] = []
        for entry in timeline {
            let body: ThreadTranscriptItem.Body
            switch entry.kind {
            case "user-message":
                guard let message = messages[entry.raw.codexIdentity("messageId")], message.role == "user", !message.isInternal else { continue }
                body = .user(message.transcriptInput)
            case "assistant":
                body = .reply(entry.content, phase: .init(status: entry.status), anchor: entry.id)
            case "reasoning":
                body = .reasoning(entry.content, hasContent: threadHasText(entry.content) || presence.contains(entry.id, "content"))
            case "activity":
                let id = entry.raw.codexIdentity("activityId")
                guard seenActivities.insert(id).inserted, let activity = activities[id] else { continue }
                body = .activity(transcriptActivity(activity, presence: presence))
            case "interaction":
                guard let interaction = interactions[entry.raw.codexIdentity("interactionId")] else { continue }
                body = interaction.status == "pending" ? .request(interaction.id)
                    : .resolution(title: interaction.title, status: threadRequestResolution(interaction.status))
            case "notice":
                let id = entry.raw.codexIdentity("noticeId")
                guard seenNotices.insert(id).inserted, let notice = notices[id] else { continue }
                body = transcriptNotice(notice)
            case "review":
                guard let review, !review.isEmpty else { continue }
                body = .review(review)
            case "context-compaction": body = .compaction
            case "error":
                guard !hasError, let error, !error.isEmpty else { continue }
                body = .error(error)
                hasError = true
            default: continue
            }
            items.append(.init(entry.id, body))
        }
        // Older snapshots can retain an entity without a chronological marker.
        for notice in self.notices where notice["level"] == .text("error") && seenNotices.insert(notice.codexIdentity("id")).inserted {
            items.append(.init(JSONText(codeUnits: executionId.codeUnits + Array(":notice:".utf16) + notice.codexIdentity("id").codeUnits),
                               transcriptNotice(notice)))
        }
        for activity in self.activities where seenActivities.insert(activity.id).inserted {
            items.append(.init(JSONText(codeUnits: executionId.codeUnits + Array(":activity:".utf16) + activity.id.codeUnits),
                               .activity(transcriptActivity(activity, presence: presence))))
        }
        if !hasError, let error, !error.isEmpty {
            items.append(.init(JSONText(codeUnits: executionId.codeUnits + Array(":error".utf16)), .error(error)))
        }
        return items
    }

    private func transcriptNotice(_ notice: JSONValue) -> ThreadTranscriptItem.Body {
        let text = notice["message"]?.stringValue ?? ""
        return notice["level"] == .text("error") ? .error(text) : .notice(text)
    }

    private func transcriptActivity(_ activity: CodexActivity, presence: ThreadExecutionPresence) -> ThreadTranscriptActivity {
        // Hook start and successful completion can both carry only lifecycle metadata.
        let hasContent = activity.kind != "hook" || activity.toolCall || activity.raw["toolName"] != nil ||
            activity.status == "failed" || activity.status == "cancelled" ||
            presence.contains(activity.id, "detail") || activityHasOutput(activity)
        return .init(id: activity.id, kind: activity.kind, label: activity.label, status: activity.status,
            detail: activity.detail, filePaths: activity.filePaths,
            countsAsTool: activity.toolCall || ["command", "file", "tool", "search"].contains(activity.kind), hasContent: hasContent)
    }

    private func activityHasOutput(_ activity: CodexActivity) -> Bool {
        guard !codexTrim(activity.raw["detail"]).codeUnits.isEmpty else { return false }
        // Older projections can contain the native run object in the detail field.
        guard let detail = activity.detail,
              let metadata = try? JSONValue(data: Data(detail.utf8)), let fields = metadata.objectValue,
              metadata["id"] == .string(activity.id), metadata["status"] == .text(activity.status),
              fields.keys.allSatisfy({ ["id", "status", "name"].contains($0.string) }),
              metadata["name"] == nil || metadata["name"] == .text("") || metadata["name"] == .text(activity.label)
        else { return true }
        return false
    }

}
