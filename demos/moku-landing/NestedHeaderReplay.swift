import AppKit
import ScreenCaptureKit
import SwiftUI
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
    override var scrollingDeltaX: CGFloat { x }
    override var scrollingDeltaY: CGFloat { y }
    override var phase: NSEvent.Phase { direct }
    override var momentumPhase: NSEvent.Phase { momentum }
    override var modifierFlags: NSEvent.ModifierFlags { [] }
    override var timestamp: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

@main @MainActor private struct NestedHeaderReplay: App {
    @State private var zoom = 5.0
    private let workspace: NativeWorkspaceModel
    private let presentation: NativeWorkspacePresentation

    init() {
        do {
            try prepareIsolatedNativeReplay()
            let directory = URL(filePath: FileManager.default.currentDirectoryPath)
            let preferences = DesktopPreferences(directory: directory)
            try preferences.setOnboardingCompleted(true)
            workspace = NativeWorkspaceModel(client: RuntimeClient(profile: try RuntimeProfile(dataDirectory: directory)),
                preferences: preferences, plugins: try .init(harnesses: [AnyHarnessPlugin(CodexHarnessPlugin())], sidecards: [], applications: NativeApplicationModules.make()))
            presentation = NativeWorkspacePresentation(workspace: workspace)
        } catch { fatalError(String(describing: error)) }
    }

