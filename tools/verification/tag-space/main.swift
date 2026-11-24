import AppKit
import SwiftUI
import WebKit
import ChiefCore
import ChiefPluginAPI
import ChiefHarnessCodex
import ChiefApplications
@testable import ChiefUI

private struct Failure: Error, CustomStringConvertible { let description: String }

private let chief = "/fixture/work/Chief"
private let other = "/fixture/personal/Chief"
private let reportCount = 12
private let size = CGSize(width: 2048, height: 1225)

private func thread(_ id: String, scope: String, tag: String, created: Double) throws -> JSONValue {
    try HarnessThread(id: JSONText(id), harnessID: "codex", revision: 1, sessionState: .null,
        observation: .init(latestExecution: try PublicExecution(executionID: JSONText("run-" + id),
            status: .completed, startedAt: 1, finishedAt: 2)), cwd: JSONText(scope), settings: .object([:]),
        createdAt: created, updatedAt: created, title: JSONText("Task " + id), tags: [JSONText(tag)],
        tagEmojis: [JSONText(tag): "📌"], directoryTag: scope == "inbox" ? "" : "Chief",
        directoryScope: JSONText(scope)).json
}

private func catalog(moved: Bool, created: Double) throws -> JSONValue {
    var threads = try (0..<5).map { try thread("agent-\($0)", scope: moved && $0 == 0 ? other : chief,
                                               tag: "共享", created: created + Double($0)) }
    threads.append(try thread("stock", scope: "inbox", tag: "股票行情", created: created))
    threads.append(try thread("personal", scope: other, tag: "共享", created: created))
    let reports: [JSONValue] = (0..<reportCount).map { index in
        let ref = ApplicationThreadRef(threadID: JSONText("report-\(index)"), typeID: "report.document")
        return .object(["id": .string(ref.threadID), "ref": ref.json, "revision": .integer(1),
            "createdAt": .number(created + 10 + Double(index)), "updatedAt": .number(created + 10 + Double(index)),
            "title": .text("Super Thread \(index)"), "archived": .bool(false), "scope": .text(chief),
            "tags": .object(["tags": .array([.text("Chief"), .text("共享")]), "semanticTags": .array([.text("共享")]),
                "directoryTags": .array([.text("Chief")]), "tagEmojis": .object(["共享": .text("📌")])]),
            "presentations": .array([]), "view": .object(["coverRevision": .text(moved && index == 0 ? "revised-cover" : "cover-\(index)"),
                    "contentRevision": .text("body-1"), "emoji": .text("📌"), "shortDescription": .text("Summary \(index)"),
                    "previewText": .text("Preview"), "readingSeconds": .integer(40), "relatedExecutions": .array([])])])
    }
    return .object(["revision": .integer(moved ? 2 : 1), "settingsRevision": .integer(0), "settings": .object([:]),
        "threads": .array(threads), "executions": .array([]), "defaultCwd": .text(chief), "applicationThreads": .array(reports)])
}

@MainActor private func readyBrowsers(in view: NSView) -> [WKWebView] {
    if let browser = view as? WKWebView { return browser.alphaValue > 0 && !browser.isLoading ? [browser] : [] }
    return view.subviews.flatMap { readyBrowsers(in: $0) }
}

@MainActor private func waitUntil(_ name: String, _ condition: () -> Bool) async throws {
    let start = ProcessInfo.processInfo.systemUptime
    while !condition() {
        guard ProcessInfo.processInfo.systemUptime - start < 12 else { throw Failure(description: "Timeout: " + name) }
        try await Task.sleep(for: .milliseconds(4))
    }
}

