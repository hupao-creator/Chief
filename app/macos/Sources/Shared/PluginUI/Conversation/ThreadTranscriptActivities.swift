import ChiefCore
import SwiftUI

struct ThreadTranscriptActivities: View {
    let activities: [ThreadTranscriptActivity]
    let groupID: JSONText
    var body: some View {
        let summary = threadActivitySummary(activities)
        HarnessToolActivityGroup(groupID: groupID,
            items: activities.map { activity in ThreadActivitySlot(id: activity.id,
                node: AnyView(ThreadTranscriptActivityRow(activity: activity)), running: activity.status == "running") },
            summary: AnyView(Text(summary.text)), summaryLabel: summary.fullText,
            summaryState: state, defaultExpanded: true)
    }
    private var state: AnyView {
        if activities.contains(where: { $0.status == "running" }) { return AnyView(NativeStatusSpinner(size: 11)) }
        let name = activities.contains(where: { $0.status == "failed" }) ? "CircleAlert"
            : activities.contains(where: { $0.status == "cancelled" }) ? "Circle" : "Check"
        return AnyView(NativeIcon(name: name, size: 13))
    }
}

private struct ThreadTranscriptActivityRow: View {
    let activity: ThreadTranscriptActivity
    @Environment(\.locale) private var locale
    var body: some View {
        ThreadActivityRow(id: activity.id, state: state,
            label: AnyView(Text((activity.label.isEmpty ? NativePluginLocalization.localize("工具", locale: locale) : activity.label) + (activity.status == "failed" ? " · " + NativePluginLocalization.localize("失败", locale: locale) : ""))),
            detail: activity.input == nil && activity.detail == nil ? nil : AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    if let input = activity.input {
                        Text(NativePluginLocalization.localize("输入", locale: locale)).foregroundStyle(NativePalette.thread.muted.swiftUI)
                        Text(input)
                    }
                    if let detail = activity.detail {
                        if activity.input != nil { Text(NativePluginLocalization.localize("输出", locale: locale)).foregroundStyle(NativePalette.thread.muted.swiftUI) }
                        Text(detail)
                    }
                }.font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)))
    }
    private var state: AnyView {
        if activity.status == "running" { return AnyView(NativeStatusSpinner(size: 11)) }
        let name = activity.status == "failed" ? "CircleAlert" : ["command": "Terminal", "file": "FilePenLine", "search": "Search", "agent": "Bot", "subagent": "Bot", "review": "GitPullRequest"][activity.kind] ?? "Wrench"
        return AnyView(NativeIcon(name: name, size: 14))
    }
}

private func threadActivitySummary(_ activities: [ThreadTranscriptActivity]) -> (text: String, fullText: String) {
    var order: [String] = []; var counts: [String: Int] = [:]
    var filePaths: Set<JSONText> = []
    var unknownFileChanges = false
    for activity in activities {
        let kind = ["file", "command", "search"].contains(activity.kind) ? activity.kind : "other"
        if counts[kind] == nil { order.append(kind) }
        if kind == "file" {
            if let paths = activity.filePaths { filePaths.formUnion(paths) }
            else { unknownFileChanges = true }
            counts[kind] = filePaths.count
        } else { counts[kind, default: 0] += 1 }
    }
    let labels = order.enumerated().map { index, kind in
        let count = counts[kind]!
        let text: String
        switch kind {
        case "file": text = unknownFileChanges ? "Changed files" : "Touched \(count) \(count == 1 ? "file" : "files")"
        case "command": text = "Ran \(count) \(count == 1 ? "command" : "commands")"
        case "search": text = "Searched \(count) \(count == 1 ? "time" : "times")"
        default: text = "Used \(count) \(count == 1 ? "tool" : "tools")"
        }
        return index == 0 ? text : text.prefix(1).lowercased() + text.dropFirst()
    }
    let text = labels.count <= 1 ? labels.first ?? "" : labels.count == 2 ? labels.joined(separator: " and ") : labels.dropLast().joined(separator: ", ") + ", and " + labels.last!
    let statuses = [("running", "running"), ("failed", "failed"), ("cancelled", "stopped")].compactMap { status, label -> String? in
        let count = activities.filter { $0.status == status }.count
        return count > 0 ? "\(count) \(label)" : nil
    }
    return (text, statuses.isEmpty ? text : text + " · " + statuses.joined(separator: " · "))
}
