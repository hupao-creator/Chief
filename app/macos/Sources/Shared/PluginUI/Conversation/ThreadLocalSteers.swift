import ChiefCore
import ChiefPluginAPI
import SwiftUI

/// Window-owned reading ink for the lifetime of a running execution. Only the
/// composer owns the command receipt, recovery decisions and durable input.
@MainActor @Observable
package final class ThreadLocalSteers {
    private var entries: [ApplicationExecutionRef: [ThreadTranscriptItem]] = [:]

    package init() {}

    package func capture(_ submission: NativeComposerSubmission, in execution: ApplicationExecutionRef) {
        let id = JSONText("steer:" + submission.commandID)
        guard entries[execution]?.contains(where: { $0.id == id }) != true else { return }
        let parts = submission.input["parts"]?.arrayValue ?? []
        let text = parts.compactMap { part in
            part["text"]?.stringValue ?? part["name"]?.stringValue.map { "@" + $0 }
        }.joined(separator: "\n")
        let attachments = submission.attachments.map { ThreadMessageAttachment(id: $0.id, label: $0.name.string) }
        let input = ThreadTranscriptInput(text, followUp: true, createdAt: Date().timeIntervalSince1970 * 1000,
                                         attachments: attachments)
        entries[execution, default: []].append(.init(id, .user(input)))
    }

    package func remove(_ commandID: String, from execution: ApplicationExecutionRef) {
        entries[execution]?.removeAll { $0.id == JSONText("steer:" + commandID) }
        if entries[execution]?.isEmpty == true { entries.removeValue(forKey: execution) }
    }

    package func retainRunning(_ isRunning: (ApplicationExecutionRef) -> Bool) {
        for execution in entries.keys where !isRunning(execution) { entries.removeValue(forKey: execution) }
    }

    func transcript(_ items: [ThreadTranscriptItem], in execution: ApplicationExecutionRef) -> [ThreadTranscriptItem] {
        guard let local = entries[execution] else { return items }
        // A retained occurrence owns chronology. Preserve the captured user's
        // ink and time across the handoff, including while the receipt is held.
        let byID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        var seen = Set<JSONText>()
        var result = items.map { item in
            guard !item.delegated, case .user(let input) = item.body, input.followUp,
                  let captured = byID[item.id] else { return item }
            seen.insert(item.id)
            return captured
        }
        result.append(contentsOf: local.filter { !seen.contains($0.id) })
        return result
    }
}

package extension EnvironmentValues {
    @Entry var threadLocalSteers: ThreadLocalSteers? = nil
    @Entry var steerThreadID: JSONText? = nil
}

package struct ThreadSteerReader: DynamicProperty {
    @Environment(\.threadLocalSteers) private var steers
    @Environment(\.steerThreadID) private var threadID
    package init() {}

    @MainActor package func transcript(_ items: [ThreadTranscriptItem], execution: JSONText) -> [ThreadTranscriptItem] {
        guard let threadID, let steers else { return items }
        return steers.transcript(items, in: .init(thread: .init(threadID: threadID, typeID: "agent"), executionID: execution))
    }
}
