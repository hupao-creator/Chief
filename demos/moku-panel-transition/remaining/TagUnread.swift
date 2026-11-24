import AppKit
import ScreenCaptureKit
import ChiefComposition
import ChiefCore
import ChiefPluginAPI
import SwiftUI
@testable import ChiefUI

@MainActor func tagUnreadVisit(activityMotionReduced: Bool? = nil) async throws {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let workspace = NativeWorkspaceModel(client: RuntimeClient(profile: try RuntimeProfile(dataDirectory: directory)),
        preferences: DesktopPreferences(directory: directory), plugins: try NativePlugins.make())
    let presentation = NativeWorkspacePresentation(workspace: workspace)
    defer { withExtendedLifetime(presentation) {} }
    let model = presentation.overview
    func install(finished: Bool, revision: Int) throws {
        let threads = try ["first", "second", "active"].map { name -> JSONValue in
            let complete = name != "active" || finished
            let execution = try PublicExecution(executionID: JSONText(name), status: complete ? .completed : .running,
                startedAt: 1, finishedAt: complete ? 2 : nil)
            let tag: JSONText = name == "second" ? "Reading" : "Work"
            return try HarnessThread(id: JSONText(name), harnessID: "codex", revision: revision, sessionState: .null,
                observation: .init(latestExecution: execution), cwd: "/fixture", settings: .object([:]),
                createdAt: 1, updatedAt: 2, title: JSONText(name), tags: [tag],
                tagEmojis: [tag: "🔎"], directoryTag: "Project", directoryScope: "/fixture").json
        }
        let snapshot: JSONValue = .object(["revision": .integer(revision), "settingsRevision": .integer(0),
            "defaultCwd": .text("/fixture"), "settings": .object([:]), "threads": .array(threads),
            "executions": .array([]), "applicationThreads": .array([])])
        try workspace.catalog.install(snapshot)
        model.refresh()
    }
    try install(finished: false, revision: 1)
    let panel = try Panel(size: .init(width: 920, height: 600), offscreen: activityMotionReduced == nil)
    defer { panel.close() }
    let overview = NativeOverviewWorkspaceView(model: model, callbacks: .init(
        openThread: { _, _ in }, openApplication: { _, _ in }, onSettings: {}))
    var measuredButtons = [String: CGRect]()
    if let activityMotionReduced {
        panel.mount(overview.environment(\._accessibilityReduceMotion, activityMotionReduced)
            .overlayPreferenceValue(OverviewTagBounds.self) { anchors in
                GeometryReader { proxy in
                    Color.clear.onChange(of: anchors.mapValues { proxy[$0] }, initial: true) { _, frames in
                        // Accept directory frames only inside the measured header scroll region.
                        guard let bar = frames["__scroll__"] else { return }
                        for (id, rect) in frames where !rect.isEmpty {
                            guard id.hasPrefix("semantic:") || (id.hasPrefix("directory:") && bar.intersects(rect)) else { continue }
                            measuredButtons[id] = CGRect(x: rect.minX, y: proxy.size.height - rect.maxY,
                                                         width: rect.width, height: rect.height)
                        }
                    }
                }.allowsHitTesting(false)
            })
    } else {
        panel.mount(overview)
    }
    guard let parent = model.visibleFilters.first(where: { $0.scope == "/fixture" }),
          let work = parent.children.first(where: { $0.tag == "Work" }) else {
        throw ReplayFailure("Expected fixture directory: " + (model.error ?? "absent"))
    }
    let controls = model.chromeInteractions
    try await until("Directory chip mounted") { controls.mountedIDs(in: .directory).contains(parent.id) }
    try controls.activate(.directory, id: parent.id)
    try await until("Semantic chip mounted") { controls.mountedIDs(in: .semantic).contains(work.id) }
    try controls.activate(.semantic, id: work.id)
    try await until("Work selected") { model.selectedFilter?.id == work.id }
    if let activityMotionReduced {
        // Keep the active conversation out of the canvas. Any running decoration
        // observed on this page must belong to a filter, not a task card.
        guard let reading = parent.children.first(where: { $0.tag == "Reading" }) else { throw ReplayFailure("Missing Reading tag") }
        try controls.activate(.semantic, id: reading.id)
        try await until("Reading tag settled") {
            model.selectedRailID == reading.id && !model.canvasState.isLayingOut
                && !model.canvasState.mountedCardIDs.contains("active")
        }
        try await inspectTagActivity(in: panel, directoryID: parent.id, childID: work.id, reduced: activityMotionReduced,
                                     currentButtons: { measuredButtons }) {
            try install(finished: true, revision: 2)
        }
        return
    }
    var observed = [[String: Any]]()
    func verify(_ step: String, directoryUnread: Int, tagUnread: Int) async throws {
        guard let parent = model.visibleFilters.first(where: { $0.scope == "/fixture" }),
              let child = parent.children.first(where: { $0.tag == "Work" }) else { throw ReplayFailure("Missing tags") }
        try check(parent.unreadCount == directoryUnread && child.unreadCount == tagUnread, "Unexpected counts at " + step)
        try check(model.selectedFilter?.id == child.id && controls.mountedIDs(in: .semantic).contains(child.id),
                  "Selected tag left its rail at " + step)
        try await pause(600)
        try panel.saveOffscreenImage(step)
        observed.append(["step": step, "directory": parent.unreadCount, "child": child.unreadCount])
    }
    try await verify("unread-two", directoryUnread: 2, tagUnread: 1)
    for (step, id, expected) in [("read-first", "first", 1), ("reread-first", "first", 1), ("read-last", "second", 0)] {
        try model.markRead(.init(threadID: JSONText(id), typeID: "agent"), version: JSONText(id))
        try await verify(step, directoryUnread: expected, tagUnread: 0)
    }
    try save(observed, "tag-unread.json")
}

