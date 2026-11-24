import AppKit
import ScreenCaptureKit
import SwiftUI
import Vision
import ChiefApplications
import ChiefCore
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
    private let workspace: NativeWorkspaceModel
    private let presentation: NativeWorkspacePresentation

    init() { self.init(profile: nil) }

    private init(profile: URL?) {
        do {
            if profile == nil { try prepareIsolatedNativeReplay() }
            let directory = profile ?? URL(filePath: FileManager.default.currentDirectoryPath)
            let preferences = DesktopPreferences(directory: directory)
            try preferences.setOnboardingCompleted(true)
            workspace = NativeWorkspaceModel(client: RuntimeClient(profile: try RuntimeProfile(dataDirectory: directory)),
                preferences: preferences, plugins: try .init(harnesses: [AnyHarnessPlugin(CodexHarnessPlugin())], sidecards: [], applications: NativeApplicationModules.make()),
                timer: NativeMokuTimerController(player: SilentReminderBell()))
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
                if captureScheme != nil { Color(nsColor: .windowBackgroundColor) }
            }
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
                              manyDirectories: Bool = false, reports: [JSONValue] = [], extraThreads: [JSONValue] = []) async throws {
        let ids = (0..<count).map { "task-\($0)" } + ["moku"]
        let note = try ThreadNote(id: "fixture-note", text: JSONText(String(repeating: "A note paragraph.\n\n", count: 55)),
                                  revision: 1, updatedAt: 2)
        let threads = try ids.enumerated().map { index, id in
            let other = firstDirectoryCount.map { index >= $0 && id != "moku" } ?? false
            let directory: JSONText = manyDirectories ? JSONText("Project \(index)") : (other ? "Other" : "Fixture")
            let scope: JSONText = manyDirectories ? JSONText("/fixture/\(index)") : (other ? "/other" : "/fixture")
            return try HarnessThread(id: JSONText(id), harnessID: "codex", revision: 0, sessionState: .null,
                observation: .init(), cwd: scope, settings: .object([:]), createdAt: 1, updatedAt: 2,
                title: JSONText(id), tags: [], moku: id == "moku" ? true : nil, note: manyDirectories && id == "moku" ? note : nil, transcript: id == "moku" ? .array([]) : nil,
                directoryTag: directory, directoryScope: scope).json
        }
        let snapshot: JSONValue = .object(["revision": .integer(revision), "settingsRevision": .integer(0),
            "defaultCwd": .text("/fixture"), "settings": .object([:]), "threads": .array(threads + extraThreads),
            "executions": .array([]), "applicationThreads": .array(reports)])
        await workspace.installPrepared(snapshot, event: .snapshot(snapshot, authority: authority))
    }

    private func replay() async throws {
        let authority = UUID()
        let noteSwipeReplay = CommandLine.arguments.contains("--note-swipe")
        try await installTasks(18, revision: 1, authority: authority, manyDirectories: noteSwipeReplay)
        guard workspace.hasInitialContent, let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "header-replay" }),
              let screen = NSScreen.screens.first else { throw ReplayError("Workspace did not mount") }
        window.collectionBehavior = [.auxiliary, .canJoinAllSpaces]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        let directory = URL(filePath: FileManager.default.currentDirectoryPath).appending(path: "evidence")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if CommandLine.arguments.contains("--status-only") {
            window.center()
            try await focusReplayWindow(window)
            try await statusFilters(window, directory: directory, authority: authority)
            return
        }
        if noteSwipeReplay {
            window.setContentSize(CGSize(width: 900, height: 680))
            window.center()
            try await focusReplayWindow(window)
            try await Task.sleep(for: .seconds(1))
            try await noteSwipes(window, directory: directory)
            let reminderFixture = Self(profile: directory.appending(path: "reminder-profile"))
            try await reminderFixture.reminderSwipe(directory: directory)
            try await focusReplayWindow(window)
            try await cardInteraction(window, directory: directory, authority: authority)
            try await fittingCards(window, directory: directory, authority: authority)
            try await statusFilters(window, directory: directory, authority: authority)
            try await installTasks(0, revision: 13, authority: authority)
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
            guard presentation.scene.notePanelOpen else { throw ReplayError("Empty Overview Chief Bar missed the Note swipe") }
            try Data("true".utf8).write(to: directory.appending(path: "landing-note-swipe.json"))
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

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView, matching: (T) -> Bool = { _ in true }) -> T? {
        if let match = view as? T, matching(match) { return match }
        for child in view.subviews {
            if let match = descendant(type, in: child, matching: matching) { return match }
        }
        return nil
    }

    private func pressKey(_ text: String, code: UInt16, in window: NSWindow) async throws {
        let flags: NSEvent.ModifierFlags = code == 36 ? [] : [.numericPad, .function]
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

    private func clickSettings(_ window: NSWindow, at point: CGPoint) async throws -> Bool {
        let location = CGPoint(x: point.x, y: window.frame.height - point.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else {
                throw ReplayError("Cannot create the window-local Settings click")
            }
            window.sendEvent(event)
        }
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
        // A window-addressed AppKit event supplies the native window identity.
        // Reuse its CGEvent envelope to enqueue a window-local pixel or line scroll.
        guard let event = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [],
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
        guard let sample = NSEvent(cgEvent: event), sample.window === window, sample.locationInWindow == point,
              sample.hasPreciseScrollingDeltas == precise else { throw ReplayError("Scroll lost its window target or precision") }
        NSApp.postEvent(sample, atStart: false)
        try await Task.sleep(for: .milliseconds(55))
    }

    /// Post pixel scrolls to this replay process. AppKit chooses the responder
    /// and invokes the installed monitors, including over the nested tag scroller.
    private func noteSwipes(_ window: NSWindow, directory: URL) async throws {
        guard let content = window.contentView,
              let monitor = descendant(NativeOverviewScrollInput.MonitorView.self, in: content),
              let parent = descendant(NativeReadingParentView.self, in: content),
              let tags = descendant(NSScrollView.self, in: parent),
              let card = presentation.canvas.presentedPlacements.compactMap({
                  presentation.canvas.visibleFrame(for: $0.id)
              }).first(where: { CGRect(origin: .zero, size: monitor.configuration.size).contains($0) }) else {
            throw ReplayError("Missing Overview swipe targets")
        }
        let scene = presentation.scene
        let camera = presentation.canvas.camera
        let center: (CGRect) -> CGPoint = { CGPoint(x: $0.midX, y: $0.midY) }
        let background = monitor.windowPoint(CGPoint(x: 8, y: monitor.configuration.size.height - 8))
        let barPoint = monitor.windowPoint(center(scene.capsuleFrame))
        let targets = [("background", background), ("card", monitor.windowPoint(center(card))),
                       ("tag scroller", tags.convert(center(tags.bounds), to: nil)),
                       ("Chief Bar", barPoint)]
        let startOffset = camera.scrollOffset
        let model = presentation.overview
        try await postScroll(window, background, y: 9, phase: .began)
        try await postScroll(window, background, y: 0, phase: .cancelled)
        try await postScroll(window, background, y: 60, phase: nil, momentum: .begin)
        try await postScroll(window, background, y: 0, phase: nil, momentum: .end)
        guard model.statusFilter == .all, !scene.notePanelOpen else { throw ReplayError("Orphan momentum took action") }
        for (region, point) in targets {
            let generation = scene.noteOpenGeneration
            let bar = region == "Chief Bar"
            try await postScroll(window, point, y: 10, phase: .began)
            guard !scene.notePanelOpen, model.statusFilter == .all else { throw ReplayError("Subthreshold swipe at " + region) }
            try await postScroll(window, point, y: 17, phase: .changed)
            guard scene.notePanelOpen == bar, scene.noteOpenGeneration == generation + (bar ? 1 : 0),
                  model.statusFilter == (bar ? .all : .running) else { throw ReplayError("Wrong swipe owner at " + region) }
            if bar { presentation.toggleMokuNote() }
            // Reverse before lift, cross into the other surface and add inertia.
            let other = bar ? background : barPoint
            try await postScroll(window, other, y: -60, phase: .changed)
            try await postScroll(window, other, y: 0, phase: .ended)
            try await postScroll(window, other, y: -60, phase: nil, momentum: .begin, x: -20)
            try await postScroll(window, other, y: 0, phase: nil, momentum: .end)
            guard !scene.notePanelOpen, model.statusFilter == (bar ? .all : .running),
                  camera.scrollOffset == startOffset else { throw ReplayError("Swipe tail escaped at " + region) }
            if !bar {
                try await postScroll(window, background, y: -40, phase: .began)
                try await postScroll(window, background, y: 0, phase: .ended)
            }
            try await Task.sleep(for: .milliseconds(600))
        }
        let inverted = WheelSample(window: window, point: background, x: 0, y: -25)
        guard monitor.handle(inverted) == nil, !scene.notePanelOpen, model.statusFilter == .running else {
            throw ReplayError("Natural Scrolling changed the physical filter gesture")
        }
        _ = monitor.handle(WheelSample(window: window, point: background, x: 0, y: 0, phase: .ended))
        try await postScroll(window, background, y: -40, phase: .began)
        try await postScroll(window, background, y: 0, phase: .ended)
        try await Task.sleep(for: .milliseconds(650))
        let tagPoint = tags.convert(center(tags.bounds), to: nil)
        let tagOffset = tags.contentView.bounds.minX
        try await postScroll(window, tagPoint, y: 0, phase: .began, x: tagOffset > 0 ? 40 : -40)
        try await postScroll(window, tagPoint, y: 0, phase: .ended)
        guard tags.contentView.bounds.minX != tagOffset, camera.scrollOffset == startOffset,
              !scene.notePanelOpen else { throw ReplayError("The overflowing tags lost horizontal scrolling") }

        try await postScroll(window, barPoint, y: 40, phase: .began)
        try await postScroll(window, barPoint, y: 0, phase: .ended)
        try await Task.sleep(for: .milliseconds(850))
        let notePoint = monitor.windowPoint(center(scene.capsuleFrame))
        let hit = content.hitTest(content.superview?.convert(notePoint, from: nil) ?? notePoint)
        guard let scroller = hit?.enclosingScrollView, let document = scroller.documentView,
              document.bounds.height > scroller.contentView.bounds.height + 80 else {
            throw ReplayError("Note swipe fixture missed the overflowing Note body")
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
        presentation.toggleMokuNote()
        try await Task.sleep(for: .milliseconds(650))
        try await postScroll(window, barPoint, y: -40, phase: .began)
        try await postScroll(window, barPoint, y: 0, phase: .ended)
        try await postScroll(window, background, y: 40, phase: .began, flags: .maskShift)
        try await postScroll(window, background, y: 0, phase: .ended)
        guard !scene.notePanelOpen, model.statusFilter == .all else { throw ReplayError("Downward Bar or modified canvas input took action") }
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
        scene.setInputOpen(true)
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
            "singleOpenThroughMomentum": true, "horizontalScroll": true, "composerExcluded": true, "settingsExcluded": true,
            "tagOffsets": [tagOffset, tags.contentView.bounds.minX], "noteOffsets": [original, scrolled],
            "naturalScrolling": true])
            .write(to: directory.appending(path: "overview-note-swipe.json"))
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
        let background = monitor.windowPoint(CGPoint(x: 8, y: monitor.configuration.size.height - 8))
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
            try wheel(0, 80, precise: false, phase: [])
            guard camera.transform == before, camera.scrollOffset == 0 else {
                throw ReplayError("Input moved a fitting grid")
            }
        }

        window.setContentSize(CGSize(width: 1360, height: 704))
        try await installTasks(13, revision: 4, authority: authority, firstDirectoryCount: 12)
        try await settle(width: 1360, count: 13)
        try wheel(-10000, 0)
        let beforeFilter = camera.scrollOffset
        guard beforeFilter > 0, let filter = presentation.overview.filters.first(where: { $0.scope == "/fixture" }) else {
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
        let ordinary = running + ["Delivered", "Stopped", "Idle"]
        let reportIDs = (1...8).map { "Report-\($0)" }
        let finishedAt = 1_790_000_000_000.0
        let permission = PublicInteraction(id: "permission", kind: .permission, title: "Review request",
            actions: [.init(id: "allow", intent: .allow, label: "Allow")], questions: [])
        func thread(_ name: String, _ status: PublicExecution.Status?, revision: Int = 1) throws -> JSONValue {
            let execution = try status.map { status in
                try PublicExecution(executionID: JSONText("run-" + name), status: status, startedAt: finishedAt - 33_000,
                    finishedAt: [.completed, .interrupted, .failed].contains(status) ? finishedAt : nil,
                    interactions: status == .waitingForUser ? [permission] : [])
            }
            let observation = ThreadPublicObservation(latestExecution: execution, backgroundWork: name == "Background" ? .init() : nil)
            let tag: JSONText = name == "Delivered" ? "Shipping" : "Development"
            let thread = try HarnessThread(id: JSONText(name), harnessID: "codex", revision: revision, sessionState: .null,
                observation: observation, cwd: "/fixture", settings: .object([:]),
                createdAt: finishedAt - 60_000, updatedAt: finishedAt + 86_400_000,
                title: JSONText(name), tags: [tag], tagEmojis: [tag: name == "Delivered" ? "📦" : "🔧"],
                directoryTag: "Fixture", directoryScope: "/fixture")
            var fields = thread.json.objectValue!
            fields["pendingInput"] = .bool(name == "Submitting")
            return .object(fields)
        }
        let fixtures = try [thread("Executing", .running), thread("Permission", .waitingForUser),
            thread("Background", .completed), thread("Submitting", nil), thread("Delivered", .completed),
            thread("Stopped", .interrupted), thread("Idle", nil), thread("Failed", .failed)]
        window.setContentSize(CGSize(width: 1024, height: 704))
        model.selectTag(nil)
        try await installTasks(0, revision: 8, authority: authority,
            reports: reportFixtures(reportIDs.map { JSONText($0) }), extraThreads: fixtures)
        guard let content = window.contentView,
              let monitor = descendant(NativeOverviewScrollInput.MonitorView.self, in: content) else {
            throw ReplayError("Status replay has no window scroll router")
        }
        let tags = model.visibleFilters
        let tagIDs = tags.flatMap { [$0.id] + $0.children.map(\.id) }
        var samples = [[String: Any]]()
        func logoImage(_ identifier: String) -> NSImageView? {
            descendant(NSImageView.self, in: content) { $0.accessibilityIdentifier() == identifier }
        }
        func emptyCopy(_ mode: NativeOverviewStatusFilter) -> [String] {
            mode == .running
                ? [workspace.locale.text("没有运行中的会话", "No running conversations"),
                   workspace.locale.text("下滑查看全部会话", "Scroll down to show all conversations")]
                : [workspace.locale.text("没有已完成的会话", "No completed conversations"),
                   workspace.locale.text("上滑查看全部会话", "Scroll up to show all conversations")]
        }
        func checkStatusText(in url: URL, expected: [String]) throws -> [String] {
            let request = VNRecognizeTextRequest()
            request.recognitionLanguages = workspace.locale == .chinese ? ["zh-Hans", "en-US"] : ["en-US"]
            request.minimumTextHeight = 0.008
            try VNImageRequestHandler(url: url).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            func normalized(_ text: String) -> String {
                text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
            }
            let actual = lines.map(normalized)
            guard expected.allSatisfy({ text in actual.contains { $0.contains(normalized(text)) } }) else {
                throw ReplayError("Missing status text in \(url.lastPathComponent): expected=\(expected), found=\(lines)")
            }
            return lines
        }
        func check(_ name: String, _ mode: NativeOverviewStatusFilter, _ expected: [String],
                   selected: String = "", needsBothReportCards: Bool = false, checkCompletedCopy: Bool = false) async throws {
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
            let expectsIdle = mode == .running && expected.isEmpty
            let expectsCompletedLogo = mode == .completed && expected.isEmpty
            var idle = logoImage("overview.idle")
            var completedLogo = logoImage("overview.completed.logo")
            while ((idle != nil) != expectsIdle || (completedLogo != nil) != expectsCompletedLogo),
                  ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(30))
                idle = logoImage("overview.idle")
                completedLogo = logoImage("overview.completed.logo")
            }
            let logoSize = CGSize(width: 156, height: 68)
            guard (idle != nil) == expectsIdle,
                  (completedLogo != nil) == expectsCompletedLogo,
                  [idle, completedLogo].compactMap({ $0 }).allSatisfy({
                      !$0.isAccessibilityElement() && $0.image != nil && $0.bounds.size == logoSize
                  }) else {
                if CommandLine.arguments.contains("--capture") {
                    try await capture(window, to: directory.appending(path: "failed-" + name + ".png"))
                }
                throw ReplayError("Unexpected logo at \(name): running=\(String(describing: idle?.bounds.size)), completed=\(String(describing: completedLogo?.bounds.size))")
            }
            var sample: [String: Any] = ["step": name, "status": mode.rawValue, "selectedTag": selected, "visibleTags": visibleTags,
                "agents": agents, "individualReports": documents, "collectionMembers": collected,
                "mountedCardCount": canvas.mountedCardIDs.count, "noteOpen": presentation.scene.notePanelOpen]
            if let logo = idle ?? completedLogo {
                sample["logoSize"] = [logo.bounds.width, logo.bounds.height]
            }
            if CommandLine.arguments.contains("--capture") {
                let url = directory.appending(path: "status-" + name + ".png")
                if expectsIdle || expectsCompletedLogo || checkCompletedCopy { try await Task.sleep(for: .milliseconds(450)) }
                try await capture(window, to: url)
                if expectsIdle || expectsCompletedLogo {
                    sample["emptyText"] = try checkStatusText(in: url, expected: emptyCopy(mode))
                } else if checkCompletedCopy {
                    let locale = workspace.locale
                    let formattedFinish = Date(timeIntervalSince1970: finishedAt / 1_000)
                        .formatted(.dateTime.year().month(.abbreviated).day().hour().minute().locale(Locale(identifier: locale.rawValue)))
                    let expectedText = ["Delivered", locale.text("仅已完成", "Completed only"),
                                        locale.text("已完成", "Completed") + " · " + formattedFinish]
                    sample["completedText"] = try checkStatusText(in: url, expected: expectedText)
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
        func swipe(_ y: Int32, over location: CGPoint = CGPoint(x: 12, y: 220)) async throws {
            try await waitForFilterInput()
            let point = monitor.windowPoint(location)
            try await postScroll(window, point, y: y, phase: .began)
            try await postScroll(window, point, y: y * 2, phase: .changed)
            try await postScroll(window, point, y: 0, phase: .ended)
            try await postScroll(window, point, y: y, phase: nil, momentum: .begin)
            try await postScroll(window, point, y: 0, phase: nil, momentum: .end)
        }
        func logoPoint(_ identifier: String) throws -> CGPoint {
            guard let logo = logoImage(identifier) else { throw ReplayError("Missing scroll target " + identifier) }
            return logo.convert(CGPoint(x: logo.bounds.midX, y: logo.bounds.midY), to: nil)
        }
        func wheel(_ y: Int32, over logo: String) async throws {
            try await waitForFilterInput()
            try await postScroll(window, logoPoint(logo), y: y, phase: nil, precise: false)
        }
        func updateDelivered(_ status: PublicExecution.Status, revision: Int) async throws {
            let updated = try thread("Delivered", status, revision: revision)
            let patch: JSONValue = .object(["type": .text("state-patched"), "baseRevision": .integer(revision - 1),
                "revision": .integer(revision), "threads": .object(["upserts": .array([updated]), "removedIds": .array([])])])
            let next = try RuntimeState.applying(patch, to: workspace.state!)
            await workspace.installPrepared(next, event: .mutation(patch, state: next, authority: authority))
        }
        try await check("all", .all, ordinary + reportIDs)
        try await swipe(40)
        try await check("up", .running, running)
        try await swipe(40)
        try await check("upper-limit", .running, running)
        try await swipe(-40)
        try await check("back-from-running", .all, ordinary + reportIDs)
        try await swipe(-40)
        try await check("down", .completed, ["Delivered"] + reportIDs, needsBothReportCards: true)
        try await swipe(-40)
        try await check("lower-limit", .completed, ["Delivered"] + reportIDs)
        try await swipe(40)
        try await check("back-from-completed", .all, ordinary + reportIDs)
        guard let parent = tags.first(where: { $0.scope == "/fixture" }),
              let child = parent.children.first(where: { $0.tag == "Shipping" }) else { throw ReplayError("Missing Shipping chip") }
        try presentation.performOverviewInteraction(.overviewDirectoryOpen(parent.id))
        try await Task.sleep(for: .milliseconds(400))
        try presentation.performOverviewInteraction(.overviewDirectorySelect(directory: parent.id, filter: child.id))
        try await check("tag", .all, ["Delivered"], selected: "Shipping")
        let originalLocale = workspace.locale
        defer { workspace.updateSystemLocale(originalLocale) }
        workspace.updateSystemLocale(.chinese)
        try await swipe(40)
        try await check("empty-tag", .running, [], selected: "Shipping")
        if CommandLine.arguments.contains("--capture") {
            defer { captureScheme = nil }
            for (scheme, filename) in [(ColorScheme.light, "idle-light"), (.dark, "idle-dark")] {
                captureScheme = scheme
                try await Task.sleep(for: .milliseconds(450))
                let url = directory.appending(path: filename + ".png")
                try await capture(window, to: url)
                _ = try checkStatusText(in: url, expected: emptyCopy(.running))
            }
        }
        try await updateDelivered(.running, revision: 9)
        try await check("live-admit", .running, ["Delivered"], selected: "Shipping")
        workspace.updateSystemLocale(.english)
        try await updateDelivered(.completed, revision: 10)
        try await check("live-remove", .running, [], selected: "Shipping")
        try await wheel(-1, over: "overview.idle")
        try await check("tag-restored", .all, ["Delivered"], selected: "Shipping")
        try await swipe(-40)
        try await check("completed-tag", .completed, ["Delivered"], selected: "Shipping", checkCompletedCopy: true)
        try await updateDelivered(.running, revision: 11)
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
                _ = try checkStatusText(in: url, expected: emptyCopy(.completed))
            }
        }
        try await swipe(40, over: monitor.canvasPoint(logoPoint("overview.completed.logo")))
        try await check("back-from-completed-empty", .all, ["Delivered"], selected: "Shipping")
        try await swipe(-40)
        try await check("completed-empty-again", .completed, [], selected: "Shipping")
        try await wheel(1, over: "overview.completed.logo")
        try await check("back-from-completed-wheel", .all, ["Delivered"], selected: "Shipping")
        try await swipe(-40)
        try await updateDelivered(.completed, revision: 12)
        try await check("completed-live-admit", .completed, ["Delivered"], selected: "Shipping", checkCompletedCopy: true)
        try await swipe(40)
        try await check("completed-finished", .all, ["Delivered"], selected: "Shipping")
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
                "tags": .object(["tags": .array([]), "semanticTags": .array([]), "directoryTags": .array([]), "tagEmojis": .object([:])]),
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
        let leading = wheel(0, 10000, precise: false, phase: []) && camera.scrollOffset == 0
        let before = camera.transform
        let factor = monitor.canvasPerWindowPoint ?? 0
        let diagonal = wheel(-24, 60) && abs(camera.scrollOffset - min(24 * factor, camera.maximumOffset)) < 0.01
        let directOffset = camera.scrollOffset
        let vertical = wheel(0, -50, phase: .changed) && camera.scrollOffset == directOffset
        _ = wheel(0, 0, phase: .ended)
        let inertia = wheel(-20, 36, phase: [], momentum: .began)
            && abs(camera.scrollOffset - min(44 * factor, camera.maximumOffset)) < 0.01
        _ = wheel(0, 0, phase: [], momentum: .ended)
        let trailing = wheel(0, -10000, precise: false, phase: []) && camera.scrollOffset == camera.maximumOffset
        let reversed = wheel(0, 1, precise: false, phase: [])
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
        let filterPositioned = abs(renderedFilterTop - filterTop) <= 0.5
        let filterBottom = window.frame.height - filterFrame.minY
        let filterInside = filterFrame.minY >= 0 && filterFrame.maxY <= window.frame.height
        let filterExcluded = filterBottom <= boundary
        let strip = size.height - boundary
        let inputPoint = monitor.windowPoint(below)
        let pointInside = CGRect(origin: .zero, size: window.frame.size).contains(inputPoint)
        return ["windowSize": [window.frame.width, window.frame.height],
                "logicalViewport": [size.width, size.height], "filterTopInWindow": renderedFilterTop,
                "expectedFilterTopInWindow": filterTop, "filterBottomInWindow": filterBottom,
                "buttonCentersFromTopLeft": buttonCenters.map { [$0.x, $0.y] }, "buttonHits": hits,
                "headerInputBottom": boundary, "canvasStripHeight": strip, "inputPointInWindow": [inputPoint.x, inputPoint.y],
                "rejectsHeader": rejectsHeader, "wheelAndTrackpad": scrolled, "diagonal": diagonal, "vertical": vertical,
                "systemMomentum": inertia, "mouseWheelEdges": leading && trailing && reversed,
                "passed": buttons.count == 3 && hits && positioned && filterPositioned && filterInside && filterExcluded
                    && strip >= 8 && pointInside && rejectsHeader && scrolled]
    }
}