@MainActor private func run() async throws {
    try prepareIsolatedNativeReplay()
    let profile = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(UUID().uuidString)
    let workspace = NativeWorkspaceModel(client: RuntimeClient(profile: try RuntimeProfile(dataDirectory: profile)),
        preferences: DesktopPreferences(directory: profile), plugins: try .init(harnesses: [AnyHarnessPlugin(CodexHarnessPlugin())],
            sidecards: [], applications: NativeApplicationModules.make()))
    let host = NativeApplicationHost(workspace: workspace, navigationCallbacks: .init(openThread: { _, _ in },
        openExecution: { _ in }, followUp: { _, _ in }, openExternal: { _ in }))
    var queries = 0
    let bars = (1...32).map {
        "<i style='height:\(($0 * 37) % 100 + 1)px;animation-delay:\($0 * 8)ms'></i>"
    }.joined()
    let stylesheet = "<style>body{background:#162826;color:white}i{display:inline-block;width:7px;background:#62aa91;transform-origin:bottom;animation:grow 2s both}@keyframes grow{from{transform:scaleY(0)}}</style>"
    let factories = host.overviewFactories
    let model = NativeOverviewWorkspaceModel(workspace: workspace, applications: .init(
        projectionCapabilities: factories.projectionCapabilities, rendererContext: { plugin, entry, lifetime in
            let original = try factories.rendererContext(plugin, entry, lifetime)
            let domain = ApplicationDomainClient(pluginID: "report") { _, operation, input, _, _ in
                guard operation == "report.cover", let id = input["reportId"]?.stringValue else {
                    throw Failure(description: "Unexpected report request")
                }
                guard let revision = entry.view["coverRevision"]?.stringValue, id == entry.ref.threadID.string else {
                    throw Failure(description: "Cover query identity mismatch")
                }
                queries += 1
                return .object(["html": .text("\(stylesheet)<h1>\(id)/\(revision)</h1>\(bars)"),
                    "contentRevision": .text(revision)])
            }
            return .init(theme: original.theme, locale: original.locale, lifetime: lifetime, domain: domain,
                capabilities: original.capabilities, openThread: original.openThread, openExecution: original.openExecution)
        }, gitStatus: factories.gitStatus))
    let created = Date().timeIntervalSince1970 * 1000
    let authority = UUID()
    func install(moved: Bool) throws {
        let value = try catalog(moved: moved, created: created)
        try workspace.catalog.install(value)
        model.receive(moved ? .mutation(.object([:]), state: value, authority: authority) : .snapshot(value, authority: authority))
        if let error = model.error { throw Failure(description: error) }
    }
    try install(moved: false)
    let top = model.visibleFilters
    guard let workFolder = top.first(where: { $0.isDirectory && $0.scope == chief }),
          let personalFolder = top.first(where: { $0.isDirectory && $0.scope == other }),
          let stockTag = top.first(where: { !$0.isDirectory && $0.scope == "inbox" && $0.tag == "股票行情" }) else {
        throw Failure(description: "Missing top-level Chief folders or 股票行情 tag")
    }
    // Sample the standalone selector before mounting any Report browser.
    model.setCollectionWindowSize(size)
    var selectionMs = [Double](), geometryMs = [Double]()
    for _ in 0..<12 {
        model.selectTag(stockTag)
        let start = ProcessInfo.processInfo.systemUptime
        model.selectTag(workFolder)
        selectionMs.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
    }
    model.selectTag(stockTag)
    let panel = NSPanel(contentRect: .init(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
    var buttons = [String: CGRect]()
    let overview = NativeOverviewWorkspaceView(model: model, callbacks: .init(
        openThread: { _, _ in }, openApplication: { _, _ in }, onSettings: {}))
    let view = NSHostingView(rootView: overview.overlayPreferenceValue(OverviewTagBounds.self) { anchors in
        GeometryReader { proxy in
            Color.clear.onChange(of: anchors.mapValues { proxy[$0] }, initial: true) { _, frames in buttons = frames }
        }.allowsHitTesting(false)
    })
    panel.appearance = NSAppearance(named: .darkAqua)
    panel.ignoresMouseEvents = true
    panel.contentView = view
    panel.orderBack(nil)
    defer { panel.orderOut(nil) }
    let canvas = model.canvasState
    let stock: Set<String> = ["stock"]
    let crowded = Set((0..<5).map { "agent-\($0)" } + (0..<reportCount).map { "report-\($0)" })
    func settled(_ ids: Set<String>) -> Bool {
        Set(canvas.presentedPlacements.map(\.id)) == ids && canvas.mountedCardIDs == ids
            && !canvas.isLayingOut && ids.allSatisfy { canvas.allowsActivation(cardID: $0) }
    }
    try await waitUntil("initial card") { settled(stock) }
    var rows = [[String: Any]]()
    func press(_ filter: NativeOverviewFilter) throws -> Double {
        let id = filter.id
        guard let rect = buttons[id], !rect.isEmpty else {
            throw Failure(description: "Missing chip geometry for " + id + " in " + String(describing: buttons.keys))
        }
        let center = CGPoint(x: rect.midX, y: view.bounds.height - rect.midY)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: center, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
        }
        let up = event(.leftMouseUp)
        NSApp.postEvent(up, atStart: true)
        let start = ProcessInfo.processInfo.systemUptime
        panel.sendEvent(event(.leftMouseDown))
        if NSApp.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: false) === up {
            _ = NSApp.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true)
            panel.sendEvent(up)
        }
        return start
    }
    for cycle in 0..<4 {
        for (target, ids) in [(workFolder, crowded), (stockTag, stock)] {
            let before = queries
            let start = try press(target)
            func ms() -> Double { (ProcessInfo.processInfo.systemUptime - start) * 1000 }
            let dispatch = ms()
            try await waitUntil("selection") { model.selectedFilter?.id == target.id }
            let selected = ms()
            try await waitUntil("placements") { Set(canvas.presentedPlacements.map(\.id)) == ids }
            let placed = ms()
            try await waitUntil("settle") { settled(ids) }
            let ready = ms()
            if target.id == workFolder.id {
                try await waitUntil("rendered report covers") { readyBrowsers(in: view).count == reportCount }
            }
            let covers = ms()
            guard let viewport = canvas.camera.viewport, viewport.width == size.width else {
                throw Failure(description: "Filter controls changed the full-width card viewport")
            }
            if target.id == workFolder.id && cycle == 0 {
                let members = model.items.map(\.member)
                let canvasSize = CGSize(width: viewport.width, height: viewport.height)
                for _ in 0..<12 {
                    let start = ProcessInfo.processInfo.systemUptime
                    _ = try NativeOverviewLayout.solve(members: members, windowSize: canvasSize)
                    geometryMs.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                }
            }
            try await Task.sleep(for: .milliseconds(300))
            rows.append(["cycle": cycle, "scope": target.scope, "filterID": target.id, "dispatchMs": dispatch, "selectedMs": selected,
                "canvasWidth": viewport.width, "placedMs": placed, "settledMs": ready, "coversAndSettledMs": covers, "coverQueries": queries - before])
        }
    }
    _ = try press(workFolder)
    try await waitUntil("interrupted layout") { canvas.isLayingOut && Set(canvas.presentedPlacements.map(\.id)) == crowded }
    _ = try press(stockTag)
    try await waitUntil("rapid return accepted") { model.selectedFilter?.id == stockTag.id }
    try await Task.sleep(for: .milliseconds(40))
    _ = try press(personalFolder)
    try await waitUntil("same-name selection accepted") { model.selectedFilter?.id == personalFolder.id }
    try await waitUntil("rapid final membership") { settled(["personal"]) }
    try install(moved: true)
    try await waitUntil("updated selection") { settled(["agent-0", "personal"]) }
    _ = try press(workFolder)
    try await waitUntil("revisited scope") { settled(crowded.subtracting(["agent-0"])) }
    try await waitUntil("revisited covers") { readyBrowsers(in: view).count == reportCount }
    var headings = Set<String>()
    for browser in readyBrowsers(in: view) {
        let heading = try await browser.callAsyncJavaScript("return document.querySelector('h1').textContent",
            arguments: [:], in: nil, contentWorld: .defaultClient)
        if let text = heading as? String { headings.insert(text) }
    }
    let expected = Set((0..<reportCount).map { "report-\($0)/" + ($0 == 0 ? "revised-cover" : "cover-\($0)") })
    guard headings == expected else { throw Failure(description: "Mounted wrong cover revision or identity") }
    guard queries >= reportCount + 1, model.error == nil, canvas.layoutError == nil else { throw Failure(description: "Cover or layout failed") }
    let result: [String: Any] = ["rows": rows, "windowWidth": view.bounds.width, "windowHeight": view.bounds.height,
        "os": ProcessInfo.processInfo.operatingSystemVersionString, "pid": ProcessInfo.processInfo.processIdentifier,
        "selectionMs": selectionMs, "geometryMs": geometryMs, "rapidFinal": other, "updatedOtherIDs": ["agent-0", "personal"],
        "revisitedCovers": headings.sorted(), "coverQueries": queries]
    try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    host.release()
    await model.stop()
    await workspace.client.close()
}

@main struct TagSpaceProbe {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do { try await run(); exit(0) }
            catch { print("Tag space probe: \(error)"); exit(1) }
        }
        app.run()
    }
}
