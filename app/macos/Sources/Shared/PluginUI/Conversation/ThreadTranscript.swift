import ChiefCore
import ChiefPluginAPI
import Foundation
import SwiftUI

/// An occurrence in the reading document. Native IDs stay opaque, including the
/// message anchor shared by several separately ordered parts of one reply.
package struct ThreadTranscriptItem {
    package enum Body {
        case user(ThreadTranscriptInput)
        case reply(String, phase: ThreadTranscriptPhase, anchor: JSONText)
        case reasoning(String, hasContent: Bool)
        case activity(ThreadTranscriptActivity)
        case request(JSONText)
        case resolution(title: String, status: String)
        case notice(String)
        case compaction
        case review(String)
        case error(String)
    }

    package let id: JSONText
    package let body: Body
    package let delegated: Bool

    package init(_ id: JSONText, _ body: Body, delegated: Bool = false) {
        self.id = id
        self.body = body
        self.delegated = delegated
    }
}

package enum ThreadTranscriptPhase {
    case streaming, settled, failed

    package init(status: String?, failed: Bool = false) {
        if failed || status == "failed" { self = .failed }
        else if status == "streaming" { self = .streaming }
        else { self = .settled }
    }
}

package struct ThreadTranscriptInput {
    package var text: String
    package var followUp: Bool
    package var createdAt: Double?
    package var annotations: [ThreadMessageAnnotation]
    package var attachments: [ThreadMessageAttachment]

    package init(_ text: String, followUp: Bool, createdAt: Double? = nil,
                 annotations: [ThreadMessageAnnotation] = [], attachments: [ThreadMessageAttachment] = []) {
        self.text = text
        self.followUp = followUp
        self.createdAt = createdAt
        self.annotations = annotations
        self.attachments = attachments
    }
}

package struct ThreadTranscriptActivity {
    package let id: JSONText
    package let kind: String
    package let label: String
    package let status: String
    package let input: String?
    package let detail: String?
    package let filePaths: [JSONText]?
    package let countsAsTool: Bool
    package let hasContent: Bool

    package init(id: JSONText, kind: String? = nil, label: String, status: String,
                 input: String? = nil, detail: String? = nil, filePaths: [JSONText]? = nil, countsAsTool: Bool = true,
                 hasContent: Bool = true) {
        self.id = id
        // Preserve protocol kinds when supplied. Generic tool protocols
        // identify the same built-in operations by their native names.
        let name = label.lowercased()
        if kind == "file" && name == "read" { self.kind = "tool" }
        else if let kind { self.kind = kind }
        else {
            switch name {
            case "bash", "shell", "command", "terminal": self.kind = "command"
            case "edit", "write", "patch", "apply_patch", "multiedit", "notebookedit": self.kind = "file"
            case "web_search", "websearch", "webfetch", "grep", "glob", "find": self.kind = "search"
            case "task", "agent": self.kind = "agent"
            default: self.kind = "tool"
            }
        }
        self.label = label
        self.status = status == "complete" ? "completed" : status == "streaming" ? "running" : status
        self.input = input
        self.detail = detail
        self.filePaths = filePaths
        self.countsAsTool = countsAsTool
        self.hasContent = hasContent
    }
}

package func threadHasText(_ text: String) -> Bool {
    text.unicodeScalars.contains { !$0.properties.isWhitespace && $0.value != 0xFEFF }
}