    var body: some Scene {
        Window("Overview header replay", id: "header-replay") {
            GeometryReader { geometry in
                NativeWorkspaceView(model: workspace, presentation: presentation)
                    .frame(width: geometry.size.width / zoom, height: geometry.size.height / zoom)
                    .environment(\.nativeWindowContentScale, zoom)
                    .scaleEffect(zoom, anchor: .topLeading)
            }
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
                              reports: [JSONValue] = []) async throws {
        let ids = (0..<count).map { "task-\($0)" } + ["moku"]
        let threads = try ids.enumerated().map { index, id in
            let other = firstDirectoryCount.map { index >= $0 && id != "moku" } ?? false
            let scope: JSONText = other ? "/other" : "/fixture"
            return try HarnessThread(id: JSONText(id), harnessID: "codex", revision: 0, sessionState: .null,
                observation: .init(), cwd: scope, settings: .object([:]), createdAt: 1, updatedAt: 2,
                title: JSONText(id), tags: [], moku: id == "moku" ? true : nil, transcript: id == "moku" ? .array([]) : nil,
                directoryTag: other ? "Other" : "Fixture", directoryScope: scope).json
        }
        let snapshot: JSONValue = .object(["revision": .integer(revision), "settingsRevision": .integer(0),
            "defaultCwd": .text("/fixture"), "settings": .object([:]), "threads": .array(threads),
            "executions": .array([]), "applicationThreads": .array(reports)])
        await workspace.installPrepared(snapshot, event: .snapshot(snapshot, authority: authority))
    }

    private func replay() async throws {
        let authority = UUID()
        try await installTasks(18, revision: 1, authority: authority)
        guard workspace.hasInitialContent, let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "header-replay" }),
              let screen = NSScreen.screens.first else { throw ReplayError("Workspace did not mount") }
        window.collectionBehavior = [.auxiliary, .canJoinAllSpaces]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        let directory = URL(filePath: FileManager.default.currentDirectoryPath).appending(path: "evidence")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var records: [[String: Any]] = []
        // Filter tops are logical points. Settings probes use actual-size window points.
        let cases: [(size: CGSize, scale: CGFloat, filterTop: CGFloat, settingsProbe: CGPoint?, captureName: String?)] = [
            (CGSize(width: 860, height: 640), 5, 76, nil, "maximum"),
            (CGSize(width: 1100, height: 760), 1, 16, CGPoint(x: 1061, y: 22), "wide"),
            (CGSize(width: 600, height: 480), 1, 76, CGPoint(x: 565, y: 16), "narrow"),
            (CGSize(width: 1100, height: 760), 1.44, 16, nil, "menu"),
            (CGSize(width: 860, height: 640), 2.5, 76, nil, nil),
            (CGSize(width: 860, height: 640), 5, 76, nil, nil),
            (CGSize(width: 860, height: 600), 5, 68, nil, nil),
        ]
        var previousOffset = 0.0
        for (size, scale, filterTop, settingsProbe, captureName) in cases {
            zoom = scale
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
            var result = try inspect(window, scale: scale, filterTop: filterTop)
            result["retainedOffsetOnResize"] = retained
            result["passed"] = retained && result["passed"] as? Bool == true
            if CommandLine.arguments.contains("--capture"), let captureName {
                try await capture(window, to: directory.appending(path: captureName + ".png"))
            }
            if let settingsProbe {
                let opened = try await clickSettings(window, at: settingsProbe)
                result["settingsProbeFromTopLeft"] = [settingsProbe.x, settingsProbe.y]
                result["settingsOpened"] = opened
                result["passed"] = opened && result["passed"] as? Bool == true
            }
            previousOffset = camera.scrollOffset
            records.append(result)
            if result["passed"] as? Bool != true { print("Failed geometry: \(result)") }
        }
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appending(path: "nested-header.json"))
        guard records.allSatisfy({ $0["passed"] as? Bool == true }) else { throw ReplayError("Nested header replay failed") }
        zoom = 1
        window.setContentSize(CGSize(width: 900, height: 680))
        try await Task.sleep(for: .seconds(1))
        try await cardInteraction(window, directory: directory, authority: authority)
        try await fittingCards(window, directory: directory, authority: authority)
        try await fittingCollection(window, directory: directory, authority: authority)
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

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews { if let match = descendant(type, in: child) { return match } }
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
            throw ReplayError("Dense fixture did not reach its trailing boundary")
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
                    || canvas.isLayingOut || canvas.layoutSolveCount == previousSolve {
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
                throw ReplayError("Fit fixture wheel missed the canvas")
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

    private func fittingCollection(_ window: NSWindow, directory: URL, authority: UUID) async throws {
        let model = presentation.overview, canvas = presentation.canvas
        let ids = (0..<8).map { JSONText("report-\($0)") }
        let now = Date().timeIntervalSince1970 * 1000
        let reports = ids.enumerated().map { index, id -> JSONValue in
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
        model.selectTag(nil)
        var samples = [[String: Any]]()
        func check(_ width: Int, _ height: Int, tasks: Int, grouped: Int, scrolls: Bool = false) async throws {
            // Fit the recording-sized logical viewport on a smaller desktop.
            zoom = 0.5
            window.setContentSize(CGSize(width: Double(width) * zoom, height: Double(height) * zoom))
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

    private func inspect(_ window: NSWindow, scale: CGFloat, filterTop: CGFloat) throws -> [String: Any] {
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
        let filterPositioned = abs(renderedFilterTop - filterTop * scale) <= 0.5
        let filterBottom = window.frame.height - filterFrame.minY
        let filterInside = filterFrame.minY >= 0 && filterFrame.maxY <= window.frame.height
        let filterExcluded = filterBottom <= boundary * scale
        let strip = size.height - boundary
        let inputPoint = monitor.windowPoint(below)
        let pointInside = CGRect(origin: .zero, size: window.frame.size).contains(inputPoint)
        return ["windowSize": [window.frame.width, window.frame.height], "scale": scale,
                "logicalViewport": [size.width, size.height], "filterTopInWindow": renderedFilterTop,
                "expectedFilterTopInWindow": filterTop * scale, "filterBottomInWindow": filterBottom,
                "buttonCentersFromTopLeft": buttonCenters.map { [$0.x, $0.y] }, "buttonHits": hits,
                "headerInputBottom": boundary, "canvasStripHeight": strip, "inputPointInWindow": [inputPoint.x, inputPoint.y],
                "rejectsHeader": rejectsHeader, "wheelAndTrackpad": scrolled, "diagonal": diagonal, "vertical": vertical,
                "systemMomentum": inertia, "mouseWheelEdges": leading && trailing && reversed,
                "passed": buttons.count == 3 && hits && positioned && filterPositioned && filterInside && filterExcluded
                    && strip >= 8 && pointInside && rejectsHeader && scrolled]
    }
}
