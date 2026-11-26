import AppKit
import SwiftUI
@testable import ChiefUI
import ChiefCore
import ChiefHarnessCodex
import ChiefPluginAPI

private struct DemoError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

@MainActor private struct Fixture {
    let workspace: NativeWorkspaceModel
    let presentation: NativeWorkspacePresentation

    init() throws {
        let directory = URL(filePath: FileManager.default.currentDirectoryPath)
        let preferences = DesktopPreferences(directory: directory)
        try preferences.setOnboardingCompleted(true)
        let profile = try RuntimeProfile(dataDirectory: directory, homeDirectory: directory)
        workspace = NativeWorkspaceModel(client: RuntimeClient(profile: profile), preferences: preferences,
            plugins: try .init(harnesses: [AnyHarnessPlugin(CodexHarnessPlugin())], sidecards: [], applications: []))
        presentation = NativeWorkspacePresentation(workspace: workspace)
    }

    func load() async throws {
        let records = try ["Design", "Review", "moku"].map { name in
            try HarnessThread(id: JSONText(name), harnessID: "codex", revision: 1, sessionState: .null,
                observation: .init(), cwd: "/fixture", settings: .object([:]), createdAt: 1, updatedAt: 1,
                title: JSONText(name), tags: [JSONText(name)], moku: name == "moku" ? true : nil,
                transcript: name == "moku" ? .array([]) : nil, tagEmojis: [JSONText(name): "📌"],
                directoryTag: "Demo", directoryScope: "/fixture").json
        }
        let snapshot: JSONValue = .object(["revision": .integer(1), "settingsRevision": .integer(0),
            "defaultCwd": .text("/fixture"), "settings": .object([:]), "threads": .array(records),
            "executions": .array([]), "applicationThreads": .array([])])
        let event = RuntimeClientEvent.snapshot(snapshot, authority: UUID())
        await workspace.installPrepared(snapshot, event: event)
        guard workspace.hasInitialContent else { throw DemoError("Could not load the demo catalog") }
        // The windowless replay has no onAppear to start the presentation.
        if workspace.onCatalogChange == nil { presentation.overview.receive(event) }
        guard let folder = presentation.overview.filters.first(where: { $0.isDirectory }) else {
            throw DemoError("Missing demo folder")
        }
        presentation.overview.selectTag(folder)
    }
}

@MainActor private struct DemoWindow: App {
    let fixture: Fixture
    @State private var swipeRequests = 0
    @State private var testRequests = 0
    @State private var pattern = NativeOverviewVerticalSwipe.defaultFeedbackPattern
    init() {
        do { fixture = try Fixture() }
        catch { fatalError(String(describing: error)) }
    }

    var body: some Scene {
        Window("Tag Space Haptics", id: "tag-space-haptics") {
            NativeWorkspaceView(model: fixture.workspace, presentation: fixture.presentation)
                .environment(\.requestRailSwipeFeedback, {
                    NativeOverviewVerticalSwipe.playFeedback(pattern)
                    swipeRequests += 1
                })
                .modifier(NativeWorkspaceWindowSurface())
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    HStack {
                        Picker("反馈模式", selection: $pattern) {
                            Text("通用").tag(NSHapticFeedbackManager.FeedbackPattern.generic)
                            Text("对齐").tag(NSHapticFeedbackManager.FeedbackPattern.alignment)
                            Text("档位").tag(NSHapticFeedbackManager.FeedbackPattern.levelChange)
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                        Text("滑动请求 \(swipeRequests)").monospacedDigit()
                        Spacer()
                        Text("一指贴住触控板，按 ⌘T").foregroundStyle(.secondary)
                        Button("测试轻触（\(testRequests)）") {
                            NativeOverviewVerticalSwipe.playFeedback(pattern)
                            testRequests += 1
                        }
                        .keyboardShortcut("t", modifiers: .command)
                    }
                    .padding(10)
                    .background(.regularMaterial)
                }
                .task {
                    do { try await fixture.load() }
                    catch { print(error); exit(1) }
                }
        }
        .nativeWorkspaceWindowStyle().defaultSize(width: 900, height: 620)
        .restorationBehavior(.disabled)
    }
}

private final class ScrollSample: NSEvent {
    let y: CGFloat
    let direct, momentum: NSEvent.Phase
    let precise: Bool

    init(_ y: CGFloat, _ phase: NSEvent.Phase, _ momentum: NSEvent.Phase, precise: Bool) {
        self.y = y
        self.direct = phase
        self.momentum = momentum
        self.precise = precise
        super.init()
    }
    required init?(coder: NSCoder) { nil }
    override var scrollingDeltaX: CGFloat { 0 }
    override var scrollingDeltaY: CGFloat { y }
    override var isDirectionInvertedFromDevice: Bool { false }
    override var hasPreciseScrollingDeltas: Bool { precise }
    override var phase: NSEvent.Phase { direct }
    override var momentumPhase: NSEvent.Phase { momentum }
    override var timestamp: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

@main @MainActor private enum Demo {
    static func main() async {
        do {
            try prepareIsolatedNativeReplay()
            if CommandLine.arguments.contains("--replay") { try await replay() }
            else { DemoWindow.main() }
        } catch { print(error); exit(1) }
    }

    static func replay() async throws {
        let fixture = try Fixture()
        try await fixture.load()
        let model = fixture.presentation.overview
        guard let design = model.selectedDirectory?.children.first(where: { $0.tag == "Design" }),
              let review = model.selectedDirectory?.children.first(where: { $0.tag == "Review" }) else {
            throw DemoError("Missing demo tags")
        }
        var router = NativeOverviewVerticalSwipe()
        var requests = 0
        func check(_ label: String, _ y: CGFloat, _ phase: NSEvent.Phase, momentum: NSEvent.Phase = [],
                   precise: Bool = true, available: Bool = true, claimed: Bool = true,
                   selected: String?, count: Int) throws {
            let sample = ScrollSample(y, phase, momentum, precise: precise)
            let consumed = router.route(sample, canFilter: { available }, perform: model.stepRail(up:),
                                        requestFeedback: { requests += 1 })
            let rail = model.selectedRailID ?? "whole folder"
            print("\(label) → \(rail) · \(requests) feedback requests")
            guard consumed == claimed, model.selectedRailID == selected, requests == count else {
                throw DemoError("Unexpected routing, selection or feedback at \(label)")
            }
        }
        try check("Swipe down from the whole folder", -30, .began, selected: nil, count: 0)
        try check("Swipe up 10 pt", 10, .began, selected: nil, count: 0)
        try check("Reach 24 pt", 14, .changed, selected: design.id, count: 1)
        try check("Reverse before lifting", -50, .changed, selected: design.id, count: 1)
        try check("Lift", 0, .ended, selected: design.id, count: 1)
        try check("Momentum", 60, [], momentum: .began, selected: design.id, count: 1)
        try check("Momentum ends", 0, [], momentum: .ended, selected: design.id, count: 1)
        try check("Wrap first to last", -30, .began, selected: "unread", count: 2)
        try check("Wrap last to first", 30, .began, selected: design.id, count: 3)
        try check("Mouse wheel", 1, [], precise: false, selected: review.id, count: 3)
        try check("Phase-less precise scroll", 60, [], claimed: false, selected: review.id, count: 3)
        try check("Excluded surface", 60, .began, available: false, claimed: false, selected: review.id, count: 3)
    }
}
