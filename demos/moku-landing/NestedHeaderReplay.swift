import AppKit
import ScreenCaptureKit
import SwiftUI
import Vision
import ChiefApplications
@testable import ChiefCore
import ChiefHarnessCodex
import ChiefPluginAPI
@testable import ChiefPluginUI
@testable import ChiefUI

private struct ReplayError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

// Deliver a window-local wheel sample directly to the mounted event monitor.
private final class WheelSample: NSEvent {
    let target: NSWindow
    let point: CGPoint
    let x, y: CGFloat
    let precise: Bool
    let direct, momentum: NSEvent.Phase
    init(window: NSWindow, point: CGPoint, x: CGFloat, y: CGFloat, precise: Bool = true,
         phase: NSEvent.Phase = .began, momentum: NSEvent.Phase = []) {
        target = window
        self.point = point
        self.x = x
        self.y = y
        self.precise = precise
        direct = phase
        self.momentum = momentum
        super.init()
    }
    required init?(coder: NSCoder) { nil }
    override var window: NSWindow? { target }
    override var locationInWindow: CGPoint { point }
    override var type: NSEvent.EventType { .scrollWheel }
    override var hasPreciseScrollingDeltas: Bool { precise }
    override var isDirectionInvertedFromDevice: Bool { true }
    override var scrollingDeltaX: CGFloat { x }
    override var scrollingDeltaY: CGFloat { y }
    override var phase: NSEvent.Phase { direct }
    override var momentumPhase: NSEvent.Phase { momentum }
    override var modifierFlags: NSEvent.ModifierFlags { [] }
    override var timestamp: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

@MainActor private final class ReminderReplayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor private final class SilentReminderBell: NativeMokuTimerPlaying {
    func startLoop() throws {}
    func stop() {}
}

@main @MainActor private struct NestedHeaderReplay: App {
    @State private var collectionViewport: CGSize?
    @State private var captureScheme: ColorScheme?
    @State private var brightCaptureBackdrop = false
    private let workspace: NativeWorkspaceModel
    private let presentation: NativeWorkspacePresentation

    init() { self.init(profile: nil) }

    private init(profile: URL?) {
        do {
            if profile == nil { try prepareIsolatedNativeReplay() }
            let liveProfile = CommandLine.arguments.firstIndex(of: "--live-conversation").map {
                URL(filePath: CommandLine.arguments[$0 + 1])
            }
            if let liveProfile, liveProfile.lastPathComponent != "profile" || !liveProfile.deletingLastPathComponent().lastPathComponent.hasPrefix("me2e-") {
                throw ReplayError("Expected a private e2e profile")
            }
            let directory = profile ?? liveProfile ?? URL(filePath: FileManager.default.currentDirectoryPath)
            let preferences = DesktopPreferences(directory: directory)
            try preferences.setOnboardingCompleted(true)
            let liveLocale: DesktopLocale = CommandLine.arguments.contains("--restart") ? .english : .chinese
            workspace = NativeWorkspaceModel(client: RuntimeClient(profile: try RuntimeProfile(dataDirectory: directory)),
                preferences: preferences, plugins: try .init(harnesses: [AnyHarnessPlugin(CodexHarnessPlugin())], sidecards: [], applications: NativeApplicationModules.make()),
                timer: NativeMokuTimerController(player: SilentReminderBell()), locale: liveProfile == nil ? .system : liveLocale)
            presentation = NativeWorkspacePresentation(workspace: workspace)
        } catch { fatalError(String(describing: error)) }
    }

    var body: some Scene {
        Window("Overview header replay", id: "header-replay") {
            GeometryReader { geometry in
                NativeWorkspaceView(model: workspace, presentation: presentation)
                    .frame(width: collectionViewport?.width ?? geometry.size.width,
                           height: collectionViewport?.height ?? geometry.size.height)
            }
            .background {
                // A single-window capture omits the desktop behind the material.
                if let captureScheme {
                    Color(white: captureScheme == .dark && !brightCaptureBackdrop ? 0.13 : 0.97)
                }
            }
            // Inspect mounted controls even when no system accessibility client is running.
            .environment(\.accessibilityEnabled, true)
            .preferredColorScheme(captureScheme)
            .modifier(NativeWorkspaceWindowSurface())
            .task {
                do { try await replay(); exit(0) }
                catch { print(error); exit(1) }
            }
        }
        .nativeWorkspaceWindowStyle().defaultSize(width: 860, height: 640)
        .restorationBehavior(.disabled)
    }

    private func installTasks(_ count: Int, revision: Int, authority: UUID, firstDirectoryCount: Int? = nil,
                              manyDirectories: Bool = false, firstTagCount: Int? = nil, reports: [JSONValue] = [], extraThreads: [JSONValue] = [],
                              noteText: String? = nil) async throws {
        let extra = manyDirectories ? (0..<12).map { "project-task-\($0)" } : []
        let ids = (0..<count).map { "task-\($0)" } + extra + ["moku"]
        let note = try ThreadNote(id: "fixture-note", text: JSONText(noteText ?? String(repeating: "A note paragraph.\n\n", count: 55)),
                                  revision: 1, updatedAt: 2)
        let threads = try ids.enumerated().map { index, id in
            let other = firstDirectoryCount.map { index >= $0 && id != "moku" } ?? false
            let directory: JSONText = index >= count && manyDirectories ? JSONText("Project \(index)") : (other ? "Other" : "Fixture")
            let scope: JSONText = index >= count && manyDirectories ? JSONText("/fixture/\(index)") : (other ? "/other" : "/fixture")
            let tag: JSONText = firstTagCount.map { index >= $0 } == true ? "Review" : "Work"
            return try HarnessThread(id: JSONText(id), harnessID: "codex", revision: 0, sessionState: .null,
                observation: .init(), cwd: scope, settings: .object([:]), createdAt: 1, updatedAt: 2,
                title: JSONText(id), tags: [tag], moku: id == "moku" ? true : nil, note: (manyDirectories || noteText != nil) && id == "moku" ? note : nil, transcript: id == "moku" ? .array([]) : nil,
                tagEmojis: [tag: "📌"], directoryTag: directory, directoryScope: scope).json
        }
        let snapshot: JSONValue = .object(["revision": .integer(revision), "settingsRevision": .integer(0),
            "defaultCwd": .text("/fixture"), "settings": .object([:]), "threads": .array(threads + extraThreads),
            "executions": .array([]), "applicationThreads": .array(reports)])
        await workspace.installPrepared(snapshot, event: .snapshot(snapshot, authority: authority))
    }

