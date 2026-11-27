import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import ChiefUI
import SwiftUI

/// Renderer composition only. This graph contains no profile, Runtime client or host file services.
@MainActor
private struct DemoCatalog {
    @MainActor enum Card {
        case report(DemoReport)
        case agent(DemoThread, HarnessOverviewSnapshot)

        var id: String {
            switch self {
            case .report(let report): report.snapshot.entry.ref.threadID.string
            case .agent(let sample, _): sample.thread.id.string
            }
        }
        var directory: JSONText {
            switch self {
            case .report(let report): report.source.thread.directoryTag
            case .agent(let sample, _): sample.thread.directoryTag
            }
        }
        var scope: JSONText {
            switch self {
            case .report(let report): report.source.thread.directoryScope
            case .agent(let sample, _): sample.thread.directoryScope
            }
        }
        var tagEmojis: [JSONText: JSONText] {
            switch self {
            case .report(let report): report.snapshot.entry.tags.tagEmojis
            case .agent(let sample, _): sample.thread.tagEmojis
            }
        }
        var running: Bool {
            if case .agent(let sample, _) = self { return sample.thread.observation.isExecutionActive }
            return false
        }
        var footprint: HarnessOverviewFootprint {
            switch self {
            case .report(let report): report.snapshot.envelope.footprint
            case .agent(_, let snapshot): snapshot.envelope.footprint
            }
        }
    }

    let cards: [Card]
    let filters: [NativeOverviewFilter]
    let harness: AnyHarnessPlugin
    let plugins: NativePluginComposition

    init() throws {
        plugins = try NativePlugins.make()
        let harness = try plugins.harnesses.require("codex")
        self.harness = harness
        let now = floor(Date().timeIntervalSince1970 * 1000)
        let plugin = try plugins.applications.requireThread("report.document")
        let boards = [DemoSample.checkout, DemoSample.api, DemoSample.launch]
        var cards: [Card] = []
        for samples in boards {
            for (index, sample) in samples.enumerated() {
                let thread = try DemoThread(sample, at: now - Double(index + 1) * 120_000)
                // A report occupies its cited execution’s place on the board.
                if let story = sample.report {
                    cards.append(.report(try DemoReport(story, plugin: plugin, source: thread, harness: harness)))
                } else {
                    let snapshot = try harness.projectOverview(input: thread.input, availableColumns: HarnessOverviewCapacity.maximumColumns)
                    cards.append(.agent(thread, snapshot))
                }
            }
        }
        self.cards = cards
        var seen = Set<JSONText>()
        filters = cards.compactMap { card in
            guard seen.insert(card.scope).inserted else { return nil }
            let members = cards.filter { $0.scope == card.scope }
            let emojis = members.reduce(into: [JSONText: JSONText]()) { $0.merge($1.tagEmojis) { first, _ in first } }
            let children: [NativeOverviewFilter] = emojis.sorted { $0.key.string < $1.key.string }.map { tag, emoji in
                let matching = members.filter { $0.tagEmojis[tag] != nil }
                return .init(tag: tag.string, displayTag: SemanticTagLabel.display(name: tag.string, emoji: emoji.string),
                    emoji: emoji.string, scope: card.scope.string, count: matching.count, hasActiveTasks: matching.contains(where: \.running))
            }
            return .init(tag: card.directory.string, scope: card.scope.string, count: members.count,
                isDirectory: true, children: children, hasActiveTasks: members.contains(where: \.running))
        }
    }
}

public struct DemoWorkspace: View {
    @State private var catalog = Result { try DemoCatalog() }
    @State private var canvas = NativeOverviewCanvasState()
    @State private var shell = DemoWorkspaceShell()
    @State private var directoryID: String?
    @State private var selection: [String: NativeOverviewRailChoice] = [:]
    @State private var reading: DemoCatalog.Card?
    @State private var reportExecution: ApplicationExecutionRef?
    @State private var reportExecutionBack: (() -> Void)?
    @State private var sourceFrame: CGRect?
    @Environment(\.colorScheme) private var scheme
    private let locale = DesktopLocale.system

