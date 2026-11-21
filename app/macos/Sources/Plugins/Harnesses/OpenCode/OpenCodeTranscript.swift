import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI

extension OpenCodeMessage {
    var isReaderReply: Bool {
        role == "assistant" && status != "streaming" && status != "failed" && raw["isError"] != .bool(true) && threadHasText(text)
    }
}

func ocTranscript(_ messages: [OpenCodeMessage], sessionID: JSONText?, execution: PublicExecution? = nil, presence: ThreadExecutionPresence) -> [ThreadTranscriptItem] {
    let tools = Dictionary(uniqueKeysWithValues: messages.filter { $0.role == "tool" }.map { ($0.id, $0) })
    let placed = Set(messages.flatMap { message in
        message.parts.filter { $0["type"] == .text("tool") }.map { ocJoinedID([message.id, ":tool:", $0.ocID("toolCallId")]) }
    })
    var rendered = Set<JSONText>()
    var result: [ThreadTranscriptItem] = []
    func appendTool(_ tool: OpenCodeMessage) {
        guard rendered.insert(tool.id).inserted else { return }
        let status = tool.raw["isError"] == .bool(true) ? "failed" : tool.status == "streaming" ? "running" : tool.status ?? "completed"
        result.append(.init(tool.id, .activity(.init(id: tool.id, label: tool.raw["toolName"]?.stringValue ?? "",
            status: status, input: tool.toolDisplay("arguments")?.string, detail: tool.toolDisplay("result")?.string))))
    }
    for message in messages {
        let child = message.nativeSessionID != nil && sessionID != nil && message.nativeSessionID != sessionID
        switch message.role {
        case "user":
            guard message.raw["presentation"] != .text("internal") else { continue }
            let attachments = (message.raw["attachments"]?.arrayValue ?? []).enumerated().map { index, entry in
                ThreadMessageAttachment(id: ocJoinedID([message.id, JSONText(":attachment:\(index)")]),
                                        label: entry["name"]?.stringValue ?? "", title: entry["mimeType"]?.stringValue)
            }
            result.append(.init(message.id, .user(.init(message.text, followUp: message.isSteer, createdAt: message.raw["createdAt"]?.numberValue,
                annotations: (message.raw["annotations"]?.arrayValue ?? []).map(ThreadMessageAnnotation.init(json:)), attachments: attachments)), delegated: child))
        case "tool":
            if !placed.contains(message.id) { appendTool(message) }
        case "assistant":
            let phase = ThreadTranscriptPhase(status: message.status, failed: message.raw["isError"] == .bool(true))
            let anchor = ocMessageAnchor(message)
            var hasText = false
            if message.parts.isEmpty {
                hasText = threadHasText(message.text)
                result.append(.init(message.id, .reply(message.text, phase: phase, anchor: anchor), delegated: child))
            }
            for part in message.parts {
                let type = part["type"]?.stringValue ?? ""
                if type == "tool" {
                    if let tool = tools[ocJoinedID([message.id, ":tool:", part.ocID("toolCallId")])] { appendTool(tool) }
                    continue
                }
                let ordinal = part["ordinal"]?.intValue ?? 0
                let id = ocJoinedID([message.id, JSONText(":\(type):\(ordinal)")])
                let text = part["text"]?.stringValue ?? ""
                if type == "reasoning" {
                    let content = threadHasText(text) || presence.contains(message.id, "parts:reasoning:\(ordinal)")
                    result.append(.init(id, .reasoning(text, hasContent: content), delegated: child))
                } else if type == "text" {
                    hasText = hasText || threadHasText(text)
                    result.append(.init(id, .reply(text, phase: phase, anchor: anchor), delegated: child))
                }
            }
            if phase == .failed, message.raw["replyError"] != nil || !hasText && (child || execution?.error == nil) {
                result.append(.init(ocJoinedID([message.id, ":assistant-error"]), .error(message.raw["replyError"]?.stringValue ?? "")))
            }
        default: continue
        }
    }
    if let execution, execution.status == .failed, let error = execution.error,
       !messages.contains(where: { $0.role == "assistant" && ($0.nativeSessionID == nil || $0.nativeSessionID == sessionID) && $0.raw["replyError"] == .string(error) }) {
        result.append(.init(ocJoinedID([execution.executionID, ":error"]), .error(error.string)))
    }
    return result
}
