import AppKit
@testable import ChiefCore
import ChiefPluginAPI
@testable import ChiefPluginUI
import ChiefUI
import ScreenCaptureKit
import SwiftUI
import Vision

// New mounts subscribe through the production offline store. Existing mounts
// receive the same scoped projections as updates, without starting a daemon.
private extension RuntimeClient {
    func publish(_ sample: JSONValue, thread: JSONText) throws {
        let key = JSONText(sample["rowKey"]!.stringValue!)
        try offlineStore.saveContent(sample["thread"]!, thread: thread, scope: .thread)
        try offlineStore.saveContent(sample["turn"]!, thread: thread, scope: .turn(key: key))
        try offlineStore.saveContent(sample["execution"]!, thread: thread, scope: .execution(key: key))
        for (id, resource) in contentResources where resource.threadID == thread {
            if let value = offlineStore.content(thread: thread, scope: resource.scope) {
                emit(.threadContent(subscriptionId: id, state: .ready(value)))
            }
        }
    }
}

@MainActor @Observable private final class ReaderVisit {
    let chief: Bool
    let client: RuntimeClient
    let plugins: NativePluginComposition
    let controls = NativeReadingInteractions()
    let draft = NativeComposerDraft(services: .init(stageFiles: { _, _ in [] }, discardAttachments: { _ in }))
    var visit = UUID()
    var thread: HarnessThread
    var target: HarnessReadingTarget?
    var sent: [String] = []
    @ObservationIgnored lazy var host = NativeHarnessHost(client: client, registry: plugins.harnesses,
        currentThread: { [weak self] id in self?.thread.id == id ? self?.thread : nil },
        callbacks: .init(openExternal: { _ in }, openFollowUp: { _, _ in }, onError: { _ in }))
    @ObservationIgnored var feed: Task<Void, Never>?
    let panel = NSPanel(contentRect: .init(x: 50, y: 50, width: 960, height: 780),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

    init(chief: Bool, harness: String, directory: URL, plugins: NativePluginComposition) throws {
        self.chief = chief
        self.plugins = plugins
        let id: JSONText = chief ? "chief" : "agent"
        let profile = directory.appendingPathComponent(harness + "-" + id.string)
        client = RuntimeClient(profile: try RuntimeProfile(dataDirectory: profile))
        var operations: [JSONValue] = []
        if chief && harness == "codex" {
            operations.append(.object(["type": .text("tool-operation"), "name": .text("create_thread"),
                "id": .text("operation"), "executionId": .text("run"), "callId": .text("audit"), "harnessCallId": .text("dispatch"),
                "arguments": .object(["target": .object(["codex": .object([:])]), "prompt": .text("Child task")]),
                "createdAt": .integer(2), "completedAt": .integer(3),
                "result": .object(["ok": .bool(true), "threadId": .text("child")])]))
        }
        thread = try HarnessThread(id: id, harnessID: JSONText(harness), revision: 0, sessionState: .null,
            observation: .init(), cwd: "/fixture", settings: .object([:]), createdAt: 1, updatedAt: 1,
            title: chief ? "Moku" : "Replay task", tags: [], moku: chief ? true : nil,
            transcript: chief ? .array(operations) : nil)
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.level = .init(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
    }

    func updateCatalog(_ sample: JSONValue, archived: Bool = false) throws {
        var envelope = thread.json.objectValue!
        envelope["observation"] = sample["observation"]
        envelope["revision"] = .integer(thread.revision + 1)
        if archived && chief {
            envelope["moku"] = nil
            envelope["archived"] = .bool(true)
            envelope["mokuHistory"] = .bool(true)
            envelope["title"] = .text("Moku history · " + thread.harnessID.string)
        }
        thread = try HarnessThread(json: .object(envelope))
    }

    func open() async {
        visit = UUID()
        let events = await client.events()
        feed = Task {
            for await event in events { host.receive(event) }
        }
        panel.contentView = NSHostingView(rootView: ReaderSurface(model: self))
        panel.orderBack(nil)
    }

    func close() {
        panel.orderOut(nil)
        panel.contentView = nil
        feed?.cancel()
    }

    var descriptors: [JSONValue] { controls.snapshot(visit: visit) }
    func control(_ role: String) -> JSONValue? { descriptors.first { $0["role"] == .text(role) } }

    func toggleWork() throws {
        guard let button = control("visibility.work"), let id = button["id"]?.stringValue,
              let handle = button["handle"]?.stringValue else { throw Mismatch("Missing work control") }
        try controls.perform(id: id, handle: handle, operation: "activate", value: .null, visit: visit)
    }

    var markdown: [MarkdownTextView] {
        // AppKit can reorder siblings when an editor takes focus. Use the
        // displayed paragraph order in bottom-up window coordinates.
        textViews(panel.contentView!).compactMap { $0 as? MarkdownTextView }.sorted {
            $0.convert($0.bounds, to: nil).midY > $1.convert($1.bounds, to: nil).midY
        }
    }

    func frame() async throws -> CGImage {
        guard let window = try await SCShareableContent.currentProcess.windows.first(where: { $0.windowID == CGWindowID(panel.windowNumber) }) else {
            throw Mismatch("Missing replay window")
        }
        let config = SCStreamConfiguration()
        config.width = Int(panel.frame.width * 2)
        config.height = Int(panel.frame.height * 2)
        config.ignoreShadowsSingleWindow = true
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
    }

    func readFrame(_ stage: String) async throws -> [(String, CGRect)] {
        let image = try await frame()
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("evidence")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let filename = "\(thread.harnessID.string)-\(thread.id.string)-\(stage).png"
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent(filename))
        let request = VNRecognizeTextRequest()
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.006
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { line in
            line.topCandidates(1).first.map { ($0.string, line.boundingBox) }
        }
    }

    func sampleSummary(_ bounds: CGRect) async throws -> [Int] {
        var previous: [UInt8]?
        var changes: [Int] = []
        for _ in 0..<9 {
            let image = try await frame()
            let rect = CGRect(x: bounds.minX * CGFloat(image.width), y: (1 - bounds.maxY) * CGFloat(image.height),
                width: bounds.width * CGFloat(image.width), height: bounds.height * CGFloat(image.height)).integral
            guard let crop = image.cropping(to: rect),
                  let buffer = CGContext(data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8,
                    bytesPerRow: crop.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
                  let data = buffer.data else { throw Mismatch("Missing summary pixels") }
            buffer.draw(crop, in: CGRect(origin: .zero, size: rect.size))
            let pixels = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: crop.width * crop.height))
            if let previous {
                changes.append(zip(previous, pixels).filter { abs(Int($0) - Int($1)) > 6 }.count)
            }
            previous = pixels
            try await Task.sleep(for: .milliseconds(100))
        }
        return changes
    }