    public init() {}

    public var body: some View {
        Group {
            switch catalog {
            case .success(let catalog): workspace(catalog)
            case .failure(let error): Text(error.localizedDescription).textSelection(.enabled)
            }
        }
        .coordinateSpace(name: "workspace")
        .environment(\.locale, Locale(identifier: locale.rawValue))
        .environment(\.nativeOfflineDraftEditing, true)
    }

    private func workspace(_ catalog: DemoCatalog) -> some View {
        let agent: DemoThread? = if case .agent(let sample, _) = reading { sample } else { nil }
        let detail: DemoThread? = if case .report(let report) = reading, reportExecution == report.source.reference {
            report.source
        } else { agent }
        return NativeMokuScene(state: shell.scene) {
            NativeReadingPageStack(open: reading != nil, identity: JSONText(reading?.id ?? "overview"), motion: shell.motion,
                enabled: !shell.scene.settingsOpen, focusBlur: true, stationaryParent: true, emphasizedOpening: true,
                panel: true, isolatesParent: true, panelSource: { sourceFrame }, panelFrontIdentity: "workspace-reading-front",
                threadPanelMotion: agent != nil, reportPanelMotion: agent == nil && reading != nil,
                onPanelOutsideClick: closeReader, onClose: {
                    reading = nil
                    reportExecution = nil
                    reportExecutionBack = nil
                    shell.showOverview()
                }) {
                if let folder = catalog.filters.first(where: { $0.id == directoryID }) ?? catalog.filters.first {
                    overview(catalog, folder: folder)
                }
            } front: {
                if let reading { reader(reading, catalog: catalog) }
            }
        } dock: {
            NativeMokuDock(state: shell.scene, draft: shell.draft, cwd: detail?.thread.cwd ?? "",
                threadID: detail?.thread.id, threadHarness: detail == nil ? nil : catalog.harness,
                onThreadClose: reportExecutionBack ?? closeReader, mode: detail?.thread.observation.isExecutionActive == true ? .running : .idle,
                running: detail?.thread.observation.isExecutionActive == true, disabled: true,
                onSend: { _ in throw DemoThread.readOnly }, onCancel: {})
        } settings: {
            if shell.scene.settingsOpen { shell.settingsPage(locale: locale, plugins: catalog.plugins) }
        }
        .overlay(alignment: .topLeading) {
            NativeWindowNavigationView(action: nil, hidden: reading != nil, suspended: shell.scene.settingsOpen)
        }
        .onAppear { shell.showOverview() }
    }

    private func overview(_ catalog: DemoCatalog, folder: NativeOverviewFilter) -> some View {
        let choice = selection[folder.id]
        let tag: NativeOverviewFilter? = if case .tag(let tag) = choice { tag } else { nil }
        let cards = catalog.cards.filter { card in
            guard card.scope.string == folder.scope else { return false }
            switch choice {
            case .tag(let tag): return card.tagEmojis[JSONText(tag.tag)] != nil
            case .status(.running): return card.running
            case .status(.unread): return false
            default: return true
            }
        }
        let items = cards.map { NativeOverviewItem(id: $0.id, columns: $0.footprint.columns, rows: $0.footprint.rows) }
        return GeometryReader { geometry in
            let viewport = NativeOverviewWorkspaceView.viewport(in: geometry.size, hasFilters: true, hasDock: true)
            NativeOverviewCanvas(items: items, sceneKey: folder.id + (choice?.id ?? ""), state: canvas,
                selectionID: tag?.id ?? folder.id, toolbarBottom: viewport.toolbarBottom,
                bottomReservedHeight: viewport.bottomReservedHeight,
                headerInputBottom: NativeOverviewChrome.headerBottom(in: geometry.size, hasFilters: true),
                interactionPaused: shell.scene.interactionPaused || shell.motion.active,
                inputRegions: shell.scene.canvasInputRegions) { item in
                if let card = catalog.cards.first(where: { $0.id == item.id }) {
                    cardView(card).environment(\.threadCardNativeDecorationsEnabled, true)
                }
            }
            .overlay {
                if cards.isEmpty {
                    NativeOverviewStatusEmptyState(title: locale.text("没有未读会话", "No unread conversations"))
                }
            }
            .overlay(alignment: .leading) {
                NativeOverviewChrome.rail(choices: folder.children.map(NativeOverviewRailChoice.tag) + [.status(.running), .status(.unread)],
                    selectedID: choice?.id, viewportWidth: geometry.size.width, strings: .init(locale: locale),
                    onSelect: { selection[folder.id] = $0 }, onClearUnread: { _ in })
                    .opacity(reading == nil ? 1 : 0)
            }
            .overlay(alignment: .top) {
                NativeOverviewChrome(filters: catalog.filters, viewportHeight: geometry.size.height,
                    selectedTag: tag?.tag ?? folder.tag, selectedScope: folder.scope, selectedKind: tag == nil ? .directory : .semantic,
                    strings: .init(locale: locale), onTagChange: { next in
                        guard let next else { return }
                        if next.id == folder.id { selection.removeValue(forKey: next.id) }
                        directoryID = next.id
                    }, onSettings: shell.openSettings)
                    .opacity(reading == nil ? 1 : 0)
            }
        }
        .nativeOverviewActivity(visible: reading == nil && !shell.scene.settingsOpen)
    }