/// Selection runs before view construction and before clipping a directory
/// preview. Delegated work belongs to the parent execution but cannot supply its
/// result. An explicit visit admits all text parts of the targeted message.
package struct ThreadTranscriptLayout {
    package struct Row {
        package let item: ThreadTranscriptItem
        package let kind: ThreadDetailRow.Kind
        package let execution: ThreadExecutionMembership?
        package let summary: ThreadExecutionSummary?
        package let finalReply: Bool
    }

    package let rows: [Row]
    package let tailIsWork: Bool
    private let agentDetail: Bool

    // Markdown delimiters can span adjacent native text parts of the same
    // message. A tool or reasoning occurrence still breaks the document there.
    private static func contiguousReplies(_ items: [ThreadTranscriptItem]) -> [ThreadTranscriptItem] {
        var result: [ThreadTranscriptItem] = []
        var index = items.startIndex
        while index < items.endIndex {
            let first = items[index]
            index += 1
            guard case let .reply(text, phase, anchor) = first.body else { result.append(first); continue }
            var body = text
            var identity = first.id
            while index < items.endIndex, items[index].delegated == first.delegated,
                  case let .reply(part, nextPhase, nextAnchor) = items[index].body, phase == nextPhase, anchor == nextAnchor {
                if items[index].id == anchor { identity = anchor }
                body += part
                index += 1
            }
            result.append(.init(identity, .reply(body, phase: phase, anchor: anchor), delegated: first.delegated))
        }
        return result
    }

    package init(_ source: [ThreadTranscriptItem], agentDetail: Bool, active: Bool = false,
                 waiting: Bool = false, completed: Bool = false, target: JSONText? = nil, inheritedTurns: Bool = false) {
        self.agentDetail = agentDetail
        let items = Self.contiguousReplies(source)
        var finals = Set<JSONText>()
        var last: JSONText?
        for item in items where !item.delegated {
            switch item.body {
            case .user where inheritedTurns:
                if let last { finals.insert(last) }
                last = nil
            case let .reply(text, phase, anchor) where phase != .streaming && (!agentDetail || phase != .failed) && threadHasText(text):
                last = anchor
            default: break
            }
        }
        if let last { finals.insert(last) }

        var rows: [Row] = []
        var runStart: JSONText?
        var tailIsWork = false
        for item in items {
            var kind: ThreadDetailRow.Kind
            var member = false
            var summary: ThreadExecutionSummary?
            var final = false
            switch item.body {
            case let .user(input):
                if agentDetail && (!input.followUp || item.delegated) { continue }
                kind = item.delegated ? .work : agentDetail ? .steer : .user
                member = item.delegated
            case let .reply(text, phase, anchor):
                guard phase != .streaming, threadHasText(text) else {
                    runStart = nil
                    tailIsWork = false
                    continue
                }
                final = !item.delegated && finals.contains(anchor)
                if phase == .failed && agentDetail { kind = .attention }
                else if agentDetail && (target == anchor || active && !item.delegated) || final && !waiting { kind = .content }
                else { kind = .work }
                member = kind == .work && (agentDetail || item.delegated)
            case let .reasoning(_, hasContent):
                kind = .work
                member = true
                summary = .init(reasoningSegments: hasContent ? 1 : 0, hasContent: hasContent)
            case let .activity(activity):
                kind = .work
                member = true
                summary = .init(toolCalls: activity.countsAsTool ? 1 : 0, hasContent: activity.hasContent)
            case .notice:
                if agentDetail { continue }
                kind = .work
            case .compaction, .resolution: kind = .work
            case .request: kind = .attention
            case .error: kind = agentDetail || !completed ? .attention : .work
            case .review: kind = .content
            }
            switch item.body {
            case .reasoning, .activity: tailIsWork = true
            default: tailIsWork = false
            }
            if !member { runStart = nil }
            else if runStart == nil { runStart = item.id }
            rows.append(Row(item: item, kind: kind, execution: runStart.map { .source(startID: $0) },
                            summary: summary, finalReply: final))
        }
        self.rows = rows
        self.tailIsWork = tailIsWork
    }

    package func hasWork(reasoningTokens: Double? = nil) -> Bool {
        rows.contains { row in
            guard row.kind == .work else { return false }
            if case .reasoning = row.item.body, (reasoningTokens ?? 0) > 0 { return true }
            return !agentDetail || row.summary?.hasContent != false
        }
    }

    @MainActor package func detailRows(executionID: JSONText, workVisible: Bool, active: Bool = false,
                                       actions: HarnessThreadActions, context: HarnessRenderContext,
                                       request: (JSONText) -> AnyView? = { _ in nil }) -> [ThreadDetailRow] {
        var result: [ThreadDetailRow] = []
        var index = 0
        while index < rows.count {
            let row = rows[index]
            index += 1
            if !workVisible && row.kind == .work { continue }
            if case .activity(let first) = row.item.body {
                var group = [first]
                while index < rows.count, rows[index].execution == row.execution,
                      case .activity(let next) = rows[index].item.body {
                    group.append(next)
                    index += 1
                }
                let id = JSONText(codeUnits: executionID.codeUnits + [58] + row.item.id.codeUnits + Array(":tools".utf16))
                result.append(.init(id: row.item.id, kind: .work,
                    node: AnyView(ThreadTranscriptActivities(activities: group, groupID: id)), execution: row.execution,
                    executionSummary: .init(toolCalls: group.filter(\.countsAsTool).count, hasContent: group.contains(where: \.hasContent))))
                continue
            }
            let node: AnyView
            if case let .request(id) = row.item.body {
                guard let panel = request(id) else { continue }
                node = panel
            } else {
                node = AnyView(ThreadTranscriptBody(item: row.item, active: active && tailIsWork && index == rows.count,
                                                    actions: actions, context: context))
            }
            result.append(.init(id: row.item.id, kind: row.kind, node: node, execution: row.execution,
                                executionSummary: row.summary, finalReply: row.finalReply))
        }
        return result
    }
}

package func threadRequestResolution(_ status: String) -> String {
    switch status {
    case "allowed": "已允许"
    case "denied": "已拒绝"
    case "submitted": "已提交"
    case "cancelled": "已取消"
    default: "已处理"
    }
}

package func threadExecutionStatus(_ status: PublicExecution.Status) -> String {
    switch status {
    case .running: "运行中"
    case .waitingForUser: "等待输入"
    case .completed: "已完成"
    case .failed: "失败"
    case .interrupted: "已取消"
    }
}
