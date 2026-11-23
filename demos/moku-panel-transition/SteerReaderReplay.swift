import AppKit
import CryptoKit
import ChiefCore
import ChiefHarnessCodex
import ChiefPluginAPI
import ChiefSidecardConversation
@testable import ChiefPluginUI
@testable import ChiefUI
import SwiftUI
import Vision

private struct ReplayError: Error, CustomStringConvertible { let description: String }

@MainActor @Observable final class SteerReaderFixture {
    var thread: HarnessThread
    var includesLocalInput = true
    var reduceMotion = false
    let steers: ThreadLocalSteers
    init(thread: HarnessThread, steers: ThreadLocalSteers) { self.thread = thread; self.steers = steers }
}

struct SteerReader: View {
    let fixture: SteerReaderFixture
    var body: some View {
        CodexThreadView(input: .init(thread: fixture.thread),
            actions: .init(interrupt: {}, respond: { _ in }, invokeHarnessExtension: { _, _ in .null },
                forkThread: { _ in "" }, openExternal: { _ in }, openFollowUp: { _ in }),
            context: .init(content: .row("turn:E"), presentation: .execution("E"),
                contentResource: { _ in fatalError("Unexpected resource request") }, onIndexChange: { _ in }))
            .environment(\.threadLocalSteers, fixture.includesLocalInput ? fixture.steers : nil)
            .environment(\.steerThreadID, fixture.thread.id)
            .environment(\._accessibilityReduceMotion, fixture.reduceMotion)
            .environment(\.locale, Locale(identifier: "en-US"))
            .frame(width: 620, height: 440)
    }
}

struct ReaderFrame: Equatable {
    let labels: [String]
    let pixels: SHA256.Digest
}

@MainActor func readerFrame(_ view: NSView, saveTo url: URL? = nil, onCapture: () -> Void = {}) throws -> ReaderFrame {
    view.displayIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw ReplayError(description: "Missing mounted reader bitmap")
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let image = bitmap.cgImage else { throw ReplayError(description: "Missing reader pixels") }
    onCapture()
    if let url { try bitmap.representation(using: .png, properties: [:])?.write(to: url) }
    let request = VNRecognizeTextRequest()
    request.recognitionLanguages = ["en-US"]
    request.minimumTextHeight = 0.005
    try VNImageRequestHandler(cgImage: image).perform([request])
    guard let data = bitmap.bitmapData else { throw ReplayError(description: "Missing bitmap data") }
    let pixels = SHA256.hash(data: Data(bytes: data, count: bitmap.bytesPerRow * bitmap.pixelsHigh))
    return ReaderFrame(labels: (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }, pixels: pixels)
}