    private func open(_ card: DemoCatalog.Card) {
        sourceFrame = canvas.displayedFrame(for: card.id)
        reading = card
        let threadID: JSONText? = if case .agent(let sample, _) = card { sample.thread.id } else { nil }
        shell.showReader(threadID: threadID)
    }

    private func closeReader() { shell.motion.close() }

    @ViewBuilder private func cardView(_ card: DemoCatalog.Card) -> some View {
        switch card {
        case .agent(let sample, let snapshot):
            Button { open(card) } label: {
                snapshot.card(respond: { _ in throw DemoThread.readOnly }, openThread: { open(card) })
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).help(sample.thread.title.string)
        case .report(let report):
            render {
                try report.snapshot.card(context: report.context(theme: theme, locale: JSONText(locale.rawValue)),
                                         openThread: { open(card) })
            }
        }
    }

    private var theme: PluginTheme { scheme == .dark ? .dark : .light }
    @ViewBuilder private func reader(_ card: DemoCatalog.Card, catalog: DemoCatalog) -> some View {
        switch card {
        case .agent(let sample, _):
            NativeAgentThreadWorkspace(harnessHost: DemoReadingHost(harness: catalog.harness),
                thread: sample.thread, registry: catalog.plugins.sidecards,
                services: .init(send: { _, _ in throw DemoThread.readOnly },
                    stageAttachments: { _ in throw DemoThread.readOnly }, discardAttachments: { _ in },
                    openExternal: { _ in throw DemoThread.readOnly }),
                onBack: closeReader, onFollowUpVisibilityChange: { _ in })
            .environment(\.nativeAgentPanelClose, closeReader)
        case .report(let report):
            render {
                try report.plugin.detail(props: .init(entry: report.snapshot.entry,
                    context: report.context(theme: theme, locale: JSONText(locale.rawValue))))
            }
            .modifier(NativeApplicationReadingPanel(enabled: true, onClose: closeReader))
            .environment(\.nativeApplicationReadingPanel, true)
            .environment(\.nativeReportExecutionInputChanged, { reference, ready, back in
                guard reading?.id == card.id else { return }
                let visible = reference == report.source.reference ? reference : nil
                let admitted = visible != nil && ready
                guard visible != reportExecution || admitted != shell.scene.inputAdmissionReady else { return }
                reportExecution = visible
                reportExecutionBack = visible == nil ? nil : back
                shell.showReader(threadID: visible?.thread.threadID, inputReady: admitted)
            })
        }
    }

    @ViewBuilder private func render(_ build: () throws -> AnyView) -> some View {
        switch Result(catching: build) {
        case .success(let view): view
        case .failure(let error): Text(error.localizedDescription)
        }
    }
}
