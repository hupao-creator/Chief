import ChiefCore
import ChiefPluginAPI
import Foundation

/// Public audit data only. A tool result acknowledges delivery; its arguments
/// retain the exact text. Identity includes the owner and execution, not text.
public struct NativeMokuTalkMessage: Equatable, Sendable, Identifiable {
    public static let maximumCodePoints = 1024

    public let id: JSONText
    public let text: String
    let content: NativeMokuTalkText
    public let dispatch: NativeMokuDispatch?

    public init(id: JSONText, text: String, dispatch: NativeMokuDispatch? = nil) {
        self.id = id; self.text = text; self.dispatch = dispatch
        content = NativeMokuTalkText(text)
    }

    public static func latest(in thread: HarnessThread?) -> Self? {
        guard let thread, thread.moku == true, let execution = thread.observation.latestExecution else { return nil }
        for item in (thread.transcript?.arrayValue ?? []).reversed() where item["executionId"] == .string(execution.executionID) {
            if let message = project(item, thread: thread, execution: execution) { return message }
        }
        return nil
    }

    private static func project(_ item: JSONValue, thread: HarnessThread, execution: PublicExecution) -> Self? {
        guard item["type"]?.stringValue == "tool-operation",
              case .string(let operationID) = item["id"], !operationID.codeUnits.isEmpty,
              case .string(let executionID) = item["executionId"] else { return nil }
        let key = [thread.id, thread.harnessID, executionID, operationID].flatMap {
            Array("\($0.codeUnits.count):".utf16) + $0.codeUnits
        }
        let active = executionID == execution.executionID && (execution.status == .running || execution.status == .waitingForUser)
        if let dispatch = NativeMokuDispatch(operation: item, executionIsActive: active) {
            return Self(id: JSONText(codeUnits: key), text: dispatch.sentence(chinese: true), dispatch: dispatch)
        }
        guard item["name"]?.stringValue == "talk", item["completedAt"]?.numberValue != nil, item["isError"]?.boolValue != true,
              item["result"]?["ok"]?.boolValue != false, case .string(let text) = item["arguments"]?["text"], text.string.unicodeScalars.count <= maximumCodePoints,
              !text.codeUnits.contains(0), text.codeUnits.contains(where: { !whitespace($0) }) else { return nil }
        return Self(id: JSONText(codeUnits: key), text: text.string)
    }

    private static func whitespace(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x0009...0x000D, 0x0020, 0x0085, 0x00A0, 0x1680, 0x2000...0x200A,
             0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
        default: false
        }
    }
}

/// Talk is literal text with one inline link format. Leave unsupported markup
/// and malformed destinations visible, including their original punctuation.
struct NativeMokuTalkText: Equatable, Sendable {
    enum Part: Equatable, Sendable {
        case text(String)
        case link(label: String?, url: URL, reference: ApplicationExecutionRef)
    }
    let parts: [Part]
    var hasLinks: Bool { parts.contains { if case .link = $0 { true } else { false } } }

    private static let links = try! NSRegularExpression(
        pattern: #"\[([^\]\n]+)\]\(((?:chief|mokusei)://[^\s()]+)\)|(?:chief|mokusei)://[^\s<>()\[\]"“”‘’（），。！？；、：《》「」『』【】,;]+"#,
        options: .caseInsensitive)

    init(_ source: String) {
        guard source.contains("://") else { parts = []; return }
        var output = [Part]()
        var start = source.startIndex
        for match in Self.links.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard let range = Range(match.range, in: source) else { continue }
            let label = Range(match.range(at: 1), in: source)
            let urlRange = Range(match.range(at: 2), in: source) ?? range
            var end = urlRange.upperBound
            if label == nil {
                while end > urlRange.lowerBound, ".,;:!?".contains(source[source.index(before: end)]) {
                    end = source.index(before: end)
                }
            }
            let destination = source[urlRange.lowerBound..<end]
            guard let url = URL(string: String(destination), encodingInvalidCharacters: false),
                  let reference = ApplicationExecutionLink.parse(url) else { continue }
            if start < range.lowerBound { output.append(.text(String(source[start..<range.lowerBound]))) }
            output.append(.link(label: label.map { String(source[$0]) }, url: url, reference: reference))
            start = label == nil ? end : range.upperBound
        }
        if start < source.endIndex { output.append(.text(String(source[start...]))) }
        parts = output
    }
}

/// Window-owned latest-only delivery. Hiding a presented message consumes it;
/// a new message received while input/another surface owns the Dock waits.
/// Mounting, reconnecting and replaying an older audit item cannot resurrect it.
public struct NativeMokuTalkState: Equatable {
    public private(set) var message: NativeMokuTalkMessage?
    public private(set) var presented = false
    public private(set) var deadline: ContinuousClock.Instant?
    private var latest: NativeMokuTalkMessage?
    private var seen: Set<JSONText> = []
    private var order: [JSONText] = []

    public init() {}

    public mutating func receive(_ next: NativeMokuTalkMessage?) {
        guard latest != next else { return }
        // A result updates the same audit operation in place. Preserve its
        // presentation lease and never resurrect an explicitly dismissed call.
        if let next, latest?.id == next.id {
            latest = next
            if message?.id == next.id { message = next }
            return
        }
        latest = next
        presented = false
        deadline = nil
        guard let next, !seen.contains(next.id) else { message = nil; return }
        seen.insert(next.id); order.append(next.id)
        if order.count > 256 { seen.remove(order.removeFirst()) }
        message = next
    }

    public mutating func setPresented(_ value: Bool, now: ContinuousClock.Instant = .now) {
        if !value, presented { dismiss() }
        presented = value && message != nil
        // Start only on actual presentation. Same-operation result updates and
        // repeated view callbacks must retain the original lease.
        if presented, deadline == nil {
            deadline = now.advanced(by: .seconds(message?.dispatch != nil ? 10 : 60))
        }
    }

    public mutating func expire(id: JSONText, deadline: ContinuousClock.Instant, now: ContinuousClock.Instant = .now) {
        guard message?.id == id, self.deadline == deadline, now >= deadline else { return }
        dismiss()
    }

    public mutating func dismiss() { message = nil; presented = false; deadline = nil }
}
