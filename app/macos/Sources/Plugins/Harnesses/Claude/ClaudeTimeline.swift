import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI

extension ClaudeTurn {
    func transcript(presence: ThreadExecutionPresence) -> [ThreadTranscriptItem] {
        let timeline = claudeProjectTimeline(self)
        var records = timeline
        // Some stored turns carry entities without occurrence markers.
        func fallback(_ kind: String, _ key: JSONText, _ fields: [String: JSONValue]) -> JSONValue {
            let identity = JSONText(codeUnits: id.codeUnits + Array(":unreferenced:".utf16) + key.codeUnits)
            return claudeObject(fields.merging(["kind": .text(kind), "id": .string(identity)]) { _, value in value })
        }
        let promptsSeen = Set(timeline.compactMap { $0["promptIndex"]?.intValue })
        for index in prompts.indices where !promptsSeen.contains(index) && !internalIndexes.contains(index) {
            records.append(fallback("user-message", JSONText("prompt:\(index)"), ["promptIndex": .integer(index)]))
        }
        for (kind, entities) in [("activity", activities), ("interaction", interactions), ("notice", notices)] {
            let seen = Set(timeline.filter { $0.claudeKind == kind }.map { $0.claudeID(kind + "Id") })
            for entity in entities where !seen.contains(entity.claudeID("id")) {
                let key = JSONText(codeUnits: Array((kind + ":").utf16) + entity.claudeID("id").codeUnits)
                records.append(fallback(kind, key, [kind: entity]))
            }
        }
        if !timeline.contains(where: { $0.claudeKind == "error" }), let error = raw["error"], error.stringValue?.isEmpty == false {
            records.append(fallback("error", "error", ["message": error]))
        }
        if !timeline.contains(where: { $0.claudeKind == "context-compaction" }), raw["compacted"] == .bool(true) {
            records.append(fallback("context-compaction", "context-compaction", [:]))
        }
        return claudeTranscript(records, turn: self, presence: presence)
    }
}

func claudeTranscript(_ records: [JSONValue], turn: ClaudeTurn? = nil, presence: ThreadExecutionPresence) -> [ThreadTranscriptItem] {
    var anchors: [JSONText: JSONText] = [:]
    for record in records where record.claudeKind == "assistant" && record["messageId"] != nil {
        anchors[record.claudeID("messageId")] = record.claudeID("id")
    }
    return records.compactMap { item in
        let id = item.claudeID("id")
        let body: ThreadTranscriptItem.Body
        let text = item["content"]?.stringValue ?? ""
        switch item.claudeKind {
        case "user-message":
            let index = item["promptIndex"]?.intValue ?? 0
            if turn?.internalIndexes.contains(index) == true { return nil }
            let attachments = turn?.raw["promptAttachments"]?.arrayValue
            let list = attachments.flatMap { $0.indices.contains(index) ? $0[index].arrayValue : nil } ?? item["attachments"]?.arrayValue ?? []
            let content = turn.flatMap { $0.prompts.indices.contains(index) ? $0.prompts[index].stringValue : nil } ?? text
            body = .user(.init(content, followUp: turn != nil && index > 0, createdAt: item["createdAt"]?.numberValue,
                annotations: list.compactMap { $0["annotation"] }.map(ThreadMessageAnnotation.init(json:)),
                attachments: list.filter { $0["annotation"] == nil }.map { attachment in
                    .init(id: attachment.claudeID("id"), label: attachment["name"]?.stringValue ?? "",
                          title: "\(attachment["mimeType"]?.stringValue ?? "") · \(Int(attachment["size"]?.numberValue ?? 0)) B")
                }))
        case "assistant":
            body = .reply(text, phase: .init(status: item["status"]?.stringValue), anchor: anchors[item.claudeID("messageId")] ?? id)
        case "reasoning": body = .reasoning(text, hasContent: threadHasText(text) || presence.contains(id, "content"))
        case "activity":
            guard let activity = item["activity"] else { return nil }
            let key = activity["id"] == nil ? id : activity.claudeID("id")
            let hasContent = activity.claudeKind != "hook" || activity["toolName"] != nil || activity["status"] != .text("completed") ||
                threadHasText(activity["detail"]?.stringValue ?? "") || presence.contains(key, "detail")
            body = .activity(.init(id: key, kind: activity.claudeKind, label: activity["label"]?.stringValue ?? "",
                status: activity["status"]?.stringValue ?? "",
                input: activity["output"] == nil ? nil : activity["detail"]?.stringValue, detail: (activity["output"] ?? activity["detail"])?.stringValue,
                countsAsTool: activity["toolName"] != nil, hasContent: hasContent))
        case "interaction":
            guard let interaction = item["interaction"] else { return nil }
            if interaction["status"] == .text("pending"), turn != nil { body = .request(interaction.claudeID("id")) }
            else {
                let title = interaction["title"]?.stringValue ?? ""
                let status = interaction["status"]?.stringValue ?? ""
                var lines = [title]
                if turn == nil {
                    lines += [interaction["description"], interaction["toolName"]].compactMap { $0?.stringValue }
                    for question in interaction["questions"]?.arrayValue ?? [] {
                        lines += [question["question"]?.stringValue].compactMap { $0 }
                        lines += (question["options"]?.arrayValue ?? []).compactMap { $0["label"]?.stringValue }
                    }
                }
                body = .resolution(title: lines.joined(separator: "\n"), status: status == "pending" ? "等待输入" : threadRequestResolution(status))
            }
        case "notice":
            guard let notice = item["notice"] else { return nil }
            let message = notice["message"]?.stringValue ?? ""
            body = notice["level"] == .text("error") ? .error(claudeRedacted(message)) : .notice(message)
        case "review": body = .review(text)
        case "context-compaction": body = .compaction
        case "error": body = .error(claudeRedacted(item["message"]?.stringValue ?? ""))
        default: return nil
        }
        return .init(id, body)
    }
}