    private func replay() async throws {
        if CommandLine.arguments.contains("--live-conversation") {
            try await liveConversation()
            return
        }
        let authority = UUID()
        let noteClickReplay = CommandLine.arguments.contains("--note-click")
        try await installTasks(18, revision: 1, authority: authority, manyDirectories: noteClickReplay)
        guard workspace.hasInitialContent, let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "header-replay" }),
              let screen = NSScreen.screens.first else { throw ReplayError("Workspace did not mount") }
        window.collectionBehavior = [.auxiliary, .canJoinAllSpaces]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        let directory = URL(filePath: FileManager.default.currentDirectoryPath).appending(path: "evidence")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if CommandLine.arguments.contains("--conversation-opening") {
            captureScheme = .dark
            window.setContentSize(CGSize(width: 1100, height: 800))
            window.center()
            try await focusReplayWindow(window)
            try await Task.sleep(for: .milliseconds(650))
            try await conversationOpening(window, directory: directory)
            return
        }
        if CommandLine.arguments.contains("--note-link") {
            window.center()
            try await focusReplayWindow(window)
            try await noteLinks(window, directory: directory, authority: authority)
            return
        }
        if CommandLine.arguments.contains("--status-only") || CommandLine.arguments.contains("--completed-card") {
            window.center()
            try await focusReplayWindow(window)
            try await statusFilters(window, directory: directory, authority: authority)
            return
        }
        if noteClickReplay {
            window.setContentSize(CGSize(width: 900, height: 680))
            window.center()
            try await focusReplayWindow(window)
            try await Task.sleep(for: .seconds(1))
            try await noteClicks(window, directory: directory)
            let reminderFixture = Self(profile: directory.appending(path: "reminder-profile"))
            try await reminderFixture.reminderSwipe(directory: directory)
            try await focusReplayWindow(window)
            try await cardInteraction(window, directory: directory, authority: authority)
            try await fittingCards(window, directory: directory, authority: authority)
            try await statusFilters(window, directory: directory, authority: authority)
            try await installTasks(0, revision: 18, authority: authority)
            try await Task.sleep(for: .milliseconds(800))
            guard presentation.moku.landing else { throw ReplayError("Empty Overview did not enter landing") }
            presentation.scene.setInputOpen(false)
            try await Task.sleep(for: .milliseconds(650))
            try await postScroll(window, CGPoint(x: 80, y: 120), y: 40, phase: .began)
            try await postScroll(window, CGPoint(x: 80, y: 120), y: 0, phase: .ended)
            guard !presentation.scene.notePanelOpen, let content = window.contentView,
                  let monitor = descendant(NativeOverviewScrollInput.MonitorView.self, in: content) else {
                throw ReplayError("Empty Overview background opened Note")
            }
            let bar = presentation.scene.capsuleFrame
            let eyes = monitor.windowPoint(CGPoint(x: bar.midX, y: bar.midY))
            try await postScroll(window, eyes, y: 40, phase: .began)
            try await postScroll(window, eyes, y: 0, phase: .ended)
            let generation = presentation.scene.noteOpenGeneration
            guard presentation.scene.conversationOpen, presentation.scene.inputOpen, !presentation.scene.notePanelOpen else {
                throw ReplayError("Landing Bar swipe did not open the conversation")
            }
            presentation.scene.setInputOpen(false)
            try await Task.sleep(for: .milliseconds(650))
            try await postClick(window, at: eyes, flags: .control)
            guard presentation.scene.notePanelOpen, presentation.scene.noteOpenGeneration == generation + 1,
                  !presentation.scene.inputOpen else { throw ReplayError("Control-click did not open Note directly on Landing") }
            try JSONSerialization.data(withJSONObject: ["controlClickOpenedNote": true, "swipeOpenedConversation": true])
                .write(to: directory.appending(path: "landing-note-click.json"))
            return
        }
        var records: [[String: Any]] = []
        let cases: [(CGSize, CGFloat, CGPoint, String)] = [
            (CGSize(width: 1100, height: 760), 16, CGPoint(x: 1061, y: 22), "wide"),
            (CGSize(width: 600, height: 480), 76, CGPoint(x: 565, y: 16), "narrow"),
        ]
        var previousOffset = 0.0
        for (size, filterTop, settingsProbe, captureName) in cases {
            window.setContentSize(size)
            window.setFrameTopLeftPoint(CGPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY + size.height / 2))
            try await Task.sleep(for: .seconds(2))
            let deadline = ContinuousClock.now + .seconds(4)
            while !presentation.canvas.canScroll || NSEvent.pressedMouseButtons != 0 {
                guard ContinuousClock.now < deadline else { throw ReplayError("Canvas did not admit wheel input at \(size)") }
                try await Task.sleep(for: .milliseconds(25))
            }
            let camera = presentation.canvas.camera
            let retained = camera.scrollOffset == min(previousOffset, camera.maximumOffset)
            var result = try inspect(window, filterTop: filterTop)
            result["retainedOffsetOnResize"] = retained
            result["passed"] = retained && result["passed"] as? Bool == true
            if CommandLine.arguments.contains("--capture") {
                try await capture(window, to: directory.appending(path: captureName + ".png"))
            }
            let opened = try await clickSettings(window, at: settingsProbe)
            result["settingsProbeFromTopLeft"] = [settingsProbe.x, settingsProbe.y]
            result["settingsOpened"] = opened
            result["passed"] = opened && result["passed"] as? Bool == true
            previousOffset = camera.scrollOffset
            records.append(result)
            if result["passed"] as? Bool != true { print("Failed geometry: \(result)") }
        }
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appending(path: "nested-header.json"))
        guard records.allSatisfy({ $0["passed"] as? Bool == true }) else { throw ReplayError("Nested header replay failed") }
        window.setContentSize(CGSize(width: 900, height: 680))
        try await Task.sleep(for: .seconds(1))
        try await focusReplayWindow(window)
        try await cardInteraction(window, directory: directory, authority: authority)
        try await fittingCards(window, directory: directory, authority: authority)
        try await fittingCollection(directory: directory, authority: authority)
    }

    private func liveConversation() async throws {
        struct Fixture: Decodable {
            let messages: [String]
            let attachment: String
            let draft: String
        }
        let profile = workspace.client.storageDirectory
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: profile.deletingLastPathComponent().appending(path: "conversation.json")))
        let restart = CommandLine.arguments.contains("--restart")
        let stage = restart ? "restart" : "send"
        let evidence = URL(filePath: FileManager.default.currentDirectoryPath).appending(path: "evidence")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        func wait(_ description: String, _ check: () -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(35)
            while !check() {
                guard ContinuousClock.now < deadline else { throw ReplayError(description) }
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "header-replay" }),
              let content = window.contentView else { throw ReplayError("Missing live replay window") }
        window.setContentSize(.init(width: 1100, height: 800))
        window.center()
        captureScheme = restart ? .light : .dark
        try await focusReplayWindow(window)
        workspace.start()
        let scene = presentation.scene
        try await wait("Live Chief did not mount") { workspace.runtimeAvailable && workspace.catalog.hasMoku && scene.capsuleFrame.width > 0 }
        try await Task.sleep(for: .milliseconds(750))
        guard let monitor = descendant(NativeOverviewScrollInput.MonitorView.self, in: content) else { throw ReplayError("Missing Bar event monitor") }
        func swipe() async throws {
            let eyePoint: CGPoint
            if scene.inputOpen {
                let bar = scene.capsuleFrame
                eyePoint = monitor.windowPoint(CGPoint(x: bar.minX + 32, y: bar.maxY - min(30, bar.height / 2)))
            } else {
                // A retained Talk can place the eyes beside selectable prose on restart.
                let button = window.convertFromScreen(try filterButton("moku-open-input", in: window).frame)
                eyePoint = CGPoint(x: button.midX, y: button.midY)
            }
            let pixel = window.convertToBacking(CGRect(origin: eyePoint, size: .zero))
            let point = window.convertFromBacking(CGRect(x: floor(pixel.minX) + 0.5, y: floor(pixel.minY) + 0.5, width: 0, height: 0)).origin
            try await postScroll(window, point, y: 36, phase: .began)
            try await postScroll(window, point, y: 0, phase: .ended)
            try await wait("Swipe did not open conversation") { scene.conversationOpen && scene.inputOpen && !scene.notePanelOpen }
        }
        func spokenRows() -> [String] {
            conversationElements(in: window).filter { $0.id == "moku-conversation-message" }.map { $0.label.isEmpty ? $0.value : $0.label }
        }
        func labels() -> [String] {
            spokenRows().map { $0.components(separatedBy: " — ")[0] }
        }
        let expected = fixture.messages.enumerated().map { index, text in
            (index == 0 || index == 2 ? workspace.locale.text("你, ", "You, ") : "Chief, ") + text + (index == 2 ? ", " + fixture.attachment : "")
        }
        try await swipe()
        let initial = restart ? expected : Array(expected.prefix(2))
        try await wait("Mounted history did not match expected rows") { labels() == initial }
        guard let field = descendant(NSTextView.self, in: content, matching: { $0.isEditable && !$0.isHiddenOrHasHiddenAncestor })
            else { throw ReplayError("Missing native composer") }
        try await wait("Swipe did not focus the native editor") { window.firstResponder === field }
        if !restart {
            field.insertText(fixture.messages[2], replacementRange: field.selectedRange())
            try await wait("Chief draft did not receive native text") { presentation.dockDraft.text == fixture.messages[2] }
            let selectedFile = profile.deletingLastPathComponent().appending(path: fixture.attachment)
            await presentation.dockDraft.importFiles([NativeComposerFile(url: selectedFile)])
            guard presentation.dockDraft.attachments.compactMap(\.attachment).map(\.name.string) == [fixture.attachment] else {
                throw ReplayError("The native composer could not stage its attachment: \(presentation.dockDraft.error ?? "missing attachment")")
            }
            try await pressKey("\r", code: 36, in: window)
            try await wait("No admitted message and Talk after Return") { labels() == expected && field.string.isEmpty && scene.conversationOpen }
            field.insertText(fixture.draft, replacementRange: field.selectedRange())
            try await wait("Next draft missing") { presentation.dockDraft.text == fixture.draft }
            try await postClick(window, at: monitor.windowPoint(CGPoint(x: 45, y: 85)))
            try await wait("Outside click did not close the panel") { !scene.conversationOpen }
            try await Task.sleep(for: .milliseconds(650))
            try await swipe()
            try await wait("Reopened history differs") { labels() == expected }
        }
        try await wait("Reopened composer did not restore the draft") {
            descendant(NSTextView.self, in: content, matching: { $0.isEditable && $0.string == fixture.draft }) != nil
        }
        try await Task.sleep(for: .milliseconds(500))
        try await capture(window, to: evidence.appending(path: "conversation-" + stage + ".png"))
        let elements = conversationElements(in: window)
        let periods = elements.filter { $0.id == "moku-conversation-period" }
        guard periods.count == 1, !elements.contains(where: {
            ($0.role == "AXStaticText" && [$0.label, $0.value].contains(workspace.locale.text("与 Chief 的对话", "Conversation with Chief")))
                || ($0.role == "AXButton" && $0.label == workspace.locale.text("关闭对话", "Close conversation"))
        }), spokenRows().allSatisfy({ $0.components(separatedBy: " — ").last?.contains(":") == true }) else {
            throw ReplayError("Unexpected date groups, heading, close control or accessible dates: \(elements)")
        }
        let bar = scene.capsuleFrame
        let point = monitor.windowPoint(CGPoint(x: bar.midX, y: bar.minY + bar.height * 0.4))
        let timeline = try await conversationScroller(in: content, at: point)
        var held: CGFloat = 0
        try await recordWindow(window, to: evidence.appending(path: "conversation-times-" + stage + ".mp4")) {
            try await Task.sleep(for: .milliseconds(300))
            held = try await revealTimes(window, at: point, timeline: timeline,
                                         captureTo: evidence.appending(path: "conversation-times-" + stage + ".png"))
            try await Task.sleep(for: .milliseconds(400))
        }
        var observed: [String: Any] = ["rows": labels(), "draft": presentation.dockDraft.text,
            "conversationOpen": scene.conversationOpen, "noteOpen": scene.notePanelOpen,
            "period": periods[0].value, "timestampsHeldPoints": held, "timestampsReleasedPoints": timeline.contentView.bounds.minX]
        func measure() throws -> [String: CGFloat] {
            let nodes = conversationElements(in: window)
            let rows = nodes.filter { $0.id == "moku-conversation-message" }.map(\.frame)
            guard rows.count == expected.count, let shell = nodes.first(where: { $0.id == "moku-capsule" })?.frame,
                  let editor = descendant(NSTextView.self, in: content, matching: { $0.isEditable && !$0.isHiddenOrHasHiddenAncestor }),
                  let editorScroll = editor.enclosingScrollView else { throw ReplayError("Missing mounted conversation geometry") }
            let editorFrame = window.convertToScreen(editorScroll.convert(editorScroll.bounds, to: nil))
            let list = window.convertToScreen(timeline.convert(timeline.bounds, to: nil))
            let bounds = window.convertToScreen(content.convert(content.bounds, to: nil))
            let distanceFromEnd = (timeline.documentView?.bounds.maxY ?? 0) - timeline.documentVisibleRect.maxY
            guard bounds.contains(shell), shell.insetBy(dx: -1, dy: -1).contains(editorFrame),
                  list.minY >= editorFrame.maxY - 1, let last = rows.last, last.height > 20, last.minY >= list.minY - 1,
                  distanceFromEnd < 2,
                  rows.allSatisfy({ $0.minX >= shell.minX + 10 && $0.maxX <= shell.maxX - 10 }) else {
                throw ReplayError("Bubble or composer outside its available space, end distance \(distanceFromEnd): \(bounds), \(shell), \(list), \(editorFrame), \(rows)")
            }
            return ["windowWidth": bounds.width, "windowHeight": bounds.height, "panelHeight": shell.height,
                    "listHeight": list.height, "editorHeight": editorFrame.height, "attachmentBubbleHeight": rows[2].height,
                    "speakerChangeGap": rows[2].minY - rows[3].maxY, "sameSpeakerGap": rows[3].minY - rows[4].maxY,
                    "distanceFromEnd": max(0, distanceFromEnd)]
        }
        observed["regular"] = try measure()
        window.setContentSize(NativeGeometry.minimumWindow)
        try await wait("Workspace did not resize to its minimum window") { content.bounds.size == NativeGeometry.minimumWindow }
        try await Task.sleep(for: .milliseconds(450))
        observed["small"] = try measure()
        try await capture(window, to: evidence.appending(path: "conversation-small-" + stage + ".png"))

        guard let editor = descendant(NSTextView.self, in: content, matching: { $0.isEditable && !$0.isHiddenOrHasHiddenAncestor })
            else { throw ReplayError("Missing resized composer") }
        let extraLines = "\n再看一下换行。\n然后检查附件。\n最后核对输入框。"
        editor.insertText(extraLines, replacementRange: NSRange(location: (editor.string as NSString).length, length: 0))
        try await wait("Multiline Chinese draft did not reach the compact window") { presentation.dockDraft.text == fixture.draft + extraLines }
        try await Task.sleep(for: .milliseconds(450))
        observed["smallMultiline"] = try measure()
        let compactCapture = evidence.appending(path: "conversation-small-multiline-" + stage + ".png")
        try await capture(window, to: compactCapture)
        let visibleText = try recognizedLines(in: compactCapture, languages: ["zh-Hans", "en-US"]).map(\.text).joined()
            .filter { !$0.isWhitespace }
        guard visibleText.contains("两处都已核对"), visibleText.contains("最后核对输入框") else {
            throw ReplayError("Last reply or last draft line missing from the compact window capture: \(visibleText)")
        }
        let scrollPoint = timeline.convert(CGPoint(x: timeline.bounds.midX, y: timeline.bounds.midY), to: nil)
        let y = timeline.contentView.bounds.minY
        try await postScroll(window, scrollPoint, y: y > 5 ? 80 : -80, phase: .began)
        try await postScroll(window, scrollPoint, y: 0, phase: .ended)
        guard abs(timeline.contentView.bounds.minY - y) > 1, editor.string == fixture.draft + extraLines else {
            throw ReplayError("History did not scroll independently of the multiline editor")
        }
        editor.insertText(fixture.draft, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        try await pressKey("\u{1b}", code: 53, in: window)
        try await wait("Escape did not close the headerless conversation") { !scene.conversationOpen }
        guard presentation.dockDraft.text == fixture.draft else { throw ReplayError("Escape discarded the draft") }
        try JSONSerialization.data(withJSONObject: observed, options: [.prettyPrinted, .sortedKeys])
            .write(to: evidence.appending(path: "conversation-" + stage + ".json"))
    }

    private func conversationOpening(_ window: NSWindow, directory: URL) async throws {
        guard let content = window.contentView,
              let monitor = descendant(NativeOverviewScrollInput.MonitorView.self, in: content) else {
            throw ReplayError("Missing mounted Overview scroll input")
        }
        let scene = presentation.scene
        let client = workspace.client
        let scope = RuntimeContentScope.mokuConversation(before: nil)
        let cache = RuntimeOfflineStore(storageDirectory: client.storageDirectory, hostID: nil)
        let ending = "End of Chief reply"
        func row(_ index: Int, _ text: String) -> JSONValue {
            .object(["id": .text("opening-\(index)"), "text": .text(text),
                     "createdAt": .integer(1_786_000_000_000 + index * 60_000),
                     "role": .text(index.isMultiple(of: 2) ? "user" : "chief")])
        }
        let paragraph = "The current checklist includes the release notes, a review of the changes, and the remaining checks."
        let rows = (0..<31).map { i in
            row(i, "Message \(i)\n" + Array(repeating: paragraph, count: 1 + (i % 5)).joined(separator: "\n"))
        } + [row(31, Array(repeating: paragraph, count: 15).joined(separator: "\n") + "\n" + ending)]
        let page = JSONValue.object(["messages": .array(rows)])
        try cache.saveContent(page, thread: "moku", scope: scope)
        func subscription() async throws -> String {
            let resources = await client.contentResources
            guard let resource = resources.first(where: { $0.value.threadID == "moku" && $0.value.scope == scope }) else {
                throw ReplayError("No conversation subscription")
            }
            return resource.key
        }
        func barPoint() -> CGPoint {
            let frame = scene.capsuleFrame
            let x = scene.inputOpen ? frame.minX + 32 : frame.midX
            return monitor.windowPoint(CGPoint(x: x, y: frame.maxY - 22))
        }
        func open() async throws {
            let point = barPoint()
            try await postScroll(window, point, y: 42, phase: .began)
            try await postScroll(window, point, y: 0, phase: .ended)
            try await postScroll(window, point, y: 90, phase: nil, momentum: .begin)
            try await postScroll(window, point, y: 0, phase: nil, momentum: .end)
            guard scene.conversationOpen else { throw ReplayError("Upward contact did not open Chief Bar") }
        }
        func bottomGap(_ timeline: NSScrollView) -> CGFloat {
            timeline.contentView.documentRect.maxY - timeline.contentView.bounds.maxY
        }
        var samples = [[String: Any]]()
        var failures = [String]()
        func checkBottom(_ name: String) async throws -> NSScrollView {
            let frame = scene.capsuleFrame
            let point = monitor.windowPoint(CGPoint(x: frame.midX, y: frame.midY))
            let timeline = try await conversationScroller(in: content, at: point)
            let gap = bottomGap(timeline)
            let png = directory.appending(path: "conversation-\(name).png")
            try await capture(window, to: png)
            let last = try recognizedLines(in: png, languages: ["en-US"]).first { $0.text.contains(ending) }
            let clip = window.convertToScreen(timeline.contentView.convert(timeline.contentView.bounds, to: nil))
            let lastFrame = last.map { CGRect(x: window.frame.minX + $0.frame.minX * window.frame.width,
                y: window.frame.minY + $0.frame.minY * window.frame.height,
                width: $0.frame.width * window.frame.width, height: $0.frame.height * window.frame.height) }
            let visible = lastFrame.map { clip.insetBy(dx: -2, dy: -2).contains($0) } ?? false
            samples.append(["visit": name, "bottomGap": gap, "lastLineInViewport": visible])
            if abs(gap) >= 2 || !visible || timeline.contentView.bounds.minX >= 1 {
                failures.append("\(name): gap=\(gap), lastLine=\(String(describing: lastFrame)), clip=\(clip)")
            }
            return timeline
        }
        let outside = monitor.windowPoint(CGPoint(x: 100, y: 200))
        try await recordWindow(window, to: directory.appending(path: "conversation-opening.mp4")) {
            try await Task.sleep(for: .milliseconds(250))
            try await open()
            try await Task.sleep(for: .milliseconds(550))
            let timeline = try await checkBottom("first")
            let clip = timeline.contentView
            let point = clip.convert(CGPoint(x: clip.bounds.midX, y: clip.bounds.midY), to: nil)
            let initial = clip.bounds.minY
            try await postScroll(window, point, y: 240, phase: .began)
            try await postScroll(window, point, y: 0, phase: .ended)
            let reading = clip.bounds.minY
            let id = try await subscription()
            let revised = JSONValue.object(["messages": .array(rows + [row(32, "A newer message arrived.")])])
            await client.emit(.threadContent(subscriptionId: id, state: .ready(revised)))
            try await Task.sleep(for: .milliseconds(200))
            let revisedY = clip.bounds.minY
            window.setContentSize(.init(width: content.bounds.width, height: 660))
            try await Task.sleep(for: .milliseconds(550))
            let resized = clip.bounds.minY
            samples.append(["initialY": initial, "readingY": reading, "revisedY": revisedY, "resizedY": resized])
            if reading >= initial - 40 || abs(revisedY - reading) >= 2 || abs(resized - reading) >= 2 {
                failures.append("Reading moved from \(initial) to \(reading) to \(revisedY) to \(resized)")
            }
            try await postClick(window, at: outside)
            try await Task.sleep(for: .milliseconds(650))
            guard !scene.conversationOpen else { throw ReplayError("Outside click did not dismiss Chief Bar") }

            // Start the mounted reader with no cached messages and deliver
            // its first nonempty page after the shell finishes expanding.
            try cache.saveContent(.object(["messages": .array([])]), thread: "moku", scope: scope)
            try await open()
            try await Task.sleep(for: .milliseconds(550))
            await client.emit(.threadContent(subscriptionId: try await subscription(), state: .ready(page)))
            try await Task.sleep(for: .milliseconds(550))
            _ = try await checkBottom("delayed-reopen")
            try await postClick(window, at: outside)
            try await Task.sleep(for: .milliseconds(650))

            try cache.saveContent(page, thread: "moku", scope: scope)
            try await postClick(window, at: barPoint())
            try await Task.sleep(for: .milliseconds(550))
            guard scene.inputOpen, !scene.conversationOpen else { throw ReplayError("Click did not open compact Compose") }
            try await open()
            try await Task.sleep(for: .milliseconds(550))
            _ = try await checkBottom("from-compose")
            try await postClick(window, at: outside)
            try await Task.sleep(for: .milliseconds(650))
        }
        try JSONSerialization.data(withJSONObject: ["samples": samples, "failures": failures], options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appending(path: "conversation-opening.json"))
        guard failures.isEmpty else { throw ReplayError(failures.joined(separator: "\n")) }
    }

    private func conversationScroller(in content: NSView, at point: CGPoint) async throws -> NSScrollView {
        let deadline = ContinuousClock.now + .seconds(3)
        while true {
            var candidates = [String]()
            if let timeline = descendant(NSScrollView.self, in: content, matching: { view in
                let rect = view.convert(view.bounds, to: nil)
                let width = view.documentView?.bounds.width ?? 0
                candidates.append("\(rect)/\(width)/\(view.contentView.bounds)")
                return rect.contains(point) && width > view.contentView.bounds.width + 40
            }) { return timeline }
            guard ContinuousClock.now < deadline else { throw ReplayError("Missing conversation scroller at \(point) in \(candidates)") }
            try await Task.sleep(for: .milliseconds(40))
        }
    }

    private func revealTimes(_ window: NSWindow, at point: CGPoint, timeline: NSScrollView, captureTo url: URL? = nil) async throws -> CGFloat {
        let before = timeline.contentView.bounds.origin
        try await postScroll(window, point, y: 0, phase: .began, x: -32)
        try await postScroll(window, point, y: 0, phase: .changed, x: -46)
        let held = timeline.contentView.bounds.origin
        guard before.x < 1, held.x > 50, abs(before.y - held.y) < 1 else {
            throw ReplayError("Holding a left swipe did not reveal times in place: \(before) → \(held)")
        }
        if let url {
            try await Task.sleep(for: .milliseconds(350))
            try await capture(window, to: url)
        }
        try await postScroll(window, point, y: 0, phase: .ended)
        let deadline = ContinuousClock.now + .seconds(3)
        while abs(timeline.contentView.bounds.minX) >= 1 {
            guard ContinuousClock.now < deadline else { throw ReplayError("Lifting did not hide timestamps") }
            try await Task.sleep(for: .milliseconds(30))
        }
        guard abs(before.y - timeline.contentView.bounds.minY) < 1 else {
            throw ReplayError("Releasing timestamps moved the transcript vertically: \(before) → \(held) → \(timeline.contentView.bounds.origin)")
        }
        return held.x
    }

    private func conversationElements(in window: NSWindow) -> [(id: String, role: String, label: String, value: String, frame: CGRect)] {
        var found = [(String, String, String, String, CGRect)]()
        func visit(_ node: NSObject) {
            func attribute(_ key: String) -> Any? {
                node.responds(to: NSSelectorFromString(key)) ? node.value(forKey: key) : nil
            }
            found.append((attribute("accessibilityIdentifier") as? String ?? "", attribute("accessibilityRole") as? String ?? "",
                          attribute("accessibilityLabel") as? String ?? attribute("accessibilityTitle") as? String ?? "",
                          attribute("accessibilityValue") as? String ?? "", (attribute("accessibilityFrame") as? NSValue)?.rectValue ?? .zero))
            for child in attribute("accessibilityChildren") as? [NSObject] ?? [] { visit(child) }
        }
        visit(window)
        return found
    }

    private func focusReplayWindow(_ window: NSWindow) async throws {
        guard !window.isKeyWindow else { return }
        // LaunchServices may leave the user's existing workspace in front
        // during a replay. Reopen only this unique replay bundle.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.addsToRecentItems = false
        let app = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        guard app.processIdentifier == getpid() else { throw ReplayError("Unexpected replay activation target") }
        window.makeKeyAndOrderFront(nil)
        let deadline = ContinuousClock.now + .seconds(3)
        while !window.isKeyWindow {
            guard ContinuousClock.now < deadline else {
                throw ReplayError("Replay window could not acquire focus, policy=\(NSApp.activationPolicy().rawValue), frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")")
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func recordWindow(_ window: NSWindow, to url: URL, actions: () async throws -> Void) async throws {
        let windows = try await SCShareableContent.currentProcess
        guard let target = windows.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw ReplayError("Cannot record replay window")
        }
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width)
        config.height = Int(window.frame.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.ignoreGlobalClipSingleWindow = true
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: target), configuration: config, delegate: nil)
        let settings = SCRecordingOutputConfiguration()
        settings.outputURL = url
        let (finished, completion) = AsyncThrowingStream<Void, Error>.makeStream()
        let observer = RecordingObserver(completion)
        let output = SCRecordingOutput(configuration: settings, delegate: observer)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()
        do {
            try await actions()
        } catch {
            try? await stream.stopCapture()
            throw error
        }
        try await stream.stopCapture()
        for try await _ in finished {}
    }

    private func capture(_ window: NSWindow, to url: URL) async throws {
        let ownWindows = try await SCShareableContent.currentProcess
        guard let target = ownWindows.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw ReplayError("Cannot capture replay window")
        }
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * 2)
        config.height = Int(window.frame.height * 2)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.ignoreGlobalClipSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: config)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ReplayError("Cannot encode replay window")
        }
        try png.write(to: url)
    }

    private func recognizedLines(in url: URL, languages: [String], region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) throws -> [(text: String, frame: CGRect)] {
        let request = VNRecognizeTextRequest()
        request.regionOfInterest = region
        request.recognitionLanguages = languages
        request.minimumTextHeight = 0.008
        try VNImageRequestHandler(url: url).perform([request])
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { (text: $0.string, frame: observation.boundingBox) }
        }
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView, matching: (T) -> Bool = { _ in true }) -> T? {
        if let match = view as? T, matching(match) { return match }
        for child in view.subviews {
            if let match = descendant(type, in: child, matching: matching) { return match }
        }
        return nil
    }

    private func pressKey(_ text: String, code: UInt16, in window: NSWindow) async throws {
        let flags: NSEvent.ModifierFlags = code == 36 || code == 53 ? [] : [.numericPad, .function]
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code) else {
                throw ReplayError("Cannot construct window keyboard input")
            }
            NSApp.postEvent(event, atStart: false)
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private struct AccessibleControl {
        let frame: CGRect
        let title: String
        let label: String
    }

    private func accessibilityAttribute(_ node: NSObject, _ key: String) -> Any? {
        // SwiftUI's accessible children implement individual AppKit accessors
        // without requiring the full NSAccessibilityProtocol conformance.
        node.responds(to: NSSelectorFromString(key)) ? node.value(forKey: key) : nil
    }

    private func filterButton(_ id: String, in window: NSWindow) throws -> AccessibleControl {
        try accessibleControl(id, role: .button, in: window)
    }

    private func accessibleControl(_ id: String, role: NSAccessibility.Role, in window: NSWindow) throws -> AccessibleControl {
        var controlIDs: [String] = []
        func find(_ value: Any) -> AccessibleControl? {
            guard let node = value as? NSObject else { return nil }
            if accessibilityAttribute(node, "accessibilityRole") as? String == role.rawValue,
               let identifier = accessibilityAttribute(node, "accessibilityIdentifier") as? String {
                controlIDs.append(identifier)
                if identifier == id, let frame = accessibilityAttribute(node, "accessibilityFrame") as? NSValue {
                    return AccessibleControl(frame: frame.rectValue,
                        title: accessibilityAttribute(node, "accessibilityTitle") as? String ?? "",
                        label: accessibilityAttribute(node, "accessibilityLabel") as? String ?? "")
                }
            }
            for child in accessibilityAttribute(node, "accessibilityChildren") as? [Any] ?? [] {
                if let result = find(child) { return result }
            }
            return nil
        }
        guard let button = find(window) ?? window.contentView.flatMap({ find($0) }) else {
            throw ReplayError("Missing accessible control \(id). Found \(controlIDs)")
        }
        return button
    }

    private func accessibilityLabels(_ value: Any) -> [String] {
        guard let node = value as? NSObject else { return [] }
        let label = accessibilityAttribute(node, "accessibilityLabel") as? String
        let children = accessibilityAttribute(node, "accessibilityChildren") as? [Any] ?? []
        return (label.map { [$0] } ?? []) + children.flatMap(accessibilityLabels)
    }

    private func checkGlyphInk(_ id: String, centerInset: CGFloat? = nil, in image: URL, window: NSWindow) throws {
        guard let pixels = NSBitmapImageRep(data: try Data(contentsOf: image)) else {
            throw ReplayError("Cannot read glyph screenshot")
        }
        let frame = window.convertFromScreen(try filterButton(id, in: window).frame)
        let scale = CGFloat(pixels.pixelsWide) / window.frame.width
        let x = Int((centerInset.map { frame.minX + $0 } ?? frame.midX) * scale)
        let y = Int((window.frame.height - frame.midY) * scale)
        let radius = Int(7 * scale)
        var levels = [CGFloat]()
        for dx in -radius...radius {
            for dy in -radius...radius {
                if let color = pixels.colorAt(x: x + dx, y: y + dy)?.usingColorSpace(.sRGB) {
                    levels.append(0.21 * color.redComponent + 0.72 * color.greenComponent + 0.07 * color.blueComponent)
                }
            }
        }
        levels.sort()
        guard !levels.isEmpty, levels[levels.count * 95 / 100] - levels[levels.count / 20] >= 0.14 else {
            throw ReplayError("Indistinguishable glyph in \(image.lastPathComponent) for \(id)")
        }
    }

    private func movePointer(_ window: NSWindow, to point: CGPoint) async throws {
        try await focusReplayWindow(window)
        window.acceptsMouseMovedEvents = true
        guard let event = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 0, pressure: 0),
              let screen = NSScreen.screens.first else {
            throw ReplayError("Cannot construct window-local pointer motion")
        }
        let position = window.convertPoint(toScreen: point)
        let target = CGPoint(x: position.x, y: screen.frame.maxY - position.y)
        guard CGWarpMouseCursorPosition(target) == .success else { throw ReplayError("Could not place fixture cursor") }
        // SwiftUI reads the live cursor for hover tracking. Deliver motion only
        // to the replay window. The caller restores the cursor on exit.
        window.sendEvent(event)
        try await Task.sleep(for: .milliseconds(240))
    }

    private func click(_ window: NSWindow, at location: CGPoint) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else {
                throw ReplayError("Cannot create a window-local click")
            }
            window.sendEvent(event)
        }
    }

    private func clickSettings(_ window: NSWindow, at point: CGPoint) async throws -> Bool {
        try click(window, at: CGPoint(x: point.x, y: window.frame.height - point.y))
        try await Task.sleep(for: .milliseconds(400))
        let opened = presentation.scene.settingsOpen
        guard opened, let content = window.contentView,
              let monitor = descendant(NativeOverviewScrollInput.MonitorView.self, in: content) else { return false }
        let camera = presentation.canvas.camera
        let before = camera.transform
        let wheel = WheelSample(window: window, point: monitor.windowPoint(CGPoint(x: 8, y: 230)), x: 200, y: 30)
        let blocked = monitor.handle(wheel) != nil && camera.transform == before
            && !presentation.overviewInteractionActions.contains("overview.scroll")
        presentation.scene.closeSettings()
        try await Task.sleep(for: .milliseconds(650))
        return blocked && camera.transform == before
    }

    private func postScroll(_ window: NSWindow, _ point: CGPoint, y: Int32, phase: CGScrollPhase?,
                            momentum: CGMomentumScrollPhase = .none, x: Int32 = 0,
                            flags: CGEventFlags = [], precise: Bool = true) async throws {
        if !window.isKeyWindow && NSScreen.screens.contains(where: { $0.frame.intersects(window.frame) }) {
            try await focusReplayWindow(window)
        }
        guard let content = window.contentView else { throw ReplayError("Scroll target window has no content") }
        func pixel(_ location: CGPoint) -> CGPoint {
            let backing = window.convertToBacking(CGRect(origin: location, size: .zero)).origin
            return CGPoint(x: floor(backing.x), y: floor(backing.y))
        }
        func hit(_ location: CGPoint) -> NSView? {
            content.hitTest(content.superview?.convert(location, from: nil) ?? location)
        }
        let targetPixel = pixel(point)
        let center = window.convertFromBacking(CGRect(x: targetPixel.x + 0.5, y: targetPixel.y + 0.5, width: 0, height: 0)).origin
        let targetHit = hit(point)
        guard hit(center) === targetHit else { throw ReplayError("Backing pixel center changed the scroll responder at \(point)") }
        // AppKit converts this envelope via screen coordinates. Fractional positions
        // can round across a pixel edge, and a moving window can still have a stale
        // presentation transform. Construct locally until it addresses the same hit.
        let deadline = ContinuousClock.now + .seconds(1)
        while true {
            guard let event = NSEvent.mouseEvent(with: .mouseMoved, location: center, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 0, pressure: 0)?.cgEvent else {
                throw ReplayError("Cannot address the replay window")
            }
            event.type = .scrollWheel
            event.flags = flags
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: precise ? 1 : 0)
            event.setIntegerValueField(precise ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventDeltaAxis1, value: Int64(y))
            event.setIntegerValueField(precise ? .scrollWheelEventPointDeltaAxis2 : .scrollWheelEventDeltaAxis2, value: Int64(x))
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase?.rawValue ?? 0))
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum.rawValue))
            guard let sample = NSEvent(cgEvent: event) else { throw ReplayError("Cannot decode window scroll event") }
            guard sample.window === window, sample.hasPreciseScrollingDeltas == precise else {
                throw ReplayError("Scroll window=\(sample.windowNumber)/\(window.windowNumber), precise=\(sample.hasPreciseScrollingDeltas)/\(precise)")
            }
            let delivered = sample.locationInWindow
            if pixel(delivered) == targetPixel, hit(delivered) === targetHit {
                NSApp.postEvent(sample, atStart: false)
                break
            }
            guard ContinuousClock.now < deadline else {
                throw ReplayError("Scroll at \(point) in \(window.frame) targeted pixel \(pixel(delivered))/\(targetPixel), hit=\(String(describing: hit(delivered)))/\(String(describing: targetHit))")
            }
            try await Task.sleep(for: .milliseconds(16))
        }
        try await Task.sleep(for: .milliseconds(55))
    }

    private func swipeWithNaturalScrolling(_ monitor: NativeOverviewScrollInput.MonitorView, in window: NSWindow,
                                          at point: CGPoint, up: Bool) throws {
        // The same finger movement reports the opposite delta with Natural Scrolling enabled.
        let sample = WheelSample(window: window, point: point, x: 0, y: up ? -40 : 40)
        guard monitor.handle(sample) == nil else { throw ReplayError("Inverted-device swipe escaped the active filter") }
        _ = monitor.handle(WheelSample(window: window, point: point, x: 0, y: 0, phase: .ended))
    }

    private func cacheNoteRuns(for thread: JSONText) throws {
        let cache = RuntimeOfflineStore(storageDirectory: workspace.client.storageDirectory, hostID: nil)
        func state(_ turns: [JSONValue]) -> JSONValue {
            .object(["schema": .text("mokusei.harness.codex.thread.v1"), "updatedAt": .integer(3),
                     "turns": .array(turns), "backgroundTerminals": .array([])])
        }
        var turns = [JSONValue]()
        for (index, run) in ["cited-run", "later-run"].enumerated() {
            let time = JSONValue.integer(index + 1)
            let reply = (1...40).map { "\(run) paragraph \($0)." }.joined(separator: "\n\n")
            var turn: [JSONText: JSONValue] = ["executionId": .text(run), "status": .text("completed"),
                "createdAt": time, "updatedAt": time, "finishedAt": time, "reasoning": .text(""),
                "answer": .text(""), "messages": .array([]), "timeline": .array([]), "activities": .array([]),
                "notices": .array([]), "interactions": .array([]), "plan": .array([])]
            turns.append(.object(turn))
            turn["timeline"] = .array([.object(["id": .text("reply"), "itemId": .text("message"),
                "kind": .text("assistant"), "content": .text(reply), "status": .text("complete"), "createdAt": time])])
            turn["answer"] = .text(reply)
            try cache.saveContent(state([.object(turn)]), thread: thread, scope: .turn(key: JSONText("turn:" + run)))
        }
        try cache.saveContent(state(turns), thread: thread, scope: .thread)
    }

    private func cacheConversationPages() throws {
        let cache = RuntimeOfflineStore(storageDirectory: workspace.client.storageDirectory, hostID: nil)
        let midnight = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        func row(_ text: String, _ seconds: Int, user: Bool) -> JSONValue {
            .object(["id": .text("message-\(seconds)"), "text": .text(text), "createdAt": .integer((midnight + seconds) * 1000),
                     "role": .text(user ? "user" : "chief")])
        }
        let rows = [row("Can we finish this tomorrow?", -120, user: true), row("One more thing.", -60, user: true),
                    row("I saved the notes.", 60, user: false), row("Ready to continue?", 959, user: false),
                    row("Let’s send them.", 1859, user: true)]
        try cache.saveContent(.object(["messages": .array(rows), "before": .text("message--120")]),
                              thread: "moku", scope: .mokuConversation(before: nil))
        let earlier = (1...20).map { index in row("Earlier plan \(index)", -7200 + index * 60, user: false) }
        try cache.saveContent(.object(["messages": .array(earlier)]),
                              thread: "moku", scope: .mokuConversation(before: "message--120"))
    }

    private func noteLinks(_ window: NSWindow, directory: URL, authority: UUID) async throws {
        let model = presentation.overview, scene = presentation.scene
        let source = ApplicationThreadRef(threadID: "linked-task", typeID: "agent")
        let citation = ApplicationExecutionRef(thread: source, executionID: "cited-run")
        try cacheNoteRuns(for: source.threadID)
        let events = await workspace.client.events()
        let contentDelivery = Task {
            for await event in events {
                if case .threadContent = event { workspace.harnessHost.receive(event) }
            }
        }
        defer { contentDelivery.cancel() }
        let note = "[Earlier run](chief://execution?threadId=linked-task&executionId=cited-run)"
        let thread = try HarnessThread(id: source.threadID, harnessID: "codex", revision: 1, sessionState: .null,
            observation: .init(latestExecution: .init(executionID: "later-run", status: .completed, startedAt: 1, finishedAt: 2)),
            cwd: "/other", settings: .object([:]), createdAt: 1, updatedAt: 2, title: "Linked task",
            tags: ["Design"], tagEmojis: ["Design": "🎨"], directoryTag: "Other", directoryScope: "/other")
        let bug = try HarnessThread(id: "other-bug", harnessID: "codex", revision: 1, sessionState: .null,
            observation: .init(), cwd: "/other", settings: .object([:]), createdAt: 1, updatedAt: 2, title: "Bug",
            tags: ["Bugs"], tagEmojis: ["Bugs": "🐛"], directoryTag: "Other", directoryScope: "/other")
        func install(revision: Int, reports: [JSONValue] = []) async throws {
            try await installTasks(2, revision: revision, authority: authority, firstDirectoryCount: 1,
                reports: reports, extraThreads: [thread.json, bug.json], noteText: note)
        }
        try await install(revision: 2)
        guard let project = model.visibleFilters.first(where: { $0.scope == "/fixture" }),
              let other = model.visibleFilters.first(where: { $0.scope == "/other" }),
              let bugs = other.children.first(where: { $0.tag == "Bugs" }),
              let design = other.children.first(where: { $0.tag == "Design" }) else {
            throw ReplayError("Missing Note fixture filters")
        }
        func wait(_ message: String, until ready: () -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(6)
            while !ready() {
                guard ContinuousClock.now < deadline else {
                    throw ReplayError("\(message), note=\(scene.notePanelOpen), focused=\(model.facts.focused), phase=\(scene.noteReadingOrigin?.phase.rawValue ?? "none"), filter=\(model.selectedFilter?.id ?? "All"), reader=\(presentation.selected?.threadID.string ?? "none")")
                }
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        var visits = [[String: Any]]()
        func visit(from start: NativeOverviewFilter, to end: NativeOverviewFilter, reader: ApplicationThreadRef,
                   fromRunning: Bool = false) async throws {
            model.selectTag(start)
            if fromRunning {
                try model.chromeInteractions.activate(.status, id: "running")
                guard model.statusFilter == .running, model.items.isEmpty else { throw ReplayError("Expected empty folder Running") }
            }
            await presentation.canvas.prepareForPresentation()
            scene.openNotePanelFromUser()
            func linkFrame() -> CGRect? {
                guard let content = window.contentView,
                      let link = descendant(MarkdownExecutionHost.self, in: content) else { return nil }
                let frame = link.convert(link.bounds, to: nil)
                let point = CGPoint(x: frame.midX, y: frame.midY)
                // A retained link participates only once its TextKit seat accepts pointer input.
                guard content.hitTest(content.superview?.convert(point, from: nil) ?? point) is MarkdownTextView
                else { return nil }
                return frame
            }
            try await wait("Note link did not become clickable") { linkFrame() != nil }
            guard let frame = linkFrame() else { throw ReplayError("Note link left the window before the click") }
            // TextKit tracks the mouse until release. Queue both events for the replay window.
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(with: type, location: CGPoint(x: frame.midX, y: frame.midY),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else {
                    throw ReplayError("Cannot construct Note link click")
                }
                NSApp.postEvent(event, atStart: false)
            }
            try await wait("Note click missed its execution link") { scene.noteReadingOrigin != nil }
            guard let origin = scene.noteReadingOrigin, origin.phase == .dismissing, origin.reference == citation,
                  model.selectedFilter?.id == start.id, presentation.selected == nil else {
                throw ReplayError("Note click lost its citation or changed space before dismissal")
            }
            try await wait("Did not locate the destination on Overview before opening the reader") {
                scene.noteReadingOrigin?.phase == .locating && model.selectedFilter?.id == end.id &&
                    !scene.notePanelOpen && presentation.selected == nil
            }
            try await wait("Destination reader did not mount") { presentation.mountedReadingThread == reader }
            guard model.statusFilter == .all,
                  model.selectedFilter?.id == end.id, presentation.selected == reader,
                  presentation.readingPanelSource != nil, scene.noteReadingOrigin?.id == origin.id,
                  scene.noteReadingOrigin?.phase == .reading else { throw ReplayError("Incorrect reader entrance or space") }
            let position: HarnessReadingTarget.Position?
            let opened: ApplicationExecutionRef?
            if reader == source {
                let target = presentation.readingTarget
                guard target?.mode == .history else { throw ReplayError("Expected a pinned historical visit") }
                opened = target.map { .init(thread: reader, executionID: $0.executionID) }
                position = target?.position
            } else {
                opened = presentation.reportSidecards.selectedExecution
                position = presentation.reportSidecards.entryPosition
            }
            guard let opened, opened == citation, let position, position == .executionStart else {
                throw ReplayError("Opened the wrong run or position")
            }
            var record: [String: Any] = ["dismissing": start.id, "locating": end.id, "reading": end.id,
                "reader": reader.threadID.string, "source": opened.thread.threadID.string,
                "execution": opened.executionID.string, "position": position.rawValue, "fromFolderRunning": fromRunning]
            if reader == source {
                try await wait("Historical reply did not load at its heading") {
                    let controls = presentation.readingInteractionSnapshot()["controls"]?.arrayValue ?? []
                    guard controls.contains(where: { $0["role"] == .text("history") && $0["value"]?["rowId"] == .text("turn:cited-run") }),
                          controls.contains(where: { $0["role"] == .text("row.load") && $0["value"]?["state"] == .text("ready")
                              && $0["value"]?["rowId"] == .text("turn:cited-run") }),
                          let value = controls.first(where: { $0["role"] == .text("timeline") && $0["id"]?.stringValue?.contains("history") == true })?["value"],
                          let height = value["height"]?.numberValue, let viewport = value["viewport"]?.numberValue,
                          viewport > 0, height > viewport, value["top"]?.numberValue == 0, value["following"] == .bool(false) else { return false }
                    record["timeline"] = ["height": height, "viewport": viewport, "top": 0, "following": false] as [String: Any]
                    return true
                }
            }
            visits.append(record)
            presentation.showOverview()
            try await wait("Reader did not close to the destination space") {
                presentation.selected == nil && model.presentationActive && !presentation.messageMotion.active
                    && !scene.notePanelOpen && model.selectedFilter?.id == end.id
            }
        }
        try await visit(from: project, to: other, reader: source)
        try await visit(from: bugs, to: design, reader: source)
        try await visit(from: design, to: design, reader: source)
        try await visit(from: other, to: other, reader: source, fromRunning: true)

        let report = ApplicationThreadRef(threadID: "linked-report", typeID: "report.document")
        var fields = reportFixtures([report.threadID])[0].objectValue!
        let related = JSONValue.array([.object(["thread": source.json, "executionId": .text("later-run")])])
        var view = fields["view"]!.objectValue!
        view["relatedExecutions"] = related
        fields["view"] = .object(view)
        fields["presentations"] = .array([.object(["id": .text("mokusei.overview"), "apiVersion": .integer(1),
            "schemaVersion": .integer(1), "value": .object(["coversExecutions": related])])])
        try await install(revision: 3, reports: [.object(fields)])
        try await visit(from: design, to: project, reader: report)
        try JSONSerialization.data(withJSONObject: visits, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appending(path: "note-links.json"))
    }

    private func postClick(_ window: NSWindow, at point: CGPoint, secondary: Bool = false,
                           flags: NSEvent.ModifierFlags = []) async throws {
        let types: [NSEvent.EventType] = secondary ? [.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp]
        for (index, type) in types.enumerated() {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: index == 0 ? 1 : 0) else {
                throw ReplayError("Cannot construct window click")
            }
            NSApp.postEvent(event, atStart: false)
            try await Task.sleep(for: .milliseconds(45))
        }
    }

    /// Exercise installed AppKit monitors and native scroll responders.
    private func noteClicks(_ window: NSWindow, directory: URL) async throws {
        guard let content = window.contentView,
              let monitor = descendant(NativeOverviewScrollInput.MonitorView.self, in: content),
              let parent = descendant(NativeReadingParentView.self, in: content),
              let tags = descendant(NSScrollView.self, in: parent, matching: {
                  ($0.documentView?.bounds.width ?? 0) > $0.contentView.bounds.width + 1
              }) else {
            throw ReplayError("Missing Overview swipe targets")
        }
        let size = monitor.configuration.size
        let center: (CGRect) -> CGPoint = { CGPoint(x: $0.midX, y: $0.midY) }
        // Choose a visible right-half card away from the floating controls.
        let rightCanvas = CGRect(x: size.width / 2, y: monitor.configuration.toolbarBottom,
                                 width: size.width * 0.28,
                                 height: max(0, size.height - monitor.configuration.toolbarBottom))
        let rightWindow = content.convert(content.bounds, to: nil).divided(
            atDistance: content.bounds.width / 2, from: .maxXEdge).slice
        let tagTarget = tags.convert(tags.bounds, to: nil).intersection(rightWindow)
        guard !tagTarget.isEmpty,
              let cardTarget = presentation.canvas.presentedPlacements.compactMap({
                  presentation.canvas.visibleFrame(for: $0.id)?.intersection(rightCanvas)
              }).first(where: { $0.width > 40 && $0.height > 40 }) else {
            throw ReplayError("Missing a right-half card or tag-bar target")
        }
        let scene = presentation.scene
        let camera = presentation.canvas.camera
        let background = monitor.windowPoint(CGPoint(x: size.width * 0.72, y: size.height - 8))
        let barPoint = monitor.windowPoint(center(scene.capsuleFrame))
        let targets = [("background", background), ("card", monitor.windowPoint(center(cardTarget))),
                       ("tag scroller", center(tagTarget))]
        let startOffset = camera.scrollOffset
        let model = presentation.overview
        try await postScroll(window, background, y: 9, phase: .began)
        try await postScroll(window, background, y: 0, phase: .cancelled)
        try await postScroll(window, background, y: 60, phase: nil, momentum: .begin)
        try await postScroll(window, background, y: 0, phase: nil, momentum: .end)
        guard model.statusFilter == .all, !scene.notePanelOpen else { throw ReplayError("Orphan momentum took action") }
        for (region, point) in targets {
            try await postScroll(window, point, y: 10, phase: .began)
            guard !scene.notePanelOpen, model.statusFilter == .all else { throw ReplayError("Subthreshold swipe at " + region) }
            try await postScroll(window, point, y: 17, phase: .changed)
            guard !scene.notePanelOpen, model.statusFilter == .running else { throw ReplayError("Wrong swipe owner at " + region) }
            // Reverse before lift, cross onto the Bar and add inertia.
            try await postScroll(window, barPoint, y: -60, phase: .changed)
            try await postScroll(window, barPoint, y: 0, phase: .ended)
            try await postScroll(window, barPoint, y: -60, phase: nil, momentum: .begin, x: -20)
            try await postScroll(window, barPoint, y: 0, phase: nil, momentum: .end)
            guard !scene.notePanelOpen, model.statusFilter == .running,
                  camera.scrollOffset == startOffset else { throw ReplayError("Swipe tail escaped at " + region) }
            try model.chromeInteractions.activate(.directory, id: model.selectedDirectory!.id)
            try await Task.sleep(for: .milliseconds(600))
        }
        try swipeWithNaturalScrolling(monitor, in: window, at: background, up: true)
        guard !scene.notePanelOpen, model.statusFilter == .running else {
            throw ReplayError("Natural Scrolling changed the physical filter gesture")
        }
        try model.chromeInteractions.activate(.directory, id: model.selectedDirectory!.id)
        try await Task.sleep(for: .milliseconds(650))
        let tagPoint = tags.convert(center(tags.bounds), to: nil)
        let tagOffset = tags.contentView.bounds.minX
        try await postScroll(window, tagPoint, y: 0, phase: .began, x: tagOffset > 0 ? 40 : -40)
        try await postScroll(window, tagPoint, y: 0, phase: .ended)
        guard tags.contentView.bounds.minX != tagOffset, camera.scrollOffset == startOffset,
              !scene.notePanelOpen else { throw ReplayError("The overflowing tags lost horizontal scrolling") }

        let beforeOpen = scene.noteOpenGeneration
        try cacheConversationPages()
        try await postScroll(window, barPoint, y: 10, phase: .began)
        guard !scene.conversationOpen else { throw ReplayError("A subthreshold contact opened the conversation") }
        try await postScroll(window, barPoint, y: 30, phase: .changed)
        try await postScroll(window, barPoint, y: 0, phase: .ended)
        try await postScroll(window, barPoint, y: 40, phase: nil, momentum: .begin)
        try await postScroll(window, barPoint, y: 0, phase: nil, momentum: .end)
        guard scene.conversationOpen, scene.inputOpen, !scene.notePanelOpen, scene.noteOpenGeneration == beforeOpen,
              model.statusFilter == .all, camera.scrollOffset == startOffset else {
            throw ReplayError("The Bar swipe did not open the conversation directly")
        }
        try await Task.sleep(for: .milliseconds(650))
        let page = conversationElements(in: window)
        let periods = page.filter { $0.id == "moku-conversation-period" }
        guard let shell = page.first(where: { $0.id == "moku-capsule" })?.frame, periods.count == 3,
              periods.allSatisfy({ abs($0.frame.midX - shell.midX) < 1.5 }),
              page.filter({ $0.id == "moku-conversation-message" }).allSatisfy({
                  $0.frame.minX >= shell.minX + 10 && $0.frame.maxX <= shell.maxX - 10
              }) else { throw ReplayError("Messages or date headings did not fit the capsule: \(page)") }
        try await capture(window, to: directory.appending(path: "conversation-periods.png"))
        var readingOffsets = [CGFloat]()
        for (button, message) in [("moku-conversation-earlier", "Earlier plan 20"), ("moku-conversation-newer", "Let’s send them.")] {
            guard let pageButton = conversationElements(in: window).first(where: {
                $0.role == "AXButton" && $0.id == button
            }) else { throw ReplayError("Missing \(button) in the conversation timeline") }
            try await postClick(window, at: window.convertPoint(fromScreen: CGPoint(x: pageButton.frame.midX, y: pageButton.frame.midY)))
            let pageDeadline = ContinuousClock.now + .seconds(3)
            while !conversationElements(in: window).contains(where: {
                $0.id == "moku-conversation-message" && ($0.label + $0.value).contains(", " + message + " — ")
            }) {
                guard ContinuousClock.now < pageDeadline else { throw ReplayError("Could not read \(message) via \(button)") }
                try await Task.sleep(for: .milliseconds(40))
            }
            if button == "moku-conversation-earlier" {
                let point = monitor.windowPoint(center(scene.capsuleFrame))
                let timeline = try await conversationScroller(in: content, at: point)
                let bottom = timeline.contentView.bounds.minY
                try await postScroll(window, point, y: 120, phase: .began)
                try await postScroll(window, point, y: 0, phase: .ended)
                guard timeline.contentView.bounds.minY > 20, timeline.contentView.bounds.minY < bottom - 20 else {
                    throw ReplayError("Could not scroll up from the latest cached message: \(bottom) → \(timeline.contentView.bounds.minY)")
                }
                _ = try await revealTimes(window, at: point, timeline: timeline)
                let reading = timeline.contentView.bounds
                let size = content.bounds.size
                window.setContentSize(.init(width: size.width, height: NativeGeometry.minimumWindow.height))
                try await Task.sleep(for: .milliseconds(350))
                let compact = timeline.contentView.bounds
                guard compact.height < reading.height - 20, abs(compact.minY - reading.minY) < 1 else {
                    throw ReplayError("Window resize lost the earlier reading position: \(reading) → \(compact)")
                }
                readingOffsets = [reading.minY, compact.minY]
                window.setContentSize(size)
                try await Task.sleep(for: .milliseconds(350))
                try await postScroll(window, point, y: -160, phase: .began)
                try await postScroll(window, point, y: 0, phase: .ended)
            }
        }
        guard let field = descendant(NSTextView.self, in: content, matching: { $0.isEditable && !$0.isHiddenOrHasHiddenAncestor }),
              window.makeFirstResponder(field) else { throw ReplayError("Missing conversation editor") }
        let draft = "Please check the release notes."
        field.insertText(draft, replacementRange: field.selectedRange())
        guard presentation.dockDraft.text == draft else { throw ReplayError("Conversation did not edit the Chief draft") }
        try await postClick(window, at: background)
        try await Task.sleep(for: .milliseconds(650))
        guard !scene.conversationOpen, !scene.inputOpen else { throw ReplayError("Outside click did not close the conversation") }
        try await postClick(window, at: background, secondary: true)
        guard !scene.notePanelOpen, scene.noteOpenGeneration == beforeOpen,
              model.statusFilter == .all, camera.scrollOffset == startOffset else {
            throw ReplayError("Background right-click changed the Bar or Overview")
        }
        try await postClick(window, at: barPoint, secondary: true)
        guard scene.notePanelOpen, scene.noteOpenGeneration == beforeOpen + 1, !scene.inputOpen else {
            throw ReplayError("Chief Bar right-click did not open Note directly")
        }
        try await Task.sleep(for: .milliseconds(850))
        let notePoint = monitor.windowPoint(center(scene.capsuleFrame))
        let hit = content.hitTest(content.superview?.convert(notePoint, from: nil) ?? notePoint)
        guard let scroller = hit?.enclosingScrollView, let document = scroller.documentView,
              document.bounds.height > scroller.contentView.bounds.height + 80 else {
            throw ReplayError("Note click fixture missed the overflowing Note body")
        }
        if CommandLine.arguments.contains("--capture") {
            try await capture(window, to: directory.appending(path: "chief-note.png"))
        }
        let generation = scene.noteOpenGeneration
        let original = scroller.contentView.bounds.minY
        try await postScroll(window, notePoint, y: -70, phase: .began)
        try await postScroll(window, notePoint, y: 0, phase: .ended)
        let scrolled = scroller.contentView.bounds.minY
        try await postScroll(window, notePoint, y: 40, phase: .began)
        try await postScroll(window, notePoint, y: 0, phase: .ended)
        guard scrolled > original, scroller.contentView.bounds.minY < scrolled,
              scene.notePanelOpen, scene.noteOpenGeneration == generation else {
            throw ReplayError("The open Note lost native scrolling or opened twice")
        }
        try await postClick(window, at: background)
        guard !scene.notePanelOpen else { throw ReplayError("Outside click did not close Note") }
        try await Task.sleep(for: .milliseconds(650))
        try await postScroll(window, barPoint, y: -40, phase: .began)
        try await postScroll(window, barPoint, y: 0, phase: .ended)
        try await postScroll(window, background, y: 40, phase: .began, flags: .maskShift)
        try await postScroll(window, background, y: 0, phase: .ended)
        guard !scene.notePanelOpen, !scene.conversationOpen, model.statusFilter == .all else { throw ReplayError("Downward Bar or modified canvas input took action") }
        // The Note and the restored 18-card layout share a motion coordinator.
        // Test a fresh pan once the production camera admits a new contact.
        let panDeadline = ContinuousClock.now + .seconds(6)
        while !monitor.enabled() {
            guard ContinuousClock.now < panDeadline else {
                throw ReplayError("Camera did not resume after Note: stage=\(String(describing: presentation.canvas.motionStages.activeOwner)), layout=\(presentation.canvas.isLayingOut)")
            }
            try await Task.sleep(for: .milliseconds(30))
        }
        let panStart = camera.scrollOffset
        try await postScroll(window, background, y: 3, phase: .began, x: panStart > 0 ? 40 : -40)
        try await postScroll(window, background, y: 0, phase: .ended)
        guard !scene.notePanelOpen, camera.scrollOffset != panStart else {
            throw ReplayError("Horizontal window scroll did not reach the camera: offset=\(panStart)->\(camera.scrollOffset)/\(camera.maximumOffset), point=\(background), phase=\(monitor.sequence.stage), owner=\(String(describing: monitor.sequence.owner)), pause=\(presentation.canvas.interactionPauseReasons), layingOut=\(presentation.canvas.isLayingOut), input=\(scene.inputOpen)")
        }
        try await postClick(window, at: barPoint)
        guard scene.inputOpen, !scene.conversationOpen, !scene.notePanelOpen, presentation.dockDraft.text == draft else {
            throw ReplayError("Primary Bar click did not reopen Compose with the conversation draft")
        }
        try await postScroll(window, background, y: 40, phase: .began)
        try await postScroll(window, background, y: 0, phase: .ended)
        guard scene.inputOpen, !scene.notePanelOpen, model.statusFilter == .all else { throw ReplayError("Swipe displaced the composer") }
        scene.setInputOpen(false)
        presentation.openSettings()
        try await postScroll(window, background, y: 40, phase: .began)
        try await postScroll(window, background, y: 0, phase: .ended)
        guard scene.settingsOpen, !scene.notePanelOpen, model.statusFilter == .all else { throw ReplayError("Swipe escaped Settings") }
        scene.closeSettings()
        let deadline = ContinuousClock.now + .seconds(4)
        while scene.settingsOpen || !monitor.enabled() {
            guard ContinuousClock.now < deadline else { throw ReplayError("Overview did not resume after Settings") }
            try await Task.sleep(for: .milliseconds(30))
        }
        try JSONSerialization.data(withJSONObject: ["regions": targets.map { $0.0 },
            "rightClickOpenedNoteOnce": true, "swipeOpenedConversation": true, "backgroundRightClickOpenedNote": false,
            "conversationDraftRestoredInCompose": true, "conversationPeriodCount": periods.count, "conversationPaging": true,
            "olderReadingOffsetsOnResize": readingOffsets,
            "outsideClickClosedNote": true, "primaryClickOpenedCompose": true,
            "horizontalScroll": true, "composerScrollExcluded": true, "settingsScrollExcluded": true,
            "tagOffsets": [tagOffset, tags.contentView.bounds.minX], "noteOffsets": [original, scrolled],
            "naturalScrolling": true])
            .write(to: directory.appending(path: "overview-note-click.json"))
    }

    /// Exercise both event owners in the same production workspace, entirely offscreen.
    private func reminderSwipe(directory: URL) async throws {
        guard let edge = NSScreen.screens.map({ $0.frame.maxX }).max() else { throw ReplayError("Missing screen") }
        // Keep WindowServer composing the panel while the controls stay offscreen.
        let frame = CGRect(x: edge - 2, y: 200, width: 900, height: 680)
        let window = ReminderReplayPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSHostingView(rootView: NativeWorkspaceView(model: workspace, presentation: presentation)
            .environment(\.scenePhase, .active))
        window.contentView = root
        window.setFrameOrigin(frame.origin)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        guard NSScreen.screens.allSatisfy({ window.frame.intersection($0.frame).width <= 2 }) else {
            throw ReplayError("Reminder interaction must run offscreen")
        }
        try await installTasks(18, revision: 1, authority: UUID(), manyDirectories: true)
        try await Task.sleep(for: .seconds(1))
        let timer = workspace.timer, scene = presentation.scene
        timer.receive(nil)
        let message = String(repeating: "Check this.\n", count: 10)
        let row: JSONValue = .object(["type": .text("tool-operation"), "name": .text("timer"),
            "id": .text("reminder"), "executionId": .text("fixture"), "completedAt": .integer(1),
            "result": .object(["ok": .bool(true)]), "arguments": .object(["text": .text(message)])])
        timer.receive(try HarnessThread(id: "moku", harnessID: "codex", revision: 1,
            sessionState: .null, observation: .init(), cwd: "/fixture", settings: .object([:]),
            createdAt: 1, updatedAt: 2, title: "Chief", tags: [], moku: true, transcript: .array([row])))
        try await Task.sleep(for: .milliseconds(800))
        guard let monitor = descendant(NativeOverviewScrollInput.MonitorView.self, in: root),
              let alert = timer.current else { throw ReplayError("Missing reminder or scroll monitor: pending=\(timer.pending.count)") }
        func messageScroller(in view: NSView) -> NSScrollView? {
            if let scroller = view as? NSScrollView, scroller.contentView.bounds.height > 0,
               scroller.contentView.bounds.height <= 41, let document = scroller.documentView,
               document.bounds.height > scroller.contentView.bounds.height + 80,
               monitor.reminderScrollRegions?.contains(scroller.convert(CGPoint(x: scroller.bounds.midX,
                    y: scroller.bounds.midY), to: nil), in: window) == true { return scroller }
            return view.subviews.lazy.compactMap { messageScroller(in: $0) }.first
        }
        guard let scroller = messageScroller(in: root) else { throw ReplayError("Missing long reminder viewport") }
        let clip = scroller.contentView
        let point = clip.convert(CGPoint(x: clip.bounds.midX, y: clip.bounds.midY), to: nil)
        let bodyOnScreen = window.convertToScreen(clip.convert(clip.bounds, to: nil))
        guard NSScreen.screens.allSatisfy({ !$0.frame.intersects(bodyOnScreen) }) else {
            throw ReplayError("Reminder viewport must stay outside all screens")
        }
        let generation = scene.noteOpenGeneration, camera = presentation.canvas.camera.scrollOffset
        try await postScroll(window, point, y: -70, phase: .began)
        try await postScroll(window, point, y: 0, phase: .ended)
        let down = clip.bounds.minY
        try await postScroll(window, point, y: 40, phase: .began)
        try await postScroll(window, point, y: 0, phase: .ended)
        let up = clip.bounds.minY
        guard down > 0, up < down, presentation.overview.statusFilter == .all, scene.noteOpenGeneration == generation, !scene.notePanelOpen,
              timer.current?.id == alert.id, presentation.canvas.camera.scrollOffset == camera else {
            throw ReplayError("Long reminder lost native scroll or Note took its gesture: \(down), \(up)")
        }
        let size = monitor.configuration.size
        let background = monitor.windowPoint(CGPoint(x: size.width * 0.72, y: size.height - 8))
        try await postScroll(window, background, y: 36, phase: .began)
        try await postScroll(window, background, y: 0, phase: .ended)
        guard !scene.notePanelOpen, scene.noteOpenGeneration == generation, presentation.overview.statusFilter == .running, timer.current?.id == alert.id else {
            throw ReplayError("Exposed Overview lost its status gesture while a reminder was pending")
        }
        try await Task.sleep(for: .milliseconds(700))
        guard let receipt = descendant(NativeMokuTimerReceiptButton.ReceiptButton.self, in: root),
              receipt.accessibilityPerformPress(), timer.current == nil else { throw ReplayError("Missing explicit receipt") }
        try JSONSerialization.data(withJSONObject: ["offscreen": true, "scrollOffsets": [down, up],
            "backgroundFilter": presentation.overview.statusFilter.rawValue, "explicitReceipt": true])
            .write(to: directory.appending(path: "reminder-note-ownership.json"))
    }

    private func cardInteraction(_ window: NSWindow, directory: URL, authority: UUID) async throws {
        guard window.isKeyWindow, let content = window.contentView,
              let monitor = descendant(NativeOverviewScrollInput.MonitorView.self, in: content) else {
            throw ReplayError("Expected the isolated key window with mounted scroll input")
        }
        let canvas = presentation.canvas
        let camera = canvas.camera
        let size = monitor.configuration.size
        let viewport = CGRect(origin: .zero, size: size)
        let point = monitor.windowPoint(CGPoint(x: 8, y: monitor.configuration.toolbarBottom + 3))
        func mouse(_ type: NSEvent.EventType, _ position: CGPoint) async throws {
            guard let event = NSEvent.mouseEvent(with: type, location: monitor.windowPoint(position), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) else {
                throw ReplayError("Cannot construct window mouse input")
            }
            NSApp.postEvent(event, atStart: false)
            try await Task.sleep(for: .milliseconds(45))
        }
        _ = monitor.handle(WheelSample(window: window, point: point, x: 10000, y: 0))
        let initiallyOffscreen = canvas.presentedPlacements.filter { canvas.visibleFrame(for: $0.id) == nil }
        _ = monitor.handle(WheelSample(window: window, point: point, x: -10000, y: 50))
        let atEnd = camera.scrollOffset
        try await Task.sleep(for: .milliseconds(200))
        guard atEnd == camera.maximumOffset, atEnd > 0, !initiallyOffscreen.isEmpty else {
            throw ReplayError("Dense fixture did not reach its trailing boundary: offset=\(atEnd)/\(camera.maximumOffset), offscreen=\(initiallyOffscreen.count), enabled=\(monitor.enabled()), canvasStart=\(monitor.canStart(at: monitor.canvasPoint(point))), owner=\(String(describing: monitor.sequence.owner)), buttons=\(NSEvent.pressedMouseButtons)")
        }
        let envelope = canvas.presentedPlacements.compactMap { canvas.displayedFrame(for: $0.id) }
            .reduce(CGRect.null) { $0.union($1) }
        guard !envelope.isNull, envelope.maxX < size.width, envelope.maxY < size.height else {
            throw ReplayError("Missing trailing or bottom canvas margin for background input")
        }
        let blank = CGPoint(x: (envelope.maxX + size.width) / 2, y: (envelope.maxY + size.height) / 2)
        let windowOrigin = window.frame.origin
        for end in [CGPoint(x: blank.x - 90, y: blank.y), CGPoint(x: blank.x, y: blank.y - 80)] {
            try await mouse(.leftMouseDown, blank)
            try await mouse(.leftMouseDragged, end)
            try await mouse(.leftMouseUp, end)
        }
        try await mouse(.leftMouseDown, blank)
        try await mouse(.leftMouseUp, blank)
        try await Task.sleep(for: .milliseconds(450))
        guard camera.scrollOffset == atEnd, window.frame.origin == windowOrigin, presentation.selected == nil else {
            throw ReplayError("Background drag or click moved the window, scrolled Overview or opened a card")
        }
        let frames = canvas.presentedPlacements.compactMap { canvas.displayedFrame(for: $0.id) }
        guard frames.count == 18, frames.allSatisfy({ $0.minY >= 0 && $0.maxY <= size.height }),
              !frames.enumerated().contains(where: { index, frame in frames.dropFirst(index + 1).contains(where: frame.intersects) }),
              let target = initiallyOffscreen.first(where: { card in
                  canvas.displayedFrame(for: card.id).map(viewport.contains) == true
              }), let frame = canvas.displayedFrame(for: target.id) else {
            throw ReplayError("Overflow cards overlap, spill vertically or are unreachable")
        }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let windowPoint = monitor.windowPoint(center)
        let clickedView = content.hitTest(content.superview?.convert(windowPoint, from: nil) ?? windowPoint)
        try await mouse(.mouseMoved, center)
        try await mouse(.leftMouseDown, center)
        try await mouse(.leftMouseUp, center)
        try await Task.sleep(for: .milliseconds(850))
        guard presentation.selected?.threadID.string == target.id else {
            throw ReplayError("Click missed \(target.id), selected=\(String(describing: presentation.selected)), "
                + "viewport=\(size), frame=\(frame), windowPoint=\(windowPoint), hit=\(String(describing: clickedView)), "
                + "active=\(canvas.allowsActivation(cardID: target.id)), key=\(window.isKeyWindow)")
        }
        try await postScroll(window, windowPoint, y: 40, phase: .began)
        try await postScroll(window, windowPoint, y: 0, phase: .ended)
        guard !presentation.scene.notePanelOpen, presentation.overview.statusFilter == .all, presentation.selected?.threadID.string == target.id else {
            throw ReplayError("A swipe in the reader activated Overview")
        }
        presentation.showOverview()
        try await Task.sleep(for: .seconds(1))
        guard presentation.selected == nil, camera.scrollOffset == atEnd else {
            throw ReplayError("Returning from the reader changed the scroll position")
        }
        if CommandLine.arguments.contains("--keyboard") {
            try await keyboardInteraction(window, directory: directory, id: target.id, atEnd: atEnd)
        }
        try await installTasks(20, revision: 2, authority: authority)
        try await Task.sleep(for: .milliseconds(700))
        guard canvas.presentedPlacements.count == 20, camera.scrollOffset == atEnd else {
            throw ReplayError("Inserting cards moved the scroll position")
        }
        try await installTasks(2, revision: 3, authority: authority)
        try await Task.sleep(for: .milliseconds(700))
        guard canvas.presentedPlacements.count == 2, camera.maximumOffset == 0, camera.scrollOffset == 0 else {
            throw ReplayError("Removing cards did not clamp the offset to the new range")
        }
        let record: [String: Any] = ["denseCount": frames.count, "trailingOffset": atEnd, "clickedCard": target.id,
            "cardFrames": frames.map { [$0.minX, $0.minY, $0.width, $0.height] },
            "backgroundPoint": [blank.x, blank.y], "backgroundDragAndClickStable": true,
            "readerReturnOffset": atEnd, "insertOffset": atEnd,
            "removedOffset": camera.scrollOffset, "window": [size.width, size.height]]
        try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appending(path: "overview-scroll.json"))
    }

    private func fittingCards(_ window: NSWindow, directory: URL, authority: UUID) async throws {
        let canvas = presentation.canvas
        let camera = canvas.camera
        var previousSolve = canvas.layoutSolveCount
        func settle(width: CGFloat, count: Int) async throws {
            let deadline = ContinuousClock.now + .seconds(4)
            while camera.viewport?.width != width || canvas.presentedPlacements.count != count
                    || !canvas.canScroll || canvas.layoutSolveCount == previousSolve {
                guard ContinuousClock.now < deadline else { throw ReplayError("Fit fixture did not settle at \(width)pt") }
                try await Task.sleep(for: .milliseconds(25))
            }
            previousSolve = canvas.layoutSolveCount
        }
        func wheel(_ x: CGFloat, _ y: CGFloat, precise: Bool = true,
                   phase: NSEvent.Phase = .began, momentum: NSEvent.Phase = []) throws {
            guard let content = window.contentView,
                  let monitor = descendant(NativeOverviewScrollInput.MonitorView.self, in: content) else {
                throw ReplayError("Missing mounted scroll input")
            }
            let point = CGPoint(x: monitor.configuration.size.width - 8, y: 220)
            guard monitor.handle(WheelSample(window: window, point: monitor.windowPoint(point), x: x, y: y,
                    precise: precise, phase: phase, momentum: momentum)) == nil else {
                throw ReplayError("Fit fixture wheel missed the canvas: size=\(monitor.configuration.size), "
                    + "delta=\(x),\(y), phase=\(phase), momentum=\(momentum), enabled=\(monitor.enabled()), "
                    + "canStart=\(monitor.canStart(at: point)), owner=\(String(describing: monitor.sequence.owner)), "
                    + "pause=\(canvas.interactionPauseReasons)")
            }
        }
        func checkFit(width: CGFloat) throws {
            let before = camera.transform
            let frames = canvas.presentedPlacements.compactMap { canvas.displayedFrame(for: $0.id) }
            let union = frames.reduce(CGRect.null) { $0.union($1) }
            guard frames.count == 12, union.width == 1328, union.midX == width / 2,
                  camera.maximumOffset == 0, camera.scrollOffset == 0 else {
                throw ReplayError("Four columns did not fit at \(width)pt: \(union), range=\(camera.maximumOffset)")
            }
            try wheel(-80, 14)
            try wheel(0, 0, phase: .ended)
            try wheel(-50, 0, phase: [], momentum: .began)
            try wheel(0, 0, phase: [], momentum: .ended)
            try wheel(80, 0, precise: false, phase: [])
            guard camera.transform == before, camera.scrollOffset == 0 else {
                throw ReplayError("Input moved a fitting grid")
            }
        }

        window.setContentSize(CGSize(width: 1360, height: 704))
        try await installTasks(13, revision: 4, authority: authority, firstTagCount: 12)
        try await settle(width: 1360, count: 13)
        try wheel(-10000, 0)
        let beforeFilter = camera.scrollOffset
        guard beforeFilter > 0, let filter = presentation.overview.selectedDirectory?.children.first(where: { $0.tag == "Work" }) else {
            throw ReplayError("Missing overflow or directory filter")
        }
        presentation.overview.selectTag(filter)
        try await settle(width: 1360, count: 12)
        try checkFit(width: 1360)

        window.setContentSize(CGSize(width: 1359, height: 704))
        try await settle(width: 1359, count: 12)
        try wheel(-10000, 0)
        let beforeResize = camera.scrollOffset
        guard beforeResize > 0, beforeResize == camera.maximumOffset else { throw ReplayError("Cannot reach trailing edge") }
        window.setContentSize(CGSize(width: 1376, height: 704))
        try await settle(width: 1376, count: 12)
        try checkFit(width: 1376)
        if CommandLine.arguments.contains("--capture") { try await capture(window, to: directory.appending(path: "four-columns.png")) }
        let record: [String: Any] = ["gridWidth": 1328, "exactFitWidth": 1360, "windowWidth": 1376,
            "offsetBeforeFilter": beforeFilter, "offsetBeforeResize": beforeResize, "finalOffset": camera.scrollOffset]
        try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appending(path: "overview-fit.json"))
    }

    private func statusFilters(_ window: NSWindow, directory: URL, authority: UUID) async throws {
        let model = presentation.overview, canvas = presentation.canvas
        let running = ["Executing", "Permission", "Background", "Submitting"]
        let backlog = (1...8).map { "Backlog-\($0)" }
        let ordinary = running + ["Delivered", "Stopped", "Idle"] + backlog
        let inboxTasks = ["Inbox tagged", "Inbox untagged", "Inbox label"]
        let namedFolderTask = "Directory named Inbox"
        let reportIDs = (1...8).map { "Report-\($0)" }
        let finishedAt = 1_790_000_000_000.0
        let permission = PublicInteraction(id: "permission", kind: .permission, title: "Review request",
            actions: [.init(id: "allow", intent: .allow, label: "Allow")], questions: [])
        func thread(_ name: String, _ status: PublicExecution.Status?, revision: Int = 1, semanticTag: JSONText? = nil) throws -> JSONValue {
            let runID = "run-" + name.replacingOccurrences(of: " ", with: "-")
            let execution = try status.map { status in
                try PublicExecution(executionID: JSONText(runID), status: status, startedAt: finishedAt - 33_000,
                    finishedAt: [.completed, .interrupted, .failed].contains(status) ? finishedAt : nil,
                    interactions: status == .waitingForUser ? [permission] : [])
            }
            let observation = ThreadPublicObservation(latestExecution: execution, backgroundWork: name == "Background" ? .init() : nil)
            let inbox = inboxTasks.contains(name)
            let defaultTag: JSONText? = switch name {
            case "Inbox untagged", "Directory only": nil
            case "Inbox label": "Inbox"
            case "Delivered", "Inbox tagged": "Shipping"
            default: "Development"
            }
            let tag = semanticTag ?? defaultTag
            let emoji: JSONText = switch tag?.string {
            case "Shipping": "📦"
            case "Design": "🎨"
            case "Planning": "🗓️"
            case "Support": "🎧"
            case "Customer experience and international release coordination": "🌎"
            default: "🔧"
            }
            let folder: JSONText = name == namedFolderTask ? "/other/Inbox" : "/fixture"
            let label: JSONText = name == namedFolderTask ? "Inbox" : "Fixture"
            var sessionState = JSONValue.null
            var settings: [JSONText: JSONValue] = [:]
            var metadata: JSONValue?
            if name == "Delivered" || name == "Inbox tagged" {
                settings = ["model": .text("gpt-6.1-terra"), "thinking": .object(["mode": .text("effort"), "effort": .text("medium")])]
                metadata = .object(["kind": .text("generated-thread-metadata"), "emoji": .text("📈")])
                if status == .completed {
                    let turn: JSONValue = .object(["executionId": .text(runID), "status": .text("completed"),
                        "createdAt": .number(finishedAt - 33_000), "updatedAt": .number(finishedAt), "finishedAt": .number(finishedAt),
                        "answer": .text("Market summary is ready."), "reasoning": .text(""),
                        "usage": .object(["inputTokens": .integer(800), "outputTokens": .integer(47)]),
                        "messages": .array([]), "timeline": .array([]), "activities": .array([]),
                        "interactions": .array([]), "notices": .array([]), "plan": .array([])])
                    sessionState = .object(["schema": .text("mokusei.harness.codex.thread.v1"), "updatedAt": .number(finishedAt),
                        "turns": .array([turn]), "backgroundTerminals": .array([])])
                }
            }
            let thread = try HarnessThread(id: JSONText(name), harnessID: "codex", revision: revision, sessionState: sessionState,
                observation: observation, cwd: inbox ? "" : folder, settings: .object(settings),
                createdAt: finishedAt - 60_000, updatedAt: finishedAt + 86_400_000,
                title: JSONText(name), tags: tag.map { [$0] } ?? [], metadataState: metadata,
                tagEmojis: tag.map { [$0: emoji] } ?? [:],
                directoryTag: inbox ? "" : label, directoryScope: inbox ? "inbox" : folder)
            var fields = thread.json.objectValue!
            fields["pendingInput"] = .bool(name == "Submitting")
            return .object(fields)
        }
        var directoryReport = reportFixtures(["Directory-only report"])[0].objectValue!
        directoryReport["tags"] = .object(["tags": .array([.text("Fixture")]), "semanticTags": .array([]),
            "directoryTags": .array([.text("Fixture")]), "tagEmojis": .object([:])])
        directoryReport["presentations"] = .array([.object(["id": .text("mokusei.overview"),
            "apiVersion": .integer(1), "schemaVersion": .integer(1),
            "value": .object(["coversExecutions": .array([.object([
                "thread": ApplicationThreadRef(threadID: "Delivered", typeID: "agent").json,
                "executionId": .text("run-Delivered")])])])])])
        let fixtures = try [thread("Executing", .running), thread("Permission", .waitingForUser),
            thread("Background", .completed), thread("Submitting", nil), thread("Delivered", .completed),
            thread("Stopped", .interrupted), thread("Idle", nil), thread("Failed", .failed), thread(namedFolderTask, nil), thread("Directory only", nil)] + (inboxTasks + backlog).map { try thread($0, $0 == "Inbox tagged" ? .completed : nil) }
        window.setContentSize(CGSize(width: 1024, height: 704))
        model.selectTag(nil)
        try await installTasks(0, revision: 8, authority: authority,
            reports: reportFixtures(reportIDs.map { JSONText($0) }) + [.object(directoryReport)], extraThreads: fixtures)
        guard let content = window.contentView,
              let monitor = descendant(NativeOverviewScrollInput.MonitorView.self, in: content) else {
            throw ReplayError("Status replay has no window scroll router")
        }
        let tags = model.visibleFilters
        let tagIDs = tags.flatMap { [$0.id] + $0.children.map(\.id) }
        var samples = [[String: Any]]()
        var deliveredGaps: [String: CGFloat] = [:]
        func logoImage(_ identifier: String) -> NSImageView? {
            descendant(NSImageView.self, in: content) { $0.accessibilityIdentifier() == identifier }
        }
        var selectedFaces = [String: [Double]](), idleFaces = [String: [Double]]()
        func readFaces(_ expected: [String: Bool], in image: URL) throws -> [String: [Double]] {
            guard let pixels = NSBitmapImageRep(data: try Data(contentsOf: image)) else {
                throw ReplayError("Cannot read mounted filter faces")
            }
            var faces = [String: [Double]]()
            for (id, selected) in expected {
                let frame = window.convertFromScreen(try filterButton(id, in: window).frame)
                let glyphX = frame.minX
                let top = CGRect(x: glyphX, y: window.frame.height - frame.maxY, width: frame.height, height: frame.height)
                let rgb = filterFaceRGB(pixels, at: top, scale: CGFloat(pixels.pixelsWide) / window.frame.width)
                faces[id] = rgb
                // Dark Aqua frames check ink contrast on separate backdrops.
                // Keep their RGB in the receipt and compare tint within the original appearance.
                if captureScheme != .dark {
                    if selected { selectedFaces[id] = rgb } else { idleFaces[id] = rgb }
                }
            }
            return faces
        }
        func checkEmptyCopy(in url: URL, mode: NativeOverviewStatusFilter) throws -> [String] {
            let running = workspace.locale.text("没有运行中的会话", "No running conversations")
            let completed = workspace.locale.text("没有已完成的会话", "No completed conversations")
            let isRunning = mode == .running
            return try checkStatusText(in: url, expected: [isRunning ? running : completed], absent: [
                isRunning ? completed : running,
                workspace.locale.text("在右半区上滑可查看全部状态", "Scroll up on the right to show all statuses"),
                workspace.locale.text("在右半区下滑可查看全部状态", "Scroll down on the right to show all statuses")
            ]).map(\.text)
        }
        func normalized(_ text: String) -> String {
            text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        }
        func checkStatusText(in url: URL, expected: [String], absent: [String] = [], region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) throws -> [(text: String, frame: CGRect)] {
            let lines = try recognizedLines(in: url, languages: workspace.locale == .chinese ? ["zh-Hans", "en-US"] : ["en-US"], region: region)
            let actual = lines.map { normalized($0.text) }
            guard expected.allSatisfy({ text in actual.contains { $0.contains(normalized(text)) } }),
                  absent.allSatisfy({ text in !actual.contains { $0.contains(normalized(text)) } }) else {
                throw ReplayError("Unexpected visible text in \(url.lastPathComponent): expected=\(expected), absent=\(absent), found=\(lines.map(\.text))")
            }
            return lines
        }
        func check(_ name: String, _ mode: NativeOverviewStatusFilter, _ expected: [String],
                   selected: String = "Fixture", needsBothReportCards: Bool = false, checkDeliveredLayout: Bool = false) async throws {
            let deadline = ContinuousClock.now + .seconds(5)
            while Set(model.items.map(\.id)) != canvas.mountedCardIDs || canvas.isLayingOut {
                guard ContinuousClock.now < deadline else { throw ReplayError("Cards did not settle at " + name) }
                try await Task.sleep(for: .milliseconds(30))
            }
            var agents = [String](), documents = [String](), collected = [String]()
            for item in model.items {
                switch model.snapshot(for: item) {
                case .harness(let card): agents.append(card.input.thread.id.string)
                case .application(_, let card): documents.append(card.entry.ref.threadID.string)
                case .collection(_, let members): collected += members.map(\.entry.ref.threadID.string)
                case nil: throw ReplayError("Missing mounted snapshot at " + name)
                }
            }
            let visibleTags = model.visibleFilters.flatMap { [$0.id] + $0.children.map(\.id) }
            guard model.statusFilter == mode, model.selectedTag == selected, visibleTags == tagIDs,
                  (agents + documents + collected).sorted() == expected.sorted(),
                  !needsBothReportCards || (!documents.isEmpty && !collected.isEmpty),
                  !presentation.scene.notePanelOpen else {
                throw ReplayError("Unexpected \(name): mode=\(model.statusFilter), agents=\(agents), reports=\(documents), grouped=\(collected), tags=\(visibleTags), selected=\(model.selectedTag)")
            }
            let expectsStatusEmpty = mode != .all && expected.isEmpty
            var logo = logoImage("overview.status.empty.logo")
            while (logo != nil) != expectsStatusEmpty, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(30))
                logo = logoImage("overview.status.empty.logo")
            }
            let invalidLogo = logo.map {
                $0.isAccessibilityElement() || $0.image == nil || $0.bounds.size != CGSize(width: 195, height: 85)
            } ?? false
            guard (logo != nil) == expectsStatusEmpty, !invalidLogo else {
                if CommandLine.arguments.contains("--capture") {
                    try await capture(window, to: directory.appending(path: "failed-" + name + ".png"))
                }
                throw ReplayError("Unexpected logo at \(name): \(String(describing: logo?.bounds.size))")
            }
            var sample: [String: Any] = ["step": name, "status": mode.rawValue, "selectedTag": selected, "scope": model.selectedScope, "visibleTags": visibleTags,
                "agents": agents, "individualReports": documents, "collectionMembers": collected,
                "mountedCardCount": canvas.mountedCardIDs.count, "noteOpen": presentation.scene.notePanelOpen,
                "cardViewport": [canvas.cardRegionInWindow.minX, canvas.cardRegionInWindow.width]]
            if let logo {
                let frame = logo.convert(logo.bounds, to: content)
                // At y=200 in the 624 px source, the bowl spans x=60…404.
                let bowlCenter = frame.minX + frame.width * 232 / 624
                let centerError = bowlCenter - content.bounds.midX
                guard abs(centerError) <= 1, content.bounds.contains(frame) else {
                    throw ReplayError("Skillet at \(name) is clipped or off center by \(centerError) pt")
                }
                sample["bowlCenterErrorPt"] = centerError
                sample["logoSize"] = [logo.bounds.width, logo.bounds.height]
            }
            if CommandLine.arguments.contains("--capture") {
                let url = directory.appending(path: "status-" + name + ".png")
                if expectsStatusEmpty || checkDeliveredLayout { try await Task.sleep(for: .milliseconds(450)) }
                try await capture(window, to: url)
                if ["all", "directory-running", "directory-selected", "inbox-label"].contains(name) {
                    var expectedFaces = ["overview-status-running": mode == .running]
                    if let folder = tags.first(where: { $0.scope == "/fixture" }) {
                        expectedFaces[folder.id] = model.selectedScope == folder.scope
                    }
                    sample["faceRGB"] = try readFaces(expectedFaces, in: url)
                }
                if expectsStatusEmpty {
                    sample["emptyText"] = try checkEmptyCopy(in: url, mode: mode)
                } else if checkDeliveredLayout {
                    let locale = workspace.locale
                    let title = locale.text("已完成", "Completed")
                    let button = try filterButton("overview-status-completed", in: window)
                    guard button.label == title || button.title == title else {
                        throw ReplayError("Completed status icon lost its localized accessible name")
                    }
                    guard let frame = canvas.displayedFrame(for: "Inbox tagged") else {
                        throw ReplayError("Missing the displayed Delivered card in \(name)")
                    }
                    let corner = monitor.windowPoint(CGPoint(x: frame.minX, y: frame.maxY))
                    let region = CGRect(x: corner.x / window.frame.width, y: corner.y / window.frame.height,
                                        width: frame.width / window.frame.width, height: frame.height / window.frame.height)
                    let model = "gpt-6.1-terra"
                    let excerpt = "Market summary is ready"
                    let completion = locale.text("已完成", "Completed")
                    let lines = try checkStatusText(in: url, expected: ["Inbox tagged", model, "medium", excerpt],
                        absent: [completion], region: region)
                    let expectedLabels = [locale.text("用时：00:00:33", "Duration: 00:00:33"), "847 tokens", "Codex · " + completion]
                    let labels = accessibilityLabels(window) + accessibilityLabels(content)
                    guard expectedLabels.allSatisfy(labels.contains) else {
                        throw ReplayError("Missing card accessibility labels in \(name): expected=\(expectedLabels), found=\(labels)")
                    }
                    guard let modelFrame = lines.first(where: { normalized($0.text).contains(normalized(model)) })?.frame,
                          let excerptFrame = lines.first(where: { normalized($0.text).contains(normalized(excerpt)) })?.frame else {
                        throw ReplayError("Missing model or excerpt bounds in \(name)")
                    }
                    let gap = (modelFrame.midY - excerptFrame.midY) * frame.height
                    if let otherGap = deliveredGaps[locale.rawValue], abs(gap - otherGap) > 2 {
                        throw ReplayError("Delivered card metadata shifted between status filters in \(locale.rawValue): \(gap) vs \(otherGap)pt")
                    }
                    deliveredGaps[locale.rawValue] = gap
                    sample["locale"] = locale.rawValue
                    sample["deliveredText"] = lines.map(\.text)
                    sample["deliveredAccessibilityLabels"] = expectedLabels
                    sample["modelToExcerptPt"] = gap
                }
            }
            samples.append(sample)
        }
        func waitForFilterInput() async throws {
            let deadline = ContinuousClock.now + .seconds(4)
            while monitor.swipeActions?.available() != true || monitor.swipeActions?.canFilter() != true {
                guard ContinuousClock.now < deadline else {
                    throw ReplayError("Status input did not become available: pause=\(canvas.interactionPauseReasons), "
                        + "inputReady=\(presentation.scene.inputInteractionReady), key=\(window.isKeyWindow)")
                }
                try await Task.sleep(for: .milliseconds(25))
            }
        }
        func windowPoint(right: Bool) -> CGPoint {
            let bounds = content.convert(content.bounds, to: nil)
            return CGPoint(x: bounds.minX + bounds.width * (right ? 0.76 : 0.24), y: bounds.midY)
        }
        func swipe(up: Bool, right: Bool = true, crossCenter: Bool = false) async throws {
            let y: Int32 = up ? 40 : -40
            try await waitForFilterInput()
            let start = windowPoint(right: right)
            let end = crossCenter ? windowPoint(right: !right) : start
            // Cross the midpoint before reaching the recognition threshold.
            try await postScroll(window, start, y: y > 0 ? 8 : -8, phase: .began)
            try await postScroll(window, end, y: y, phase: .changed)
            try await postScroll(window, end, y: y * 2, phase: .changed)
            try await postScroll(window, end, y: 0, phase: .ended)
            try await postScroll(window, end, y: y, phase: nil, momentum: .begin)
            try await postScroll(window, end, y: 0, phase: nil, momentum: .end)
        }
        func wheel(_ y: Int32, right: Bool) async throws {
            try await waitForFilterInput()
            try await postScroll(window, windowPoint(right: right), y: y, phase: nil, precise: false)
        }
        func activate(_ group: NativeOverviewControlGroup, _ id: String) async throws {
            let deadline = ContinuousClock.now + .seconds(4)
            while !model.chromeInteractions.mountedIDs(in: group).contains(id) {
                guard ContinuousClock.now < deadline else { throw ReplayError("Filter did not mount: " + id) }
                try await Task.sleep(for: .milliseconds(25))
            }
            try presentation.performOverviewInteraction(.overviewActivateFilter(group, id))
        }
        func updateThread(_ name: String, _ status: PublicExecution.Status, revision: Int) async throws {
            let updated = try thread(name, status, revision: revision)
            let patch: JSONValue = .object(["type": .text("state-patched"), "baseRevision": .integer(revision - 1),
                "revision": .integer(revision), "threads": .object(["upserts": .array([updated]), "removedIds": .array([])])])
            let next = try RuntimeState.applying(patch, to: workspace.state!)
            await workspace.installPrepared(next, event: .mutation(patch, state: next, authority: authority))
        }
        guard let parent = tags.first(where: { $0.scope == "/fixture" }),
              let development = parent.children.first(where: { $0.tag == "Development" }),
              let shipping = parent.children.first(where: { $0.tag == "Shipping" }),
              !tags.contains(where: { $0.scope == "inbox" && $0.isDirectory }),
              let inboxShipping = tags.first(where: { $0.scope == "inbox" && $0.tag == "Shipping" && !$0.isDirectory }),
              let inboxLabel = tags.first(where: { $0.scope == "inbox" && $0.tag == "Inbox" && !$0.isDirectory }),
              let namedFolder = tags.first(where: { $0.scope == "/other/Inbox" && $0.isDirectory }) else {
            throw ReplayError("Missing scoped Shipping controls")
        }
        let allCards = ordinary + reportIDs
        try await check("all", .all, allCards)
        try await waitForFilterInput()
        let panPoint = monitor.windowPoint(CGPoint(x: canvas.cardRegionInWindow.width * 0.8, y: content.bounds.height - 8))
        let startOffset = canvas.camera.scrollOffset
        try await postScroll(window, panPoint, y: 0, phase: nil, x: -2, precise: false)
        let wheelOffset = canvas.camera.scrollOffset
        guard wheelOffset > startOffset, model.statusFilter == .all, model.selectedFilter?.id == parent.id else {
            throw ReplayError("Line wheel failed in \(model.selectedTag): offset \(startOffset) → \(wheelOffset) of \(canvas.camera.maximumOffset)")
        }
        try await postScroll(window, panPoint, y: 0, phase: nil, x: 2, precise: false)
        samples.append(["step": "populated-wheel", "windowPoint": [panPoint.x, panPoint.y],
                        "startOffset": startOffset, "wheelOffset": wheelOffset])
        try await swipe(up: false, right: false)
        try await check("directory-left-upper-limit", .all, allCards)
        let semanticIDs = parent.children.map(\.id)
        guard model.railChoices.map(\.id) == semanticIDs + ["running"],
              model.chromeInteractions.mountedIDs(in: .status) == ["running"] else {
            throw ReplayError("Directory Running did not follow its semantic tags")
        }
        try await swipe(up: true, crossCenter: true)
        try await check("right-to-development", .all, ordinary.filter { $0 != "Delivered" } + reportIDs, selected: development.tag)
        try await swipe(up: true, right: false)
        try await check("left-to-shipping", .all, ["Delivered"], selected: shipping.tag)
        try await swipe(up: true)
        try await check("directory-running", .running, running)
        try await swipe(up: true, right: false)
        try await check("last-tag-stops", .running, running)
        try await updateThread("Delivered", .running, revision: 9)
        try await check("directory-live-admit", .running, running + ["Delivered"])
        try await updateThread("Delivered", .completed, revision: 10)
        try await check("directory-live-remove", .running, running)
        try await swipe(up: false, crossCenter: true)
        try await check("right-to-shipping", .all, ["Delivered"], selected: shipping.tag)
        let windowedSize = window.frame.size
        window.collectionBehavior = [.fullScreenPrimary]
        func fullscreen(_ enter: Bool) async throws {
            let notification = enter ? NSWindow.didEnterFullScreenNotification : NSWindow.didExitFullScreenNotification
            let finished = NotificationCenter.default.notifications(named: notification, object: window).makeAsyncIterator()
            window.toggleFullScreen(nil)
            _ = await finished.next()
            try await focusReplayWindow(window)
            let deadline = ContinuousClock.now + .seconds(6)
            while window.styleMask.contains(.fullScreen) != enter
                    || window.frame.size != (enter ? window.screen?.frame.size : windowedSize)
                    || monitor.configuration.size != content.bounds.size || canvas.isLayingOut {
                guard ContinuousClock.now < deadline else { throw ReplayError("Native full screen did not settle") }
                try await Task.sleep(for: .milliseconds(50))
            }
            try await waitForFilterInput()
        }
        try await fullscreen(true)
        let bounds = content.convert(content.bounds, to: nil)
        for x in [bounds.maxX - 8, bounds.minX + 8] {
            let point = CGPoint(x: x, y: bounds.midY + bounds.height * 0.32)
            try await postScroll(window, point, y: 40, phase: .began)
            try await postScroll(window, point, y: 0, phase: .ended)
            try await postScroll(window, point, y: -60, phase: nil, momentum: .begin)
            try await postScroll(window, point, y: 0, phase: nil, momentum: .end)
            if model.statusFilter != .running {
                try await capture(window, to: directory.appending(path: "failed-fullscreen.png"))
                let hit = content.hitTest(content.superview?.convert(point, from: nil) ?? point)
                throw ReplayError("Fullscreen swipe missed at \(point), bounds=\(bounds), hit=\(String(describing: hit)), "
                    + "key=\(window.isKeyWindow), activeSpace=\(window.isOnActiveSpace), visible=\(presentation.scene.windowVisible), "
                    + "monitorAttached=\(monitor.window === window), canFilter=\(monitor.swipeActions?.canFilter() == true), "
                    + "available=\(monitor.swipeActions?.available() == true), choices=\(model.railChoices.map(\.id))")
            }
            try await check("fullscreen-running-" + (x > bounds.midX ? "right" : "left"), .running, running)
            guard let card = canvas.visibleFrame(for: "Executing") else { throw ReplayError("Missing fullscreen running card") }
            let cardPoint = monitor.windowPoint(CGPoint(x: card.midX, y: card.midY))
            try await postScroll(window, cardPoint, y: -40, phase: .began)
            try await postScroll(window, cardPoint, y: 0, phase: .ended)
            try await check("fullscreen-card-down", .all, ["Delivered"], selected: shipping.tag)
        }
        try await fullscreen(false)
        try await activate(.directory, parent.id)
        // The canvas can settle before AppKit publishes the updated toolbar accessibility tree.
        let toolbarDeadline = ContinuousClock.now + .seconds(4)
        while (try? filterButton(parent.id, in: window)) == nil, ContinuousClock.now < toolbarDeadline {
            try await Task.sleep(for: .milliseconds(30))
        }
        let folderButton = try filterButton(parent.id, in: window)
        let shippingButton = try filterButton(inboxShipping.id, in: window)
        let inboxButton = try filterButton(inboxLabel.id, in: window)
        let left = try filterButton(development.id, in: window)
        let runningButton = try filterButton("overview-status-running", in: window)
        let heights = [folderButton, shippingButton, inboxButton, runningButton].map { $0.frame.height }
        // AppKit includes the unread badge above the compact circle in the button's AX frame.
        let badgeRise = development.unreadCount > 0 ? 3.5 * OverviewTagMetrics.tagScale : 0
        guard (try? filterButton("overview-semantic-any", in: window)) == nil,
              !model.chromeInteractions.mountedIDs(in: .semantic).contains(parent.id),
              abs(left.frame.width - 46.2) <= 1, abs(left.frame.height - 46.2 - badgeRise) <= 1,
              heights.allSatisfy({ abs($0 - 46.2) <= 1 }),
              [shippingButton, inboxButton].allSatisfy({ abs($0.frame.midY - folderButton.frame.midY) <= 1 }),
              Set(model.chromeInteractions.mountedIDs(in: .directory)) == [parent.id, namedFolder.id] else {
            throw ReplayError("Incorrect tag controls: heights=\(heights), left=\(left.frame.size), badge=\(badgeRise)")
        }
        samples.append(["step": "tag-heights", "points": heights, "compactLeftWidth": left.frame.width,
                        "leftHeightWithBadge": left.frame.height, "leftUnread": development.unreadCount])
        let notice = try accessibleControl("workspace.runtime.connection-notice", role: .group, in: window).frame
        let clearance = [folderButton, shippingButton, inboxButton].map { $0.frame.minY - notice.maxY }
        guard !notice.isEmpty, clearance.allSatisfy({ $0 > 0 }) else {
            throw ReplayError("Runtime notice overlaps a top filter. Screen-space gaps: \(clearance)")
        }
        samples.append(["step": "sync-notice-header-clearance", "gapsPt": clearance])
        let shippingCenter = window.convertPoint(fromScreen: CGPoint(x: shippingButton.frame.midX, y: shippingButton.frame.midY))
        try click(window, at: shippingCenter)
        try await check("inbox-top-resets-status", .all, ["Inbox tagged"], selected: inboxShipping.tag)
        guard model.railChoices.map(\.id) == ["running", "all", "completed"] else {
            throw ReplayError("Inbox tag lost its status order")
        }
        for id in ["running", "all", "completed"] {
            let frame = window.convertFromScreen(try filterButton("overview-status-" + id, in: window).frame)
            guard abs(frame.minX - 12) <= 1 else { throw ReplayError("Inbox control is outside the left column") }
        }
        try await swipe(up: true, right: false)
        try await check("inbox-left-completed", .completed, ["Inbox tagged"], selected: inboxShipping.tag)
        try await activate(.semantic, inboxLabel.id)
        try await check("inbox-label", .all, ["Inbox label"], selected: inboxLabel.tag)
        try await activate(.directory, namedFolder.id)
        try await check("directory-named-inbox", .all, [namedFolderTask], selected: namedFolder.tag)
        guard model.railChoices.map(\.id) == ["running"] else { throw ReplayError("Expected a running-only directory rail") }
        try await swipe(up: true)
        try await check("empty-directory-running", .running, [], selected: namedFolder.tag)
        try await activate(.directory, parent.id)
        try await check("directory-restores-shipping", .all, ["Delivered"], selected: shipping.tag)
        try await activate(.directory, parent.id)
        try await check("directory-selected", .all, ordinary + reportIDs)
        let cardViewport = canvas.cardRegionInWindow
        guard cardViewport == CGRect(origin: .zero, size: content.bounds.size) else { throw ReplayError("A filter consumed card space") }
        let developmentFrame = try filterButton(development.id, in: window).frame
        try click(window, at: window.convertPoint(fromScreen: CGPoint(x: developmentFrame.midX, y: developmentFrame.midY)))
        try await check("mouse-development", .all, ordinary.filter { $0 != "Delivered" } + reportIDs, selected: development.tag)
        try await waitForFilterInput()
        try swipeWithNaturalScrolling(monitor, in: window, at: windowPoint(right: true), up: true)
        try await check("shipping-natural-scrolling", .all, ["Delivered"], selected: shipping.tag)
        try await activate(.directory, namedFolder.id)
        try await check("restore-empty-running", .running, [], selected: namedFolder.tag)
        try await activate(.semantic, inboxShipping.id)
        try await check("inbox-clears-running", .all, ["Inbox tagged"], selected: inboxShipping.tag)
        let originalLocale = workspace.locale
        defer { workspace.updateSystemLocale(originalLocale) }
        workspace.updateSystemLocale(.chinese)
        try await swipe(up: false)
        try await check("empty-tag", .running, [], selected: "Shipping")
        if CommandLine.arguments.contains("--capture") {
            defer { captureScheme = nil }
            for (scheme, filename) in [(ColorScheme.light, "running-empty-light"), (.dark, "running-empty-dark")] {
                captureScheme = scheme
                try await Task.sleep(for: .milliseconds(450))
                let url = directory.appending(path: filename + ".png")
                try await capture(window, to: url)
                _ = try checkEmptyCopy(in: url, mode: .running)
            }
        }
        try await wheel(-1, right: true)
        try await check("empty-running-upper-limit", .running, [], selected: "Shipping")
        try await wheel(1, right: false)
        workspace.updateSystemLocale(.english)
        try await check("inbox-all", .all, ["Inbox tagged"], selected: "Shipping", checkDeliveredLayout: true)
        try await swipe(up: true)
        try await check("completed-tag", .completed, ["Inbox tagged"], selected: "Shipping", checkDeliveredLayout: true)
        try await updateThread("Inbox tagged", .running, revision: 11)
        try await check("completed-live-remove", .completed, [], selected: "Shipping")
        workspace.updateSystemLocale(.chinese)
        try await check("completed-empty-zh", .completed, [], selected: "Shipping")
        if CommandLine.arguments.contains("--capture") {
            defer { captureScheme = nil }
            for (scheme, filename) in [(ColorScheme.light, "completed-empty-light"), (.dark, "completed-empty-dark")] {
                captureScheme = scheme
                try await Task.sleep(for: .milliseconds(450))
                let url = directory.appending(path: filename + ".png")
                try await capture(window, to: url)
                _ = try checkEmptyCopy(in: url, mode: .completed)
                if scheme == .light {
                    try await recordWindow(window, to: directory.appending(path: "sleeping-skillet.mp4")) {
                        try await Task.sleep(for: .seconds(4))
                    }
                }
            }
        }
        try await wheel(1, right: true)
        try await check("empty-completed-lower-limit", .completed, [], selected: "Shipping")
        try await wheel(-1, right: true)
        try await check("back-from-completed-wheel", .all, ["Inbox tagged"], selected: "Shipping")
        try await swipe(up: false)
        try await check("inbox-running", .running, ["Inbox tagged"], selected: "Shipping")
        try await updateThread("Inbox tagged", .completed, revision: 12)
        try await check("inbox-running-live-remove", .running, [], selected: "Shipping")
        try await swipe(up: true)
        try await swipe(up: true)
        if CommandLine.arguments.contains("--capture") { captureScheme = .dark }
        try await check("completed-live-admit", .completed, ["Inbox tagged"], selected: "Shipping", checkDeliveredLayout: true)
        try await swipe(up: false)
        try await check("completed-finished", .all, ["Inbox tagged"], selected: "Shipping", checkDeliveredLayout: true)
        captureScheme = nil
        guard canvas.cardRegionInWindow == cardViewport else {
            throw ReplayError("Changing a tag or a status moved the card viewport")
        }
        if CommandLine.arguments.contains("--capture") {
            let cards = samples.filter { $0["modelToExcerptPt"] != nil }
            guard cards.count == 4 else { throw ReplayError("Missing a localized completed card capture") }
            try JSONSerialization.data(withJSONObject: cards, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appending(path: "overview-completed-card.json"))
        }
        if CommandLine.arguments.contains("--completed-card") { return }
        workspace.updateSystemLocale(.english)
        model.selectTag(nil)
        let captureFilters = CommandLine.arguments.contains("--capture")
        if captureFilters { captureScheme = .light }
        defer {
            captureScheme = nil
            brightCaptureBackdrop = false
        }
        window.setContentSize(CGSize(width: 860, height: 600))
        window.center()
        let longName = "Customer experience and international release coordination"
        let labels = [longName, "Design", "Engineering", "Running", "Support"]
        let compactTasks = try labels.enumerated().map { index, label in
            try thread("Compact-\(index)", index == 2 ? .running : nil, semanticTag: JSONText(label))
        }
        try await installTasks(0, revision: 13, authority: authority, extraThreads: compactTasks)
        guard let compactFolder = model.visibleFilters.first(where: { $0.scope == "/fixture" }),
              let longChild = compactFolder.children.first(where: { $0.tag == longName }) else {
            throw ReplayError("Minimum-size fixture is missing its long tag")
        }
        try await activate(.directory, compactFolder.id)
        let fixtureIDs = Set(labels.indices.map { "Compact-\($0)" })
        let layoutDeadline = ContinuousClock.now + .seconds(4)
        while Set(canvas.presentedPlacements.map(\.id)) != fixtureIDs || canvas.isLayingOut {
            guard ContinuousClock.now < layoutDeadline else {
                throw ReplayError("Minimum window did not settle on its five tag fixtures: \(canvas.presentedPlacements.map(\.id))")
            }
            try await Task.sleep(for: .milliseconds(30))
        }
        if captureFilters {
            try await recordWindow(window, to: directory.appending(path: "filter-switches.mp4")) {
                try await Task.sleep(for: .milliseconds(400))
                try await swipe(up: false)
                try await Task.sleep(for: .milliseconds(600))
                try await swipe(up: true)
                try await Task.sleep(for: .milliseconds(600))
                try await swipe(up: true, right: false)
                try await Task.sleep(for: .milliseconds(600))
                try await activate(.directory, compactFolder.id)
                try await Task.sleep(for: .milliseconds(600))
            }
        }
        let fullViewport = CGRect(origin: .zero, size: content.bounds.size)
        guard canvas.cardRegionInWindow == fullViewport else { throw ReplayError("Filters consumed card layout space") }
        // The camera starts with a 64pt inset. Pan a column beneath the left
        // controls so the pass-through test actually has a card to hit.
        func placeCardsUnderRail() async throws {
            canvas.camera.scroll(by: 160 - canvas.camera.scrollOffset)
            try await Task.sleep(for: .milliseconds(120))
        }
        try await placeCardsUnderRail()
        // Measure the actual left buttons. A visible button intercepts the click;
        // the vertical gap between its glass and the next button belongs to the card.
        let buttons = try compactFolder.children.map { tag in
            (tag, window.convertFromScreen(try filterButton(tag.id, in: window).frame))
        }
        let overlap = zip(buttons, buttons.dropFirst()).compactMap { upper, lower -> (String, CGPoint, CGPoint, String)? in
            let chip = monitor.canvasPoint(CGPoint(x: upper.1.midX, y: upper.1.midY))
            let gap = monitor.canvasPoint(CGPoint(x: upper.1.midX, y: (upper.1.minY + lower.1.maxY) / 2))
            guard let card = canvas.presentedPlacements.first(where: {
                guard let frame = canvas.visibleFrame(for: $0.id) else { return false }
                return frame.contains(chip) && frame.contains(gap)
            }) else { return nil }
            return (card.id, chip, gap, upper.0.id)
        }.first
        guard let (underlyingID, chip, gap, tagID) = overlap else { throw ReplayError("No card beneath a tag and its gap") }
        try await focusReplayWindow(window)
        try await postClick(window, at: monitor.windowPoint(chip))
        try await Task.sleep(for: .milliseconds(600))
        guard model.selectedRailID == tagID, presentation.selected == nil else {
            throw ReplayError("A tag over an Agent card failed to take the click")
        }
        try await activate(.directory, compactFolder.id)
        try await Task.sleep(for: .milliseconds(650))
        try await placeCardsUnderRail()
        guard canvas.visibleFrame(for: underlyingID)?.contains(gap) == true else {
            throw ReplayError("Returning to the directory lost the underlying card")
        }
        let gapPoint = monitor.windowPoint(gap)
        let gapHit = content.hitTest(content.superview?.convert(gapPoint, from: nil) ?? gapPoint)
        let gapActive = canvas.allowsActivation(cardID: underlyingID)
        try await postClick(window, at: gapPoint)
        try await Task.sleep(for: .milliseconds(850))
        guard presentation.selected?.threadID.string == underlyingID else {
            try await capture(window, to: directory.appending(path: "failed-status-gap.png"))
            throw ReplayError("A click between two tag capsules failed to open \(underlyingID), "
                + "point=\(gapPoint), frame=\(String(describing: canvas.visibleFrame(for: underlyingID))), "
                + "hit=\(String(describing: gapHit)), active=\(gapActive), pause=\(canvas.interactionPauseReasons), "
                + "selected=\(String(describing: presentation.selected)), status=\(model.statusFilter), key=\(window.isKeyWindow)")
        }
        presentation.showOverview()
        try await Task.sleep(for: .milliseconds(700))
        guard let shortChild = compactFolder.children.first(where: { $0.tag == "Design" }) else {
            throw ReplayError("Missing short label for the second selection")
        }
        let ids = compactFolder.children.map(\.id)
        let leftColumn = CGRect(x: 0, y: 0.16, width: 0.20, height: 0.68)
        let titles = ["Any tag", "Customer", "Design", "Engineering", "Running", "Support"]
        let runningID = "overview-status-running"
        let side: CGFloat = 46.2
        var phases = [[String: Any]]()
        func observe(_ name: String, expanded: [String: String], runningExpanded: Bool = false) async throws {
            var widths = [String: CGFloat]()
            for id in ids {
                let button = try filterButton(id, in: window)
                let frame = button.frame
                if id == longChild.id, !(button.title + button.label).contains(longName) {
                    throw ReplayError("Truncating the long tag changed its accessible name")
                }
                widths[id] = frame.width
                let local = window.convertFromScreen(frame)
                guard abs(local.minX - 12) <= 1, frame.width <= 142.9,
                      local.minY >= 0, local.maxY <= fullViewport.height, abs(frame.height - side) <= 1,
                      expanded[id] == nil ? abs(frame.width - side) <= 1 : frame.width > side + 1 else {
                    throw ReplayError("Unexpected \(name) button frame for \(id): \(frame), expanded=\(expanded)")
                }
            }
            let runningButton = try filterButton(runningID, in: window)
            let runningFrame = window.convertFromScreen(runningButton.frame)
            guard abs(runningFrame.minX - 12) <= 1, abs(runningFrame.height - side) <= 1,
                  runningExpanded ? runningFrame.width > side + 1 : abs(runningFrame.width - side) <= 1,
                  try ids.allSatisfy({ try filterButton($0, in: window).frame.minY > runningButton.frame.maxY }),
                  model.chromeInteractions.mountedIDs(in: .status) == ["running"] else {
                throw ReplayError("Unexpected position or selection of the built-in Running tag at " + name)
            }
            widths[runningID] = runningFrame.width
            var sample: [String: Any] = ["phase": name, "widths": widths]
            if CommandLine.arguments.contains("--capture") {
                let url = directory.appending(path: name + ".png")
                try await capture(window, to: url)
                sample["faceRGB"] = try readFaces(Dictionary(uniqueKeysWithValues: (ids + [runningID]).map {
                    ($0, $0 == runningID ? model.statusFilter == .running : $0 == model.selectedRailID)
                }), in: url)
                try checkGlyphInk(shortChild.id, centerInset: side / 2, in: url, window: window)
                let visible = Array(expanded.values) + (runningExpanded ? ["Running"] : [])
                sample["visibleTitles"] = try checkStatusText(in: url, expected: visible,
                    absent: titles.filter { !visible.contains($0) }, region: leftColumn).map(\.text)
            }
            phases.append(sample)
        }
        var originalCursor: CGPoint?
        defer { if let originalCursor { CGWarpMouseCursorPosition(originalCursor) } }
        func pointAt(_ point: CGPoint) async throws {
            if originalCursor == nil {
                guard let position = CGEvent(source: nil)?.location else { throw ReplayError("Missing fixture cursor") }
                originalCursor = position
            }
            try await movePointer(window, to: point)
        }
        // Sample selection independently of incidental hover.
        let away = monitor.windowPoint(CGPoint(x: fullViewport.midX, y: fullViewport.midY))
        let railIDs = ids + [runningID]
        if try railIDs.contains(where: { try filterButton($0, in: window).frame.contains(NSEvent.mouseLocation) }) {
            try await pointAt(away)
        }
        try await observe("folder-selected", expanded: [:])
        let first = ContinuousClock.now
        try await activate(.semantic, longChild.id)
        let settlingDeadline = first + .seconds(3)
        while Set(model.items.map(\.id)) != canvas.mountedCardIDs || canvas.isLayingOut {
            guard ContinuousClock.now < settlingDeadline else { throw ReplayError("Long tag's card did not settle") }
            try await Task.sleep(for: .milliseconds(30))
        }
        try await Task.sleep(for: .milliseconds(300))
        try await observe("minimum-window", expanded: [longChild.id: "Customer"])
        let registered = model.chromeInteractions.mountedIDs(in: .semantic)
        guard Set(registered) == Set(ids), ids.count == 5, model.selectedFilter?.id == longChild.id,
              content.bounds.size == CGSize(width: 860, height: 600),
              Set(model.items.map(\.id)) == canvas.mountedCardIDs,
              model.items.count == 1, canvas.cardRegionInWindow == fullViewport else {
            throw ReplayError("Minimum window did not settle: controls=\(registered), selected=\(model.selectedFilter?.id ?? "-"), size=\(content.bounds.size), items=\(model.items.map(\.id)), mounted=\(canvas.mountedCardIDs), region=\(canvas.cardRegionInWindow)")
        }
        try await activate(.semantic, shortChild.id)
        let design = [shortChild.id: "Design"]
        try await Task.sleep(for: .milliseconds(550))
        try await observe("second-selection", expanded: design)
        try await Task.sleep(for: .seconds(5))
        try await observe("selection-held", expanded: design)
        func waitForHoverMotion(_ id: String, expanded: Bool) async throws {
            var previous: CGFloat?
            var stable = 0
            let deadline = ContinuousClock.now + .seconds(1)
            var trace = [CGFloat]()
            while ContinuousClock.now < deadline {
                let width = try filterButton(id, in: window).frame.width
                trace.append(width)
                let reached = expanded ? width > side + 1 : abs(width - side) <= 1
                stable = reached && previous == width ? stable + 1 : 0
                if stable >= 2 { return }
                previous = width
                try await Task.sleep(for: .milliseconds(40))
            }
            throw ReplayError("Hover title for \(id) did not settle at cursor \(NSEvent.mouseLocation): \(trace)")
        }
        let hoverFrame = try filterButton(longChild.id, in: window).frame
        let hover = window.convertPoint(fromScreen: CGPoint(x: hoverFrame.maxX + 10, y: hoverFrame.midY))
        let beyond = window.convertPoint(fromScreen: CGPoint(x: hoverFrame.maxX + 16, y: hoverFrame.midY))
        try await pointAt(beyond)
        try await waitForHoverMotion(longChild.id, expanded: false)
        try await pointAt(hover)
        try await waitForHoverMotion(longChild.id, expanded: true)
        try await observe("hovered-tag", expanded: [longChild.id: "Customer", shortChild.id: "Design"])
        let expandedTitle = window.convertFromScreen(try filterButton(longChild.id, in: window).frame)
        if captureFilters {
            captureScheme = .dark
            try await Task.sleep(for: .milliseconds(450))
            try await observe("hovered-tag-dark", expanded: [longChild.id: "Customer", shortChild.id: "Design"])
            brightCaptureBackdrop = true
            try await Task.sleep(for: .milliseconds(450))
            try await observe("hovered-tag-dark-on-light", expanded: [longChild.id: "Customer", shortChild.id: "Design"])
            brightCaptureBackdrop = false
        }
        let gapBelowTag = window.convertPoint(fromScreen: CGPoint(x: hoverFrame.maxX + 10, y: hoverFrame.minY - 5))
        try await pointAt(gapBelowTag)
        try await waitForHoverMotion(longChild.id, expanded: false)
        try await observe("pointer-left", expanded: design)

        let runningFrame = window.convertFromScreen(try filterButton(runningID, in: window).frame)
        try await pointAt(CGPoint(x: runningFrame.maxX + 10, y: runningFrame.midY))
        try await waitForHoverMotion(runningID, expanded: true)
        try await observe("hovered-running", expanded: design, runningExpanded: true)
        workspace.updateSystemLocale(.chinese)
        try await Task.sleep(for: .milliseconds(450))
        let localized = try filterButton(runningID, in: window)
        guard localized.label == "运行中" || localized.title == "运行中" else { throw ReplayError("Missing 运行中") }
        let runningBounds = window.convertFromScreen(localized.frame)
        let titlePointRunning = CGPoint(x: (runningBounds.maxX + runningFrame.maxX) / 2, y: runningFrame.midY)
        try click(window, at: titlePointRunning)
        try await pointAt(away)
        try await Task.sleep(for: .milliseconds(550))
        guard model.selectedRailID == "running", model.items.map(\.id) == ["Compact-2"], presentation.selected == nil else {
            throw ReplayError("Running did not replace Design with the whole folder's running work")
        }
        if captureFilters {
            let url = directory.appending(path: "folder-running-zh.png")
            try await capture(window, to: url)
            let button = window.convertFromScreen(try filterButton(runningID, in: window).frame)
            let title = button.divided(atDistance: button.height, from: .minXEdge).remainder
            let region = CGRect(x: title.minX / window.frame.width, y: title.minY / window.frame.height,
                                width: title.width / window.frame.width, height: title.height / window.frame.height)
            _ = try checkStatusText(in: url, expected: ["运行中"], region: region)
        }
        workspace.updateSystemLocale(.english)
        try await Task.sleep(for: .milliseconds(450))
        try await observe("selected-running", expanded: [:], runningExpanded: true)
        try await swipe(up: false)
        try await Task.sleep(for: .milliseconds(500))
        guard model.statusFilter == .all, model.selectedTag == "Support" else {
            throw ReplayError("Swiping down from Running did not select the preceding semantic tag")
        }
        try await activate(.semantic, shortChild.id)
        try await Task.sleep(for: .milliseconds(550))
        try await observe("semantic-clears-running", expanded: design)
        try await activate(.directory, compactFolder.id)
        try await Task.sleep(for: .milliseconds(700))
        try await observe("folder-restores-all", expanded: [:])
        try await placeCardsUnderRail()
        let longBounds = window.convertFromScreen(try filterButton(longChild.id, in: window).frame)
        let titlePoint = CGPoint(x: longBounds.maxX + 10, y: longBounds.midY)
        guard expandedTitle.contains(titlePoint) else { throw ReplayError("Expanded label did not reach the hover margin") }
        let canvasPoint = monitor.canvasPoint(titlePoint)
        guard abs(longBounds.width - side) <= 1, let underLabel = canvas.presentedPlacements.first(where: {
            canvas.visibleFrame(for: $0.id)?.contains(canvasPoint) == true
        }) else { throw ReplayError("Compact tag fixture needs a card under the collapsed title") }
        try click(window, at: titlePoint)
        try await Task.sleep(for: .milliseconds(850))
        guard presentation.selected?.threadID.string == underLabel.id else {
            throw ReplayError("The collapsed title area did not pass its click to the card")
        }
        presentation.showOverview()
        try await Task.sleep(for: .milliseconds(700))
        try await pointAt(away)
        let returnedFrame = window.convertFromScreen(try filterButton(longChild.id, in: window).frame)
        try await pointAt(CGPoint(x: returnedFrame.minX + side / 2, y: returnedFrame.midY))
        try await waitForHoverMotion(longChild.id, expanded: true)
        let expandedBounds = window.convertFromScreen(try filterButton(longChild.id, in: window).frame)
        guard expandedBounds.contains(titlePoint) else { throw ReplayError("Hovered title did not reach the click") }
        try click(window, at: titlePoint)
        try await Task.sleep(for: .milliseconds(350))
        guard model.selectedFilter?.id == longChild.id, presentation.selected == nil else {
            throw ReplayError("The expanded title area did not select its tag over the card")
        }
        try await pointAt(away)
        try await Task.sleep(for: .milliseconds(500))
        try await observe("selected-tag-after-exit", expanded: [longChild.id: "Customer"])
        let compact: [String: Any] = ["step": "minimum-window", "visibleSemanticControls": registered,
            "window": [content.bounds.width, content.bounds.height], "selectedTag": model.selectedTag,
            "underlyingCard": underlyingID, "gapPoint": [gap.x, gap.y], "capsulePoint": [chip.x, chip.y],
            "cardViewport": [canvas.cardRegionInWindow.minX, canvas.cardRegionInWindow.width],
            "leftHoverOutsidePoints": 10,
            "tagTitlePoint": [titlePoint.x, titlePoint.y], "cardBeneathTitle": underLabel.id,
            "labelPhases": phases]
        samples.append(compact)
        if captureFilters {
            let switched = [compactFolder.id, longChild.id, shortChild.id, runningID]
            for id in switched {
                guard let tint = selectedFaces[id], let idle = idleFaces[id],
                      zip(tint, idle).contains(where: { abs($0 - $1) > 0.025 }) else {
                    throw ReplayError("Switching the filter left its glass face unchanged: " + id)
                }
            }
            // The stacked header places the directory glyph below the connection
            // notice so the same bright-surface sample includes its visible title.
            window.setContentSize(CGSize(width: 600, height: 600))
            brightCaptureBackdrop = true
            try await Task.sleep(for: .milliseconds(450))
            let url = directory.appending(path: "directory-dark-on-light.png")
            try await capture(window, to: url)
            try checkGlyphInk(compactFolder.id, centerInset: OverviewTagMetrics.chipLabelInset + OverviewTagMetrics.folderIcon / 2,
                in: url, window: window)
            _ = try checkStatusText(in: url, expected: ["Fixture"],
                region: CGRect(x: 0.20, y: 0.76, width: 0.60, height: 0.15))
            window.setContentSize(CGSize(width: 860, height: 600))
        }
        guard let namedRunning = compactFolder.children.first(where: { $0.tag == "Running" }),
              let support = compactFolder.children.first(where: { $0.tag == "Support" }) else {
            throw ReplayError("Missing semantic Running or Support")
        }
        try await activate(.semantic, namedRunning.id)
        guard model.selectedRailID == namedRunning.id, model.items.map(\.id) == ["Compact-3"] else {
            throw ReplayError("Semantic Running collided with the built-in tag")
        }
        try await activate(.status, "running")
        let added = try thread("Support-backlog", nil, semanticTag: "Support")
        let reorder: JSONValue = .object(["type": .text("state-patched"), "baseRevision": .integer(13), "revision": .integer(14),
            "threads": .object(["upserts": .array([added]), "removedIds": .array([])])])
        let reordered = try RuntimeState.applying(reorder, to: workspace.state!)
        await workspace.installPrepared(reordered, event: .mutation(reorder, state: reordered, authority: authority))
        let order = model.railChoices.map(\.id)
        guard order.count == 6, order.first == support.id, order.last == "running",
              model.selectedRailID == "running", model.items.map(\.id) == ["Compact-2"] else {
            throw ReplayError("Membership reorder moved or cleared the built-in Running tag: \(order)")
        }
        samples.append(["step": "reordered-with-semantic-running", "rail": order, "selected": "running"])
        try await installTasks(0, revision: 15, authority: authority, extraThreads: [thread("Inbox tagged", nil)])
        try await activate(.semantic, inboxShipping.id)
        guard model.visibleFilters.map(\.id) == [inboxShipping.id], model.selectedFilter?.id == inboxShipping.id,
              model.items.map(\.id) == ["Inbox tagged"] else { throw ReplayError("The sole Inbox tag was not selectable") }
        let scene = model.sceneKey
        let cardDeadline = ContinuousClock.now + .seconds(4)
        // The incoming card can accept activation before SwiftUI unmounts the outgoing card at the same center.
        while canvas.mountedCardIDs != ["Inbox tagged"] || !canvas.allowsActivation(cardID: "Inbox tagged") || canvas.isLayingOut {
            guard ContinuousClock.now < cardDeadline else {
                throw ReplayError("Single tagged card did not settle: mounted=\(canvas.mountedCardIDs.sorted())")
            }
            try await Task.sleep(for: .milliseconds(30))
        }
        guard let frame = canvas.visibleFrame(for: "Inbox tagged") else { throw ReplayError("Single tagged card was offscreen") }
        let point = monitor.windowPoint(CGPoint(x: frame.midX, y: frame.midY))
        try await focusReplayWindow(window)
        try await postClick(window, at: point)
        let readerDeadline = ContinuousClock.now + .seconds(4)
        while model.presentationActive || presentation.selected?.threadID.string != "Inbox tagged" {
            guard ContinuousClock.now < readerDeadline else {
                try await capture(window, to: directory.appending(path: "inbox-reader-click-failure.png"))
                throw ReplayError("Reader did not cover the selected Inbox tag at \(point): "
                    + "frame=\(frame), active=\(model.presentationActive), selected=\(String(describing: presentation.selected))")
            }
            try await Task.sleep(for: .milliseconds(30))
        }
        var retagged = try thread("Inbox tagged", nil, revision: 2).objectValue!
        retagged["tags"] = .array([])
        retagged["tagEmojis"] = .object([:])
        let patch: JSONValue = .object(["type": .text("state-patched"), "baseRevision": .integer(15), "revision": .integer(16),
            "threads": .object(["upserts": .array([.object(retagged), try thread("Inbox untagged", nil)]), "removedIds": .array([])])])
        let next = try RuntimeState.applying(patch, to: workspace.state!)
        await workspace.installPrepared(next, event: .mutation(patch, state: next, authority: authority))
        guard !model.presentationActive, model.sceneKey == scene, model.items.map(\.id) == ["Inbox tagged"],
              model.filterContextFacts.isEmpty, model.selectedFilter == nil, model.selectedTag.isEmpty, model.selectedScope.isEmpty else {
            throw ReplayError("Hidden Inbox tag removal left stale filter context or rebuilt the covered Overview")
        }
        presentation.showOverview()
        let deadline = ContinuousClock.now + .seconds(4)
        while !model.presentationActive || !model.chromeInteractions.mountedIDs(in: .directory).isEmpty
                || !model.chromeInteractions.mountedIDs(in: .semantic).isEmpty
                || !canvas.mountedCardIDs.isEmpty || canvas.isLayingOut {
            guard ContinuousClock.now < deadline else { throw ReplayError("Untagged-only workspace did not settle") }
            try await Task.sleep(for: .milliseconds(30))
        }
        let savedIDs = workspace.catalog.threads.map(\.id.string)
        guard model.visibleFilters.isEmpty, model.selectedFilter == nil, model.selectedTag.isEmpty,
              model.statusFilter == .all, savedIDs.contains("Inbox tagged"), savedIDs.contains("Inbox untagged"),
              model.chromeInteractions.mountedIDs(in: .status).isEmpty else {
            throw ReplayError("Unexpected cards, controls or thread loss after removing the last tag")
        }
        samples.append(["step": "last-inbox-tag-removed", "previousTag": inboxShipping.id, "scope": model.selectedScope,
                        "visibleTags": model.visibleFilters.map(\.id), "mountedCardIDs": Array(canvas.mountedCardIDs),
                        "retainedReaderScene": scene, "catalogThreadIDs": savedIDs])
        let assigned = try thread("Inbox untagged", nil, revision: 2, semanticTag: "Shipping")
        let assignment: JSONValue = .object(["type": .text("state-patched"), "baseRevision": .integer(16), "revision": .integer(17),
            "threads": .object(["upserts": .array([assigned]), "removedIds": .array([])])])
        let taggedState = try RuntimeState.applying(assignment, to: workspace.state!)
        await workspace.installPrepared(taggedState, event: .mutation(assignment, state: taggedState, authority: authority))
        let assignedDeadline = ContinuousClock.now + .seconds(4)
        while model.selectedFilter?.id != inboxShipping.id || canvas.mountedCardIDs != ["Inbox untagged"] || canvas.isLayingOut {
            guard ContinuousClock.now < assignedDeadline else { throw ReplayError("First assignment did not open its space") }
            try await Task.sleep(for: .milliseconds(30))
        }
        samples.append(["step": "first-assignment", "selected": inboxShipping.id, "mountedCardIDs": Array(canvas.mountedCardIDs)])
        try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appending(path: "overview-status.json"))
    }

    private func reportFixtures(_ ids: [JSONText]) -> [JSONValue] {
        let now = Date().timeIntervalSince1970 * 1000
        return ids.enumerated().map { index, id -> JSONValue in
            let ref = ApplicationThreadRef(threadID: id, typeID: "report.document")
            let created = now - Double(ids.count - index)
            return .object(["id": .string(id), "ref": ref.json, "revision": .integer(1),
                "createdAt": .number(created), "updatedAt": .number(created),
                "title": .string(id), "archived": .bool(false), "scope": .text("/fixture"), "presentations": .array([]),
                "tags": .object(["tags": .array([.text("Fixture"), .text("Development")]), "semanticTags": .array([.text("Development")]), "directoryTags": .array([.text("Fixture")]), "tagEmojis": .object(["Development": .text("🔧")])]),
                "view": .object(["coverRevision": .text("cover"), "contentRevision": .text("body"), "emoji": .text("📕"),
                    "readingSeconds": .integer(20), "shortDescription": .text("Report"), "previewText": .text("Report"),
                    "relatedExecutions": .array([])])])
        }
    }

    private func fittingCollection(directory: URL, authority: UUID) async throws {
        let model = presentation.overview, canvas = presentation.canvas
        let ids = (0..<8).map { JSONText("report-\($0)") }
        let reports = reportFixtures(ids)
        model.selectTag(nil)
        var samples = [[String: Any]]()
        func check(_ width: Int, _ height: Int, tasks: Int, grouped: Int, scrolls: Bool = false) async throws {
            // Collection membership depends on the proposed layout size, including
            // viewports wider than the display. Keep the native window in place.
            collectionViewport = CGSize(width: width, height: height)
            let expected = ids.prefix(grouped).map(\.string)
            let deadline = ContinuousClock.now + .seconds(5)
            while true {
                if let error = model.error ?? canvas.layoutError { throw ReplayError(error) }
                let members = model.items.flatMap { item -> [String] in
                    guard case .collection(_, let members) = model.snapshot(for: item) else { return [] }
                    return members.map(\.entry.ref.threadID.string)
                }
                let placements = canvas.presentedPlacements
                let camera = canvas.camera
                if camera.viewport?.width == Double(width), camera.viewport?.height == Double(height),
                   members == expected, placements.count == tasks + ids.count - grouped + (grouped == 0 ? 0 : 1),
                   placements.map(\.id) == model.items.map(\.id), canvas.mountedCardIDs == Set(placements.map(\.id)),
                   !canvas.isLayingOut, (camera.maximumOffset > 0) == scrolls {
                    camera.scroll(by: 10_000)
                    guard camera.scrollOffset == camera.maximumOffset else { throw ReplayError("Unreachable collection scroll boundary") }
                    samples.append(["viewport": [width, height], "tasks": tasks, "grouped": members, "travel": camera.maximumOffset])
                    return
                }
                guard ContinuousClock.now < deadline else {
                    throw ReplayError("Collection at \(width)×\(height) did not settle: \(members), viewport=\(String(describing: camera.viewport)), travel=\(camera.maximumOffset), cards=\(placements.count), error=\(model.error ?? workspace.operationError ?? "none")")
                }
                try await Task.sleep(for: .milliseconds(25))
            }
        }
        try await installTasks(2, revision: 5, authority: authority, reports: reports)
        try await check(2064, 1212, tasks: 2, grouped: 0)
        try await installTasks(3, revision: 6, authority: authority, reports: reports)
        try await check(2064, 1212, tasks: 3, grouped: 0)
        try await installTasks(2, revision: 7, authority: authority, reports: reports)
        try await check(2064, 1212, tasks: 2, grouped: 0)
        try await check(1024, 704, tasks: 2, grouped: 6)
        let atBoundary = model.items.map(\.id)
        try await Task.sleep(for: .milliseconds(500))
        guard model.items.map(\.id) == atBoundary, canvas.presentedPlacements.map(\.id) == atBoundary,
              atBoundary.allSatisfy(canvas.allowsActivation) else { throw ReplayError("Unstable collection at exact fit") }
        try await check(1022, 704, tasks: 2, grouped: 7)
        try await check(600, 704, tasks: 2, grouped: 7, scrolls: true)
        try await check(1024, 704, tasks: 2, grouped: 6)
        try await check(2064, 1212, tasks: 2, grouped: 0)
        try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appending(path: "collection-fit.json"))
    }

    private func keyboardInteraction(_ window: NSWindow, directory: URL, id: String, atEnd: Double) async throws {
        let camera = presentation.canvas.camera
        let identifier = "overview-card-\(id)"
        let workspace = directory.deletingLastPathComponent()
        try identifier.write(to: workspace.appending(path: "keyboard-target"), atomically: true, encoding: .utf8)
        let receipt = workspace.appending(path: "keyboard-focus")
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: receipt.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        guard let result = try? String(contentsOf: receipt, encoding: .utf8), result == "focused" else {
            throw ReplayError("The system accessibility client could not focus \(identifier). See keyboard-focus.log.")
        }
        try await pressKey("\u{F702}", code: 123, in: window)
        let keyboardOffset = camera.scrollOffset
        guard keyboardOffset == atEnd - NativeOverviewLayout.columnPitch else {
            throw ReplayError("A focused card did not scroll one column left, offset=\(keyboardOffset)")
        }
        try await pressKey("\u{F703}", code: 124, in: window)
        try await pressKey("\r", code: 36, in: window)
        guard camera.scrollOffset == atEnd, presentation.selected?.threadID.string == id else {
            throw ReplayError("A focused card did not scroll right and open with Return")
        }
        presentation.showOverview()
        try await Task.sleep(for: .seconds(1))
        let record: [String: Any] = ["focusedCard": id, "leftArrowOffset": keyboardOffset,
            "rightArrowOffset": camera.scrollOffset, "openedCard": id]
        try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appending(path: "overview-keyboard.json"))
    }

    private func inspect(_ window: NSWindow, filterTop: CGFloat) throws -> [String: Any] {
        guard let content = window.contentView, let frame = content.superview,
              let host = descendant(NativeReadingParentView.self, in: content),
              let monitor = descendant(NativeOverviewScrollInput.MonitorView.self, in: host),
              let filter = descendant(NSScrollView.self, in: host) else {
            throw ReplayError("Missing nested Overview, its directory scroller or its input monitor")
        }
        let size = monitor.configuration.size
        let filterFrame = filter.convert(filter.bounds, to: nil)
        let boundary = monitor.configuration.toolbarBottom
        let below = CGPoint(x: size.width - 8, y: size.height - 4)
        let above = CGPoint(x: below.x, y: boundary - 1)
        let camera = presentation.overview.canvasState.camera
        let rejectsHeader = !monitor.canStart(at: above)
        let point = monitor.windowPoint(below)
        func wheel(_ x: CGFloat, _ y: CGFloat, precise: Bool = true,
                   phase: NSEvent.Phase = .began, momentum: NSEvent.Phase = []) -> Bool {
            monitor.handle(WheelSample(window: window, point: point, x: x, y: y,
                precise: precise, phase: phase, momentum: momentum)) == nil
        }
        let leading = wheel(10000, 0, precise: false, phase: []) && camera.scrollOffset == 0
        let before = camera.transform
        let factor = monitor.canvasPerWindowPoint ?? 0
        let diagonal = wheel(-24, 12) && abs(camera.scrollOffset - min(24 * factor, camera.maximumOffset)) < 0.01
        let directOffset = camera.scrollOffset
        let vertical = wheel(0, -50, phase: .changed) && camera.scrollOffset == directOffset
        _ = wheel(0, 0, phase: .ended)
        let inertia = wheel(-20, 36, phase: [], momentum: .began)
            && abs(camera.scrollOffset - min(44 * factor, camera.maximumOffset)) < 0.01
        _ = wheel(0, 0, phase: [], momentum: .ended)
        let trailing = wheel(-10000, 0, precise: false, phase: []) && camera.scrollOffset == camera.maximumOffset
        let reversed = wheel(1, 0, precise: false, phase: [])
            && abs(camera.scrollOffset - max(0, camera.maximumOffset - 40 * factor)) < 0.01
        let scrolled = camera.maximumOffset > 0 && factor > 0 && before.y == camera.transform.y
            && leading && diagonal && vertical && inertia && trailing && reversed

        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap(window.standardWindowButton)
        let rects = buttons.map { $0.convert($0.bounds, to: nil) }
        let hits = zip(buttons, rects).allSatisfy { button, rect in
            [-6.5, 0, 6.5].allSatisfy { dy in
                let point = CGPoint(x: rect.midX, y: rect.midY + dy)
                return frame.hitTest(frame.superview?.convert(point, from: nil) ?? point) === button
            }
        }
        let buttonCenters = rects.map { CGPoint(x: $0.midX, y: window.frame.height - $0.midY) }
        let positioned = zip(buttonCenters, [31.0, 51.0, 71.0]).allSatisfy { center, x in
            abs(center.x - x) <= 0.5 && abs(center.y - 38) <= 0.5
        }
        let renderedFilterTop = window.frame.height - filterFrame.maxY
        guard let selected = presentation.overview.selectedFilter else { throw ReplayError("Missing selected tag") }
        let topHeight = try filterButton(selected.id, in: window).frame.height
        let statusHeight = try filterButton("overview-status-running", in: window).frame.height
        let filterPositioned = abs(renderedFilterTop - filterTop) <= 0.5
            && abs(topHeight - 46.2) <= 1 && abs(statusHeight - topHeight) <= 0.5
        let filterBottom = window.frame.height - filterFrame.minY
        let filterInside = filterFrame.minY >= 0 && filterFrame.maxY <= window.frame.height
        let filterExcluded = filterBottom <= boundary
        let strip = size.height - boundary
        let inputPoint = monitor.windowPoint(below)
        let pointInside = CGRect(origin: .zero, size: window.frame.size).contains(inputPoint)
        return ["windowSize": [window.frame.width, window.frame.height],
                "logicalViewport": [size.width, size.height], "filterTopInWindow": renderedFilterTop,
                "topTagHeight": topHeight, "statusHeight": statusHeight, "expectedFilterTopInWindow": filterTop, "filterBottomInWindow": filterBottom,
                "buttonCentersFromTopLeft": buttonCenters.map { [$0.x, $0.y] }, "buttonHits": hits,
                "headerInputBottom": boundary, "canvasStripHeight": strip, "inputPointInWindow": [inputPoint.x, inputPoint.y],
                "rejectsHeader": rejectsHeader, "wheelAndTrackpad": scrolled, "diagonal": diagonal, "vertical": vertical,
                "systemMomentum": inertia, "mouseWheelEdges": leading && trailing && reversed,
                "passed": buttons.count == 3 && hits && positioned && filterPositioned && filterInside && filterExcluded
                    && strip >= 8 && pointInside && rejectsHeader && scrolled]
    }
}

private final class RecordingObserver: NSObject, SCRecordingOutputDelegate, Sendable {
    let completion: AsyncThrowingStream<Void, Error>.Continuation
    init(_ completion: AsyncThrowingStream<Void, Error>.Continuation) { self.completion = completion }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { completion.finish() }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        completion.finish(throwing: error)
    }
}
