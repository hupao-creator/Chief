import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI

extension PiMessage {
    func replyPhase(_ execution: PublicExecution.Status) -> ThreadTranscriptPhase {
        // A retained partial message in an older Pi snapshot inherits settlement
        // from its own execution. Keep its text and terminal diagnostic reachable.
        if status == "streaming" && execution != .running && execution != .waitingForUser {
            return execution == .failed ? .failed : .settled
        }
        return .init(status: status?.string)
    }

    func isReaderReply(_ execution: PublicExecution.Status) -> Bool {
        role == "assistant" && replyPhase(execution) == .settled && threadHasText(text.string)
    }
}

func piTranscript(_ messages: [PiMessage], execution: PublicExecution, presence: ThreadExecutionPresence) -> [ThreadTranscriptItem] {
    var tools: [JSONText: PiMessage] = [:]
    var referenced = Set<JSONText>()
    for message in messages {
        if let call = message.toolCallID { tools[call] = message }
        for block in message.contentOrder { if let call = block.callID { referenced.insert(call) } }
    }
    var items: [ThreadTranscriptItem] = []
    var shown = Set<JSONText>()
    func appendTool(_ message: PiMessage) {
        guard shown.insert(message.id).inserted else { return }
        if message.toolCallID == nil, ["Pi notify", "Pi setStatus", "Pi setWidget", "Pi setTitle", "Pi set_editor_text"].contains(message.toolName?.string ?? "") {
            if threadHasText(message.text.string) {
                items.append(.init(message.id, message.isError ? .error(message.text.string) : .notice(message.text.string)))
            }
            return
        }
        let active = execution.status == .running || execution.status == .waitingForUser
        let status = message.isError ? "failed" : message.status == "streaming" && !active ? "cancelled" : message.status?.string ?? "completed"
        items.append(.init(message.id, .activity(.init(id: message.id, label: message.toolName?.string ?? "", status: status,
            input: message.raw["toolInput"]?.stringValue, detail: message.text.codeUnits.isEmpty ? nil : message.text.string,
            countsAsTool: message.toolCallID != nil))))
    }
    for message in messages {
        switch message.role {
        case "user":
            guard message.raw["presentation"] != .text("internal") else { continue }
            items.append(.init(message.id, .user(.init(message.text.string, followUp: message.isSteer, createdAt: message.createdAt,
                annotations: message.annotations.map(ThreadMessageAnnotation.init(json:))))))
        case "tool":
            if message.toolCallID.map(referenced.contains) != true { appendTool(message) }
        case "assistant":
            let phase = message.replyPhase(execution.status)
            if message.contentOrder.isEmpty {
                let thinking = message.thinking?.string ?? ""
                if threadHasText(thinking) || presence.contains(message.id, "thinking") {
                    items.append(.init(JSONText(codeUnits: message.id.codeUnits + Array(":thinking".utf16)), .reasoning(thinking, hasContent: true)))
                }
                if !message.text.codeUnits.isEmpty || phase == .streaming && thinking.isEmpty {
                    items.append(.init(message.id, .reply(message.text.string, phase: phase, anchor: message.id)))
                }
                continue
            }
            var firstText = true
            for (index, block) in message.contentOrder.enumerated() {
                let id = JSONText(codeUnits: message.id.codeUnits + Array(":\(block.kind.string):\(index)".utf16))
                if let call = block.callID {
                    if let tool = tools[call] { appendTool(tool) }
                } else if block.kind == "thinking" {
                    items.append(.init(id, .reasoning(block.text, hasContent: block.hasContent)))
                } else {
                    let anchored = firstText && threadHasText(block.text)
                    let text = index > 0 && message.contentOrder[index - 1].kind == "text" ? "\n" + block.text : block.text
                    items.append(.init(anchored ? message.id : id, .reply(text, phase: phase, anchor: message.id)))
                    if anchored { firstText = false }
                }
            }
        default: continue
        }
    }
    if execution.status == .failed, let error = execution.error, !error.codeUnits.isEmpty {
        items.append(.init(JSONText(codeUnits: execution.executionID.codeUnits + Array(":error".utf16)), .error(error.string)))
    }
    return items
}