struct ClaudeActivityGlyph: View {
    var status: String
    var kind = "tool"
    var body: some View {
        if status == "running" { ProgressView().controlSize(.mini).scaleEffect(0.7) }
        else { NativeIcon(name: status == "failed" ? "CircleAlert" : status == "cancelled" ? "CircleStop" : kind == "command" ? "SquareTerminal" : kind == "subagent" ? "Bot" : "Check", size: 13) }
    }
}
func claudeStatus(_ value: String) -> String {
    ["running":"运行中","completed":"已完成","failed":"失败","interrupted":"已中断","cancelled":"已取消","allowed":"已允许","denied":"已拒绝","submitted":"已提交","resolved":"已处理"][value] ?? value
}
func claudeEmoji(_ thread: HarnessThread) -> String? { nativeGeneratedThreadEmoji(metadata: thread.metadataState) }
func claudeDocumentTitle(_ thread: HarnessThread, state: ClaudeState) -> String {
    let prompt: JSONText? = state.turns.first?.visiblePrompts.first.map { if case .string(let text) = $0 { text } else { JSONText("") } }
    return nativeGeneratedThreadDocumentTitle(metadata: thread.metadataState, title: thread.title, initialPrompt: prompt)
}


struct ClaudeFailure: View {
    let message: String
    var detail: String? = nil
    var retry: (() async throws -> Void)?
    @State private var error: String?
    @Environment(\.locale) private var locale
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) { NativeIcon(name: "CircleAlert", size: 13); Text(claudeLocalized(claudeRedacted(error ?? message), locale: locale)).textSelection(.enabled) }
            if let detail, !detail.isEmpty {
                Text(claudeLocalized(claudeRedacted(detail), locale: locale)).font(NativeTypography.mono(size: 10))
                    .foregroundStyle(NativePalette.thread.muted.swiftUI).textSelection(.enabled).padding(.leading, 21)
            }
            if let retry { Button(claudeLocalized("重试", locale: locale)) { Task { do { try await retry(); error = nil } catch { self.error = error.localizedDescription } } }.buttonStyle(.plain) }
        }.font(NativeTypography.inter(size: 12)).foregroundStyle(NativePalette.thread.danger.swiftUI).padding(.vertical, 8)
            .nativeThreadDocumentMargins()
            .nativeReadingContentReady()
    }
}