@MainActor private func inspectTagActivity(in panel: Panel, directoryID: String, childID: String, reduced: Bool,
                                           currentButtons: () -> [String: CGRect], finishExecution: () throws -> Void) async throws {
    func surfaces() -> [NSView] {
        (panel.contentView?.descendants(NSView.self) ?? []).filter {
            $0.identifier?.rawValue == "OverviewTagActivityPerforations"
        }
    }
    func shapeLayers(_ layer: CALayer) -> [CAShapeLayer] {
        ([layer as? CAShapeLayer].compactMap { $0 }) + (layer.sublayers ?? []).flatMap(shapeLayers)
    }
    try await until("Visible Project and Work controls mount activity perforations") {
        surfaces().count == 2 && panel.occlusionState.contains(.visible)
    }
    try await until("Filter activity follows Reduce Motion") {
        surfaces().allSatisfy { view in
            guard let layer = view.layer else { return false }
            let holes = shapeLayers(layer).filter { $0.path?.isEmpty == false }
            return holes.count > 1 && holes.contains { $0.animation(forKey: "badge.sweep") != nil } == !reduced
        }
    }
    // The header enters from above. Anchor the pixel capture after its glyph stops moving
    // so every frame measures the dot pattern at the same window coordinates.
    var lastFrames = [CGRect]()
    var stationarySince = ContinuousClock.now
    try await until("Filter glyphs settle in the window") {
        let frames = surfaces().map { $0.convert($0.bounds, to: nil) }.sorted { $0.minX < $1.minX }
        if frames != lastFrames {
            lastFrames = frames
            stationarySince = .now
        }
        return frames.count == 2 && ContinuousClock.now - stationarySince >= .milliseconds(200)
    }
    // Get each button's actual window frame. The folder and the tag use separate
    // glyphs and the card behind the floating controls may overlap either one.
    func attribute(_ node: NSObject, _ name: String) -> Any? {
        node.responds(to: NSSelectorFromString(name)) ? node.value(forKey: name) : nil
    }
    func buttonFrames(_ node: NSObject, into result: inout [String: CGRect]) {
        if let id = attribute(node, "accessibilityIdentifier") as? String, [directoryID, childID].contains(id),
           attribute(node, "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue,
           let screenRect = attribute(node, "accessibilityFrame") as? NSValue {
            result[id] = panel.convertFromScreen(screenRect.rectValue)
        }
        for child in attribute(node, "accessibilityChildren") as? [NSObject] ?? [] {
            buttonFrames(child, into: &result)
        }
    }
    let buttons = currentButtons()
    var panelAX = [String: CGRect](), hostAX = [String: CGRect]()
    buttonFrames(panel, into: &panelAX)
    if let root = panel.contentView { buttonFrames(root, into: &hostAX) }
    try save(["window": NSStringFromRect(panel.frame), "controlAnchors": buttons.mapValues(NSStringFromRect),
              "panelAX": panelAX.mapValues(NSStringFromRect), "contentAX": hostAX.mapValues(NSStringFromRect),
              "nativeSurfaces": surfaces().map { NSStringFromRect($0.convert($0.bounds, to: nil)) }],
             "tag-activity-geometry.json")
    var samples = [[String: Any]]()
    var regions = [String: CGRect]()
    for (id, diameter) in [(directoryID, CGFloat(28.6)), (childID, CGFloat(39.6))] {
        guard let button = buttons[id] else { throw ReplayFailure("Missing measured button " + id) }
        guard let view = surfaces().first(where: {
            let frame = $0.convert($0.bounds, to: nil)
            return button.contains(CGPoint(x: frame.midX, y: frame.midY))
        }), let layer = view.layer else { throw ReplayFailure("Missing activity behind " + id) }
        let bounds = view.convert(view.bounds, to: nil)
        let glyphWidth = OverviewTagMetrics.chipHeight
        try check(abs(bounds.width - diameter) < 1 && abs(bounds.height - diameter) < 1
            && bounds.midX < button.minX + glyphWidth && abs(bounds.midY - button.midY) < 1,
            "Activity escaped the leading glyph of " + id)
        regions[id == directoryID ? "folder" : "semantic"] = bounds
        let holes = shapeLayers(layer).filter { $0.path?.isEmpty == false }
        let sweeps = holes.filter { $0.animation(forKey: "badge.sweep") != nil }
        try check(holes.contains { $0.opacity > 0 && ($0.fillColor?.alpha ?? 0) > 0 },
                  "No visible perforation layers behind " + id)
        samples.append(["id": id, "button": NSStringFromRect(button), "perforations": NSStringFromRect(bounds),
                        "shapeLayers": holes.count, "animatedLayers": sweeps.count])
    }
    let pixels = try await captureTagActivity(in: panel, regions: regions, reduced: reduced)
    try finishExecution()
    try await until("Completing the final running conversation removes both filter decorations") {
        surfaces().isEmpty
    }
    let filter = try await panel.filter()
    let config = panel.configuration()
    config.ignoreGlobalClipSingleWindow = true
    try await savePNG(SCScreenshotManager.captureImage(contentFilter: filter, configuration: config), "finished-filter-activity.png")
    try save(["reduceMotion": reduced, "running": samples, "pixelCounts": pixels, "finishedSurfaceCount": surfaces().count], "tag-activity.json")
}
