import AppKit
@testable import ChiefApplications
import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
@testable import ChiefUI
import SwiftUI

@MainActor @Observable private final class ReportDestination {
    var hasContent = false
}

private struct ReportSendSurface: View {
    let presentation: NativeWorkspacePresentation
    let props: ApplicationThreadProps<NativeReportView>
    let route: UUID
    let onSend: () -> Void

    var body: some View {
        if presentation.selected == props.entry.ref {
            VStack(alignment: .trailing, spacing: 0) {
                NativeReportDetail(props: props)
                    .environment(\.nativeReportSidecards, presentation.reportSidecards)
                    .onPreferenceChange(NativeReportExecutionInputKey.self) { input in
                        presentation.updateReportExecution(input?.reference, ready: input?.ready == true, onBack: nil, route: route)
                    }
                NativeMokuComposerInput(draft: presentation.dockDraft, submissionPending: presentation.dockDraft.submitting, targetsThread: true,
                    automaticFocus: false, running: presentation.dockThread?.cancellationID != nil, onSend: onSend)
                    .frame(width: 600)
                    .background(.background)
            }
        } else {
            Text("Another conversation")
        }
    }
}

@MainActor private func editableText(in view: NSView) -> NSTextView? {
    if let text = view as? NSTextView, text.isEditable { return text }
    for child in view.subviews {
        if let text = editableText(in: child) { return text }
    }
    return nil
}

/// Mount the Report renderer with a finished source and a Go-reduced Codex
/// destination. Document HTML and execution catalog delivery are fixture inputs.
@MainActor private func reportProps(report: ApplicationThreadRef, source: ApplicationExecutionRef,
                                    reader: SteerReaderFixture, destination: ReportDestination, cards: NativeReportSidecardPresentation)
throws -> ApplicationThreadProps<NativeReportView> {
    let documentVisit = UUID()
    let capabilities = try ApplicationCapabilityAccess<ApplicationRendererPhase>(scope: .init(pluginID: "report", thread: report),
        requires: [ApplicationCapabilities.isolatedHTML.requirement, ApplicationCapabilities.executionReferencesUI.requirement],
        registrations: [
            .init(ApplicationCapabilities.isolatedHTML, value: ApplicationIsolatedHTML { html, _ in
                Text("Report document").preference(key: NativeApplicationHTMLReadinessKey.self,
                    value: .init(source: html, thread: report, generation: documentVisit, ready: true))
            }),
            .init(ApplicationCapabilities.executionReferencesUI, value: ApplicationExecutionReferencesUI(read: { refs in
                refs.map { .init(reference: $0, title: "Result", emoji: nil, missing: false, running: false, harness: nil, preview: nil) }
            }, subscribe: { _, _ in {} }, logo: { _, _ in AnyView(EmptyView()) }, execution: { ref in
                let visit = cards.executionVisit
                if ref != source && !destination.hasContent { return AnyView(Color.clear) }
                let content = ref == source ? AnyView(Text("Previous result").nativeReadingContentReady())
                    : AnyView(SteerReader(fixture: reader).nativeReadingContentReady())
                return AnyView(content.onAppear { cards.updateInput(ref, ready: true, visit: visit) })
            }))
        ])
    let view = try NativeReportView(json: .object(["emoji": .text("📄"), "shortDescription": .text("Report"),
        "previewText": .text("Report"), "readingSeconds": .integer(1), "contentRevision": .text("1"),
        "relatedExecutions": .array([.object(["thread": source.thread.json, "executionId": .string(source.executionID)])])]))
    return .init(entry: .init(ref: report, revision: 1, createdAt: 1, updatedAt: 1, title: "Report", archived: false,
        tags: .init(tags: [], semanticTags: [], directoryTags: [], tagEmojis: [:]), presentations: [], view: view),
        context: .init(theme: .light, locale: "en-US", lifetime: PluginLifetime(),
            domain: .init(pluginID: "report", invoke: { _, _, _, _, _ in
                .object(["reportId": .string(report.threadID), "revision": .integer(1), "items": .array([])])
            }), capabilities: capabilities, openThread: { _, _ in }, openExecution: { _ in }))
}