@MainActor func checkSteerReader(workspace: NativeWorkspaceModel, mode: (String) throws -> Void) async throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let text = "Repeat this instruction"
    let source = ApplicationThreadRef(threadID: "steer-reader", typeID: "agent")
    func thread(_ state: String, id: JSONText, moku: Bool = false) throws -> HarnessThread {
        try HarnessThread(id: id, harnessID: "codex", revision: 1,
            sessionState: JSONValue(data: Data(contentsOf: root.appendingPathComponent("steer-" + state + ".json"))),
            observation: .init(latestExecution: .init(executionID: "E", status: .running, startedAt: 1)),
            cwd: "/fixture", settings: .object([:]), createdAt: 1, updatedAt: 2, title: "Active reader", tags: [],
            moku: moku ? true : nil, transcript: moku ? .array([]) : nil)
    }
    let current = try thread("initial", id: source.threadID)
    let other = try thread("initial", id: "another-thread")
    let chief = try thread("initial", id: "chief", moku: true)
    var archiveRecord = other.json.objectValue!
    archiveRecord["id"] = .text("retained-chief")
    archiveRecord["mokuHistory"] = .bool(true)
    archiveRecord["archived"] = .bool(true)
    let archive = try HarnessThread(json: .object(archiveRecord))
    let snapshot = JSONValue.object(["revision": .integer(3), "settingsRevision": .integer(0),
        "defaultCwd": .text("/fixture"), "executions": .array([]), "settings": .object([:]),
        "threads": .array([current.json, other.json, chief.json, archive.json]), "applicationThreads": .array([])])
    await workspace.installPrepared(snapshot, event: .snapshot(snapshot, authority: UUID()))
    for id in [chief.id, archive.id] {
        try workspace.preferences.selectThread(id.string)
        let restored = NativeWorkspacePresentation(workspace: workspace)
        guard restored.selected == nil, workspace.preferences.selectedThreadID == nil,
              workspace.catalog.thread(id) != nil else { throw ReplayError(description: "Failed to retire saved Chief route") }
    }
    let presentation = NativeWorkspacePresentation(workspace: workspace)
    func open(_ id: JSONText) {
        presentation.open(.init(threadID: id, typeID: "agent"))
        presentation.updateAgentInput(owner: UUID(), target: .init(threadID: id, requestID: nil, executionID: nil,
            followsLatest: true, ready: true), route: presentation.navigationRouteID)
    }
    open(source.threadID)
    let services = presentation.sidecardServices()
    var config = NativeSidecardWorkspaceConfiguration(input: .init(thread: current), executionDisabled: false,
        suppressed: false, locale: Locale(identifier: "en"))
    let cards = NativeSidecardWorkspaceModel(harnessHost: workspace.harnessHost,
        registry: try SidecardPluginRegistry([AnySidecardPlugin(NativeConversationSidecard())]),
        configuration: config, services: services, onBack: {}, onVisibilityChange: { _ in })
    defer { cards.release() }
    func reconcileCards() {
        config.executionReveal = presentation.threadExecutionReveal
        cards.update(configuration: config, services: services, onBack: {}, onVisibilityChange: { _ in })
    }
    let fixture = SteerReaderFixture(thread: current, steers: presentation.localSteers)
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.finishLaunching()
    NativeTypography.registerFonts()
    let view = NSHostingView(rootView: SteerReader(fixture: fixture))
    let panel = NSPanel(contentRect: .init(x: -2000, y: -2000, width: 620, height: 440),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.contentView = view
    panel.orderBack(nil)
    defer { panel.orderOut(nil); panel.contentView = nil }

    func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw ReplayError(description: message) }
    }
    func rendered(_ count: Int, matching expected: String = "Repeat this instruction") async throws -> ReaderFrame {
        let deadline = ContinuousClock.now + .seconds(3)
        var labels: [String] = []
        repeat {
            try await Task.sleep(for: .milliseconds(20))
            view.layoutSubtreeIfNeeded()
            let frame = try readerFrame(view)
            labels = frame.labels
            if labels.filter({ $0 == expected }).count == count && !labels.isEmpty { return frame }
        } while ContinuousClock.now < deadline
        throw ReplayError(description: "Expected \(count) mounted steer rows; got \(labels)")
    }

    func waitForHandler(_ value: String, count: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while try String(contentsOf: root.appendingPathComponent("handler-calls.jsonl"), encoding: .utf8)
            .components(separatedBy: value).count - 1 != count {
            try check(ContinuousClock.now < deadline, "Command never reached the held Go peer")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    for (index, step) in ["event first", "receipt first", "reject", "retry after switch"].enumerated() {
        fixture.reduceMotion = step == "receipt first"
        cards.receiveIndex(.init(executionIDs: index == 0 ? ["E"] : ["earlier", "E"], hasInheritedHistory: false))
        await Task.yield()
        let draft = presentation.dockDraft
        let route = presentation.navigationRouteID
        if step != "retry after switch" { draft.inputText = text }
        try check(draft.inputText == text && draft.canSubmit, "Retry lost the restored draft")
        try mode("hold")
        let send = Task.immediate {
            await draft.submit({ try await presentation.sendThread($0, to: source.threadID, route: route) }, optimisticallyClear: true)
        }
        reconcileCards()
        let inMain = index == 0
        try check(cards.snapshot?.selected == (inMain ? nil : "conversation") &&
                  cards.snapshot?.excludedExecutionIDs == (inMain ? [] : ["E"]),
                  "Steer replaced the current reader with an empty sidecard")
        let count = min(index + 1, 3)
        // With normal motion, compare receipt/content pixels at the settled pose.
        // Reduced motion must present that pose on the initial capture.
        if !fixture.reduceMotion {
            try await Task.sleep(for: .seconds(NativeReadingPageTiming.duration))
        }
        let local = try await rendered(count)
        let times = local.labels.filter { $0 != text }
        try check(times.count == count && times.allSatisfy { $0.contains(":") && $0.first?.isNumber == true },
                  "Ordinary steer should show only text and time: " + local.labels.description)
        try check(draft.submitting && draft.inputText.isEmpty, "Steer waited for receipt")
        try await waitForHandler(text, count: index + 1)
        if step == "event first" {
            fixture.thread = try thread("steer-reader-next", id: source.threadID)
            try check(try await rendered(count) == local && draft.submitting, "Early event changed the steer presentation")
        }
        if step == "retry after switch" {
            open(other.id)
            fixture.thread = other
            _ = try await rendered(0)
        }
        try mode(step == "reject" ? "direct-reject" : "accepted")
        await send.value
        reconcileCards()
        if step == "reject" {
            _ = try await rendered(2)
            try check(draft.error != nil && draft.inputText == text, "Rejected steer left a row or lost its input")
        } else if step == "retry after switch" {
            _ = try await rendered(0)
            try check(presentation.dockThreadID == other.id && presentation.threadExecutionReveal == nil,
                      "Late receipt changed the selected thread")
            open(source.threadID)
            fixture.thread = try thread("steer-reader-next", id: source.threadID)
            _ = try await rendered(3)
        } else {
            try check(try await rendered(count) == local, "Receipt changed the ordinary user row")
            fixture.thread = try thread("steer-reader-next", id: source.threadID)
            try check(try await rendered(count) == local, "Canonical steer changed the ordinary user row")
        }
        if step != "reject" {
            // Exercise the authoritative reader on its own as well. A capture
            // that never received a matching native event cannot satisfy this.
            fixture.includesLocalInput = false
            _ = try await rendered(count)
            fixture.includesLocalInput = true
        }
        print("Verified mounted steer:", step)
    }
    let draft = presentation.dockDraft
    draft.inputText = text
    try mode("lose")
    await draft.submit({ submission in
        try await presentation.sendThread(submission, to: source.threadID, route: presentation.navigationRouteID)
    }, optimisticallyClear: true)
    try check(draft.hasTrackedReceipt && !draft.canSubmit && draft.error != nil, "Missing interrupted-send recovery")
    _ = try await rendered(3)
    try mode("accepted")
    let deadline = ContinuousClock.now + .seconds(4)
    while draft.hasTrackedReceipt {
        await draft.checkPendingReceipt()
        try check(ContinuousClock.now < deadline, "Original receipt did not settle")
        try await Task.sleep(for: .milliseconds(10))
    }
    fixture.thread = try thread("steer-reader-next", id: source.threadID)
    _ = try await rendered(4)
    try check(draft.inputText.isEmpty && !draft.hasInterruptedSend, "Receipt lookup altered the successor draft")
    print("Verified late canonical steer after interrupted-send recovery")

    for id in [chief.id, archive.id] {
        let ref = ApplicationThreadRef(threadID: id, typeID: "agent")
        presentation.open(ref, target: .init(executionID: "E", requestID: "linked", mode: .history, position: .executionStart))
        try check(presentation.selected == source, "A Chief execution link replaced the ordinary reader")
    }
}