    func wait(_ reason: String, until predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        repeat {
            try await Task.sleep(for: .milliseconds(25))
            panel.contentView?.layoutSubtreeIfNeeded()
            if predicate() { return }
        } while ContinuousClock.now < deadline
        let turn = try (control("turn")?["value"] ?? .null).encodedData()
        throw Mismatch("\(thread.harnessID.string)/\(thread.id.string) \(reason). Markdown \(markdown.map(\.string)), " +
            "turn \(String(decoding: turn, as: UTF8.self)), controls \(descriptors.compactMap { $0["role"]?.stringValue })")
    }
}

private struct ReaderSurface: View {
    let model: ReaderVisit
    var body: some View {
        Group {
            if model.thread.moku == true {
                NativeMokuThreadView(harnessHost: model.host, thread: model.thread, draft: model.draft,
                    readingTarget: model.target, onNavigationChange: { _ in }, onBack: {},
                    onSend: { model.sent.append($0.text) }, onCancel: {})
            } else {
                NativeAgentThreadWorkspace(harnessHost: model.host, thread: model.thread, registry: model.plugins.sidecards,
                    readingTarget: model.target, services: .init(send: { _, _ in throw Mismatch("Unexpected Agent send") },
                        stageAttachments: { _ in [] }, discardAttachments: { _ in }, openExternal: { _ in }),
                    onBack: {}, onNavigationChange: { _ in })
            }
        }
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.scenePhase, .active)
        .environment(\.nativeReadingInteractions, model.controls)
        .environment(\.nativeReadingInteractionVisit, model.visit)
        .environment(\.nativeReadingInteractionRefresh, model.controls.refresh)
    }
}