@MainActor func checkReportSend(workspace: NativeWorkspaceModel, mode: (String) throws -> Void) async throws {
    let src = ApplicationExecutionRef(thread: .init(threadID: "report-agent", typeID: "agent"), executionID: "current")
    let report = ApplicationThreadRef(threadID: "report", typeID: "report.document")
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let state = try JSONValue(data: Data(contentsOf: root.appendingPathComponent("steer-working.json")))
    func thread(_ harness: JSONText, active: Bool) throws -> HarnessThread {
        try HarnessThread(id: src.thread.threadID, harnessID: harness, revision: 1, sessionState: active ? state : .object([:]),
            observation: .init(latestExecution: .init(executionID: active ? "E" : src.executionID,
                status: active ? .running : .completed, startedAt: 1, finishedAt: active ? nil : 2)),
            cwd: "/fixture", settings: .object([:]), createdAt: 1, updatedAt: 2, title: "Report source", tags: [])
    }
    func install(_ item: HarnessThread) throws {
        try workspace.catalog.install(.object(["revision": .integer(3), "settingsRevision": .integer(0),
            "defaultCwd": .text("/fixture"), "executions": .array([]), "settings": .object([:]),
            "threads": .array([item.json]), "applicationThreads": .array([])]))
    }
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.finishLaunching()
    NativeTypography.registerFonts()
    let active = try thread("codex", active: true)
    for step in ["accept", "reject", "leave"] {
        let previous = try thread(step == "reject" ? "claude" : "codex", active: false)
        try install(previous)
        let presentation = NativeWorkspacePresentation(workspace: workspace)
        presentation.open(report)
        let route = presentation.navigationRouteID, cards = presentation.reportSidecards
        cards.selectExecution(src)
        let destination = ReportDestination()
        let props = try reportProps(report: report, source: src,
            reader: .init(thread: active, steers: presentation.localSteers), destination: destination, cards: cards)
        var sends = 0
        var sending: Task<Void, Never>?
        let surface = ReportSendSurface(presentation: presentation, props: props, route: route) {
            sends += 1
            let draft = presentation.dockDraft
            sending = Task.immediate {
                await draft.submit({ try await presentation.sendThread($0, to: src.thread.threadID,
                    from: src.executionID, route: route) }, optimisticallyClear: true)
            }
        }
        let view = NSHostingView(rootView: surface.frame(width: 1240, height: 560)
            .environment(\.locale, Locale(identifier: "en-US")))
        let panel = NSPanel(contentRect: .init(x: -2000, y: -2000, width: 1240, height: 560),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = view; panel.orderBack(nil)
        defer { panel.orderOut(nil); panel.contentView = nil }
        let deadline = ContinuousClock.now + .seconds(6)
        while presentation.dockExecution != src || !presentation.dockInputAvailable {
            try require(ContinuousClock.now < deadline, "Report composer did not mount")
            try await Task.sleep(for: .milliseconds(20))
        }
        let harness = step == "reject" ? "Claude" : "Codex"
        let expected = "Connecting to " + harness
        let draft = presentation.dockDraft, prompt = "Report " + step
        try mode("hold")
        guard let editor = editableText(in: view), panel.makeFirstResponder(editor),
              let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                  windowNumber: panel.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                  isARepeat: false, keyCode: 36) else { throw PluginContractError("Missing Report editor") }
        editor.selectAll(nil)
        editor.insertText(prompt, replacementRange: editor.selectedRange())
        let evidence = ProcessInfo.processInfo.environment["CHIEF_REPORT_REPLAY_EVIDENCE"].map { URL(fileURLWithPath: $0) }
        var start = ContinuousClock.now
        func sample(_ stage: String) throws -> [String] {
            view.layoutSubtreeIfNeeded()
            var captured = ContinuousClock.now
            let labels = try readerFrame(view, saveTo: evidence?.appendingPathComponent(step + "-" + stage + ".png")) {
                captured = .now
            }.labels
            print("Report", step, stage, start.duration(to: captured), labels)
            return labels
        }
        func observe(_ expected: String, stage: String) async throws {
            let deadline = ContinuousClock.now + .seconds(3)
            repeat {
                try await Task.sleep(for: .milliseconds(16))
                if try sample(stage).contains(expected) { return }
            } while ContinuousClock.now < deadline
            throw PluginContractError("Missing Report pixels: " + expected)
        }
        try await observe("Previous result", stage: "source")
        try require(try sample("source").contains(prompt), "Source frame did not show the submitted input")
        start = .now
        editor.keyDown(with: enter)
        try require(draft.inputText.isEmpty && draft.submitting && cards.connectingHarness == harness,
            "Return cleared the editor without publishing the connection")
        try await observe(expected, stage: "held")
        try require(cards.selectedExecution == src && presentation.dockThread?.cancellationID == nil
            && draft.submitting && draft.inputText.isEmpty && editor.string.isEmpty,
            "Connection feedback changed execution authority or retained the submitted text")
        editor.insertText("next", replacementRange: editor.selectedRange())
        editor.keyDown(with: enter)
        try require(sends == 1 && draft.text == "next", "Duplicate Return sent or consumed the next draft")
        if step == "leave" {
            presentation.open(src.thread)
            try await observe("Another conversation", stage: "left")
        }
        try await Task.sleep(until: start + .milliseconds(900), clock: .continuous)
        try mode(step == "reject" ? "direct-reject" : "accepted")
        print("Report", step, "peer released", start.duration(to: .now))
        await sending?.value
        if step == "accept" {
            try require(cards.selectedExecution?.executionID == "E" && !cards.executionReady, "Receipt bypassed reader readiness")
            try await observe(expected, stage: "awaiting-reader")
            try install(active)
            destination.hasContent = true
            try await observe("Processing request", stage: "accepted")
            try require(cards.selectedExecution?.executionID == "E" && draft.text == "next", "Wrong accepted execution or draft")
        } else if step == "reject" {
            try require(draft.error != nil && draft.text == prompt + "\n\nnext" && cards.selectedExecution == src,
                "Rejection lost the source or its draft")
        } else {
            try require(presentation.selected == src.thread && cards.selectedExecution == nil, "Late receipt navigated after leaving")
        }
        try await Task.sleep(for: .milliseconds(40))
        try require(try !sample("settled").contains(expected), "Retired feedback remained visible")
        if step == "accept" {
            cards.selectExecution(src)
            try await observe("next", stage: "source-draft")
            try require(presentation.dockExecution == src && presentation.dockDraft.text == "next",
                "Returning to the source lost the next draft")
        }
    }
}