@MainActor func replayConversationReaders(harness: String, directory: URL, plugins: NativePluginComposition) async throws -> [[String: Any]] {
    let agent = try ReaderVisit(chief: false, harness: harness, directory: directory, plugins: plugins)
    let chief = try ReaderVisit(chief: true, harness: harness, directory: directory, plugins: plugins)
    let pair = [agent, chief]
    defer { for reader in pair { reader.close() } }
    var evidence: [[String: Any]] = []
    func update(_ stage: String, archived: Bool = false) async throws {
        let file = directory.appendingPathComponent("\(harness)-\(stage).json")
        let sample = try JSONValue(data: Data(contentsOf: file))
        for reader in pair {
            try reader.updateCatalog(sample, archived: archived)
            try await reader.client.publish(sample, thread: reader.thread.id)
        }
    }
    func check(_ stage: String, paragraphs: [String], work: Bool, filter: Bool, status: String) async throws {
        var snapshots: [JSONValue] = []
        var sweep: [String: [Int]] = [:]
        for reader in pair {
            try await reader.wait(stage) {
                guard let state = reader.control("turn")?["value"]?["status"]?.stringValue else { return false }
                let matchesStatus = status == "Running"
                    ? !["Completed", "Failed", "Waiting for input", "Cancelled"].contains(state)
                    : state == status
                return reader.markdown.map(\.string) == paragraphs && matchesStatus &&
                    reader.control("turn")?["value"]?["work"] == .bool(work) &&
                    (reader.control("visibility.work") != nil) == filter
            }
        }
        for reader in pair where reader.control("visibility.userMessages") != nil {
            throw Mismatch("\(harness)/\(stage) user-message switch: Agent \(agent.control("visibility.userMessages") != nil), Chief \(chief.control("visibility.userMessages") != nil)")
        }
        // A ready document registers its rows before the shared 200ms ink
        // entrance ends. Read the settled text, then sample its own sweep.
        try await Task.sleep(for: .milliseconds(300))
        for reader in pair {
            let lines = try await reader.readFrame(stage)
            let labels = lines.map(\.0)
            if labels.contains(where: { $0.contains("Retry once") }) != (status == "Running") {
                throw Mismatch("\(harness)/\(stage): unexpected live follow-up on \(reader.thread.id.string): \(labels)")
            }
            // Vision can read the leading wrench and separator dots as punctuation.
            // Compare the caption itself and retain each original frame as evidence.
            let summaries = labels.compactMap { line -> String? in
                guard let start = line.range(of: "Execution process") else { return nil }
                return line[start.lowerBound...].components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { !$0.isEmpty }.joined(separator: " ")
            }
            guard reader.control("execution.load") == nil, reader.control("execution.group") == nil,
                  !labels.contains(where: { $0.contains("create_thread") || $0.contains("tool diagnostic") }) else {
                throw Mismatch("\(harness)/\(stage): exposed tool members on \(reader.thread.id.string)")
            }
            if work {
                let toolCount = harness == "codex" && stage != "dispatch" ? "2 tool calls" : "1 tool call"
                guard summaries.count == 1, summaries[0].contains(toolCount),
                      summaries[0].contains("1 reasoning segment") else { throw Mismatch("\(stage): unexpected summaries \(summaries), frame text \(labels)") }
            } else if !summaries.isEmpty { throw Mismatch("\(stage): exposed collapsed summary \(summaries)") }
            if stage == "failed", labels.filter({ $0.contains("independent failure") }).count != 1 {
                throw Mismatch("\(stage): failure must appear once, got \(labels)")
            }
            if harness == "codex", ["work", "stream", "expanded"].contains(stage),
               let line = lines.first(where: { $0.0.contains("Execution process") }) {
                let changes = try await reader.sampleSummary(line.1)
                guard changes.contains(where: { $0 > 0 }) == (stage == "work") else {
                    throw Mismatch("\(stage): unexpected summary motion on \(reader.thread.id.string): \(changes)")
                }
                sweep[reader.thread.id.string] = changes
            }
            // Vision can split the date, clock, count and unit into separate boxes.
            // Compare complete visible captions, joining neighbours on the same baseline.
            var captions: [(String, CGRect)] = []
            for (text, box) in lines.sorted(by: { $0.1.minX < $1.1.minX }) {
                if let index = captions.lastIndex(where: { _, previous in
                    abs(box.midY - previous.midY) < min(box.height, previous.height) / 2 &&
                        box.midX > previous.maxX && abs(box.minX - previous.maxX) < previous.height
                }) {
                    captions[index] = (captions[index].0 + " " + text, captions[index].1.union(box))
                } else {
                    captions.append((text, box))
                }
            }
            let footer = captions.sorted { $0.1.midY > $1.1.midY }.map(\.0).filter {
                $0.range(of: #"\d{4}/\d{2}/\d{2}"#, options: .regularExpression) != nil ||
                    $0.contains(" tokens") && !$0.contains("Execution process") || $0.contains("Worked for")
            }
            if harness == "codex", stage != "retained" {
                guard reader.control("turn.author")?["value"]?["model"] == .text("fixture-model") else { throw Mismatch("Missing runtime model") }
                if status == "Completed" || status == "Failed" {
                    guard footer.contains(where: { $0.contains("148 tokens") }) else { throw Mismatch("Missing reported usage in \(labels)") }
                } else if status == "Running", footer.contains(where: { $0.contains("148 tokens") }) {
                    throw Mismatch("Terminal usage appeared during \(stage)")
                }
            }
            let fonts = reader.markdown.map { view -> JSONValue in
                var runs: [JSONValue] = []
                view.textStorage?.enumerateAttribute(.font, in: NSRange(location: 0, length: view.string.utf16.count)) { font, range, _ in
                    if let font = font as? NSFont {
                        runs.append(.text("\(range.location)+\(range.length) \(font.fontName) \(font.pointSize)"))
                    }
                }
                return .array(runs)
            }
            var geometry: [JSONValue] = []
            if stage == "done" {
                for view in reader.markdown {
                    let rect = view.convert(view.bounds, to: nil)
                    geometry.append(.object(["top": .number((reader.panel.frame.height - rect.maxY).rounded()),
                        "width": .number(rect.width.rounded()), "height": .number(rect.height.rounded())]))
                }
            }
            snapshots.append(.object([
                "turn": reader.control("turn")?["value"] ?? .null, "author": reader.control("turn.author")?["value"] ?? .null,
                "summary": .array(summaries.map(JSONValue.text)), "footer": .array(footer.map(JSONValue.text)),
                "fonts": .array(fonts), "paragraphFrames": .array(geometry), "markdown": .array(paragraphs.map(JSONValue.text))
            ]))
        }
        if snapshots[0] != snapshots[1] {
            let values = try snapshots.map { String(decoding: try $0.encodedData(), as: UTF8.self) }
            throw Mismatch("\(harness)/\(stage) Agent \(values[0]), Chief \(values[1])")
        }
        evidence.append(["harness": harness, "stage": stage, "surfaces": ["Agent", chief.thread.mokuHistory ? "Chief archive" : "Chief history"],
                         "reading": try JSONSerialization.jsonObject(with: snapshots[0].encodedData()), "summaryPixelChanges": sweep])
    }

    let final = ["Result", "Use café."]
    try await update(harness == "codex" ? "dispatch" : "work")
    for reader in pair { await reader.open() }
    if harness == "codex" {
        guard NativeOverviewMokuOperation.project(transcript: chief.thread.transcript) == [
            .init(id: "operation", kind: .start, phase: .completed, threadID: "child")
        ] else { throw Mismatch("Lost the admitted child Thread reference") }
        try await check("dispatch", paragraphs: ["First note"], work: true, filter: false, status: "Running")
        try await update("work")
    }
    try await check("work", paragraphs: ["First note"], work: true, filter: false, status: "Running")
    guard let editor = textViews(chief.panel.contentView!).first(where: \.isEditable),
          chief.panel.makeFirstResponder(editor) else { throw Mismatch("Chief editor could not take focus") }
    editor.insertText("next @draft", replacementRange: editor.selectedRange())
    editor.setSelectedRange(NSRange(location: 5, length: 6))
    try await update("stream")
    try await check("stream", paragraphs: ["First note"], work: true, filter: false, status: "Running")
    try await update("reply")
    try await check("reply", paragraphs: ["First note"] + final, work: true, filter: false, status: "Running")
    if harness == "codex" {
        // The catalog can announce settlement before the scoped document. The
        // already settled Markdown remains readable between those deliveries.
        let done = try JSONValue(data: Data(contentsOf: directory.appendingPathComponent("codex-done.json")))
        for reader in pair { try reader.updateCatalog(done) }
        try await check("catalog settled", paragraphs: ["First note"] + final, work: false, filter: true, status: "Running")
    }
    try await update("done")
    try await check("done", paragraphs: final, work: false, filter: true, status: "Completed")
    guard chief.panel.firstResponder === editor, chief.draft.text == "next @draft",
          editor.selectedRange() == NSRange(location: 5, length: 6) else { throw Mismatch("Settlement replaced the focused Chief draft") }
    for reader in pair { try reader.toggleWork() }
    try await check("expanded", paragraphs: final, work: true, filter: true, status: "Completed")
    for reader in pair { reader.close() }
    try await update("reopen")
    for reader in pair { await reader.open() }
    try await check("reopen", paragraphs: final, work: false, filter: true, status: "Completed")
    if harness == "codex" {
        for reader in pair {
            reader.target = .init(executionID: "run", requestID: "visit-first", mode: .current,
                message: .object(["executionId": .text("run"), "itemId": .text("m1")]))
            try await reader.wait("locate earlier reply") { reader.control("timeline")?["value"]?["locatedRequestId"] == .text("visit-first") }
        }
        try await check("linked", paragraphs: ["First note"] + final, work: false, filter: true, status: "Completed")
        guard let reopened = textViews(chief.panel.contentView!).first(where: \.isEditable),
              chief.panel.makeFirstResponder(reopened), reopened.string == "next @draft" else { throw Mismatch("Lost current Chief draft on reopen") }
        let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: chief.panel.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36)!
        reopened.keyDown(with: enter)
        try await chief.wait("send current Chief draft") { chief.sent == ["next @draft"] && chief.draft.text.isEmpty }
        for reader in pair { reader.target = nil }
    }
    try await update("reply")
    try await check("running before failure", paragraphs: ["First note"] + final, work: true, filter: false, status: "Running")
    try await update("waiting")
    // Pi and OpenCode continue to identify the waiting execution as active.
    try await check("waiting", paragraphs: ["First note"] + final, work: ["pi", "opencode"].contains(harness), filter: true, status: "Waiting for input")
    try await update("failed")
    try await check("failed", paragraphs: final, work: false, filter: true, status: "Failed")
    for reader in pair { reader.close() }
    try await update("reopen", archived: true)
    for reader in pair { await reader.open() }
    try await check("archived", paragraphs: final, work: false, filter: true, status: "Completed")
    guard !textViews(chief.panel.contentView!).contains(where: \.isEditable) else { throw Mismatch("Archive mounted an editable composer") }
    try await update("retained")
    try await check("retained", paragraphs: ["Saved answer."], work: false, filter: harness == "opencode", status: "Completed")
    for reader in pair { await reader.client.close() }
    return evidence
}
