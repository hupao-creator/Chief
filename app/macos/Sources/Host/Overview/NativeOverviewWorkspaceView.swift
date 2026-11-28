import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI

@MainActor
public struct NativeOverviewWorkspaceCallbacks {
    public let openThread: (JSONText, HarnessReadingTarget?) -> Void
    public let openApplication: (ApplicationThreadRef, HarnessReadingTarget?) -> Void
    public let onSettings: () -> Void
    /// Settings bounds in the logical client viewport, with a top-left origin.
    public let onSettingsWithOrigin: ((CGRect) -> Void)?
    public let onSettingsFrameChange: ((CGRect?) -> Void)?
    public let onRestart: (() -> Void)?
    public init(openThread: @escaping (JSONText, HarnessReadingTarget?) -> Void,
                openApplication: @escaping (ApplicationThreadRef, HarnessReadingTarget?) -> Void,
                onSettings: @escaping () -> Void,
                onRestart: (() -> Void)? = nil,
                onSettingsWithOrigin: ((CGRect) -> Void)? = nil,
                onSettingsFrameChange: ((CGRect?) -> Void)? = nil) {
        self.openThread = openThread; self.openApplication = openApplication
        self.onSettings = onSettings; self.onRestart = onRestart
        self.onSettingsWithOrigin = onSettingsWithOrigin; self.onSettingsFrameChange = onSettingsFrameChange
    }
}

/// A stable reference for the current callbacks. The view is reconstructed with
/// fresh closures by its owner, but already-mounted cards retain this store, so
/// actions always invoke the latest receiver.
@MainActor private final class NativeOverviewWorkspaceCallbackStore {
    var current: NativeOverviewWorkspaceCallbacks
    init(_ callbacks: NativeOverviewWorkspaceCallbacks) { current = callbacks }
}

/// Full overview composition; all semantic content is rendered by the owning native
/// plugin snapshot. The surrounding navigation/Moku scene remains owned by the shell.
@MainActor
public struct NativeOverviewWorkspaceView: View {
    public let model: NativeOverviewWorkspaceModel
    public let callbacks: NativeOverviewWorkspaceCallbacks
    public var interactionPaused: Bool
    public var chromeVisible: Bool
    public var readingMotion: NativeReadingPageMotion?
    public var landing: Bool
    @Environment(\.nativeCanvasInputRegions) private var sharedInputRegions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var localInputRegions = NativeCanvasInputRegions()
    @State private var callbackStore: NativeOverviewWorkspaceCallbackStore
    private var inputRegions: NativeCanvasInputRegions { sharedInputRegions ?? localInputRegions }
    private var locale: DesktopLocale { model.workspace.locale }
    public init(model: NativeOverviewWorkspaceModel, callbacks: NativeOverviewWorkspaceCallbacks,
                interactionPaused: Bool = false, landing: Bool = false,
                chromeVisible: Bool = true, readingMotion: NativeReadingPageMotion? = nil) {
        self.model = model; self.callbacks = callbacks; self.interactionPaused = interactionPaused
        self.landing = landing; self.chromeVisible = chromeVisible
        self.readingMotion = readingMotion
        _callbackStore = State(initialValue: NativeOverviewWorkspaceCallbackStore(callbacks))
    }
    public var body: some View {
        callbackStore.current = callbacks
        return GeometryReader { geometry in
            let filters = landing ? [] : model.visibleFilters
            let hasFilters = !filters.isEmpty
            let viewport = Self.viewport(in: geometry.size, hasFilters: hasFilters,
                                         hasDock: model.workspace.catalog.hasMoku)
            let headerBottom = NativeOverviewChrome.headerBottom(in: geometry.size, hasFilters: !landing && hasFilters)
            // The last card can make the Dock switch to landing before the
            // canvas admits its empty layout. Keep that exit drawable while
            // landing and its input take over immediately.
            let retiringToLanding = landing && !model.facts.settingsOpen
                && model.content.isEmpty
                && (!model.canvasState.presentedPlacements.isEmpty || model.canvasState.isLayingOut)
            let canvasVisible = !landing || retiringToLanding
            ZStack {
                NativeOverviewCanvas(contentSource: model.content, sceneKey: model.sceneKey, state: model.canvasState,
                    selectionID: model.statusFilter == .unread ? nil : model.selectedFilter?.id,
                    toolbarBottom: viewport.toolbarBottom, bottomReservedHeight: viewport.bottomReservedHeight,
                    headerInputBottom: headerBottom,
                    visible: model.facts.overviewVisible && model.facts.documentVisible && canvasVisible,
                    layoutPaused: !model.presentationActive,
                    cloudAnimationsEnabled: !model.facts.settingsOpen && !landing,
                    interactionPaused: interactionPaused || landing, resetEpoch: model.recoveryEpoch,
                    revisions: model.revisions, onRevisionsConsumed: { model.consumeRevisions(through: $0) },
                    onRetainedPresentationIDsChanged: { model.retainPresentations($0) },
                    cardContentIdentity: ObjectIdentifier(model),
                    inputRegions: inputRegions) { item in
                        NativeOverviewWorkspaceCard(item: item, model: model, callbacks: callbackStore)
                            .environment(\.locale, Locale(identifier: model.workspace.locale.rawValue))
                            .environment(\.threadCardNativeDecorationsEnabled, true)
                    }
                    .opacity(canvasVisible ? 1 : 0)
                    .allowsHitTesting(!landing)
                    .accessibilityHidden(landing)
                if !landing && model.showsEmptyState {
                    switch model.statusFilter {
                    case .running, .unread:
                        let rail = NativeOverviewChrome.railGeometry(
                            viewportWidth: geometry.size.width, topSemantic: model.isTopSemanticSelected)
                        let sideInset = model.railChoices.isEmpty ? 16 : rail.maximumWidth + rail.inset + 12
                        let recent = NativeOverviewRecentThreadList(
                            title: model.statusFilter == .running
                                ? locale.text("最近完成", "Recently completed") : locale.text("最近阅读", "Recently read"),
                            threads: model.recentStatusThreads) { id in
                                guard model.containsGlobalThread(id) else { return }
                                callbackStore.current.openThread(id, nil)
                            }
                        NativeOverviewStatusEmptyState(title: emptyTitle, recent: recent,
                            recentInsets: EdgeInsets(top: headerBottom, leading: sideInset,
                                                    bottom: viewport.bottomReservedHeight, trailing: sideInset),
                            recentInteractive: !interactionPaused && chromeVisible)
                    case .completed:
                        NativeOverviewStatusEmptyState(title: emptyTitle)
                    case .all:
                        NativeOverviewEmptyState(title: emptyTitle, detail: locale.text("切换标签筛选以查看其他 Thread。", "Switch tag filters to see other threads."))
                    }
                }
                if let error = model.error ?? model.canvasState.layoutError {
                    VStack {
                        HStack(spacing: 8) {
                            Text(locale.text("布局暂未更新，请重试。", "The layout could not be updated. Please retry."))
                                .help(error)
                            Button(locale.text("重试", "Retry")) {
                                model.refresh()
                                model.canvasState.retryLayout()
                            }.buttonStyle(.plain).foregroundStyle(NativePalette.overviewAccentText.swiftUI)
                        }.font(NativeTypography.inter(size: 12)).padding(10)
                            .background(NativePalette.overview.surface.swiftUI, in: RoundedRectangle(cornerRadius: 8))
                            .padding(.top, 72)
                        Spacer()
                    }
                    .accessibilityLabel(error)
                }
                if model.canvasState.overflowAttentionCount > 0 {
                    VStack {
                        Spacer()
                        NativeOverviewAttentionIndicator(text: locale.text("\(model.canvasState.overflowAttentionCount) 待介入", "\(model.canvasState.overflowAttentionCount) need attention"))
                            .padding(.bottom, 20)
                    }
                }
            }
            .overlay(alignment: .leading) {
                if !landing {
                    NativeOverviewChrome.rail(choices: model.railChoices, selectedID: model.selectedRailID,
                        viewportWidth: geometry.size.width, topSemantic: model.isTopSemanticSelected,
                        strings: chromeStrings, onSelect: model.selectRailChoice, onClearUnread: model.clearUnread(inTag:),
                        interactions: model.chromeInteractions)
                        .modifier(chromePresentation(edge: .leading))
                        .modifier(StartupSkilletChrome())
                }
            }
            .overlay {
                NativeOverviewRefreshDecoration(operation: model.featuredOperation,
                    visible: model.facts.overviewVisible && model.facts.documentVisible && !landing).allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                NativeOverviewChrome(filters: filters, viewportHeight: geometry.size.height,
                    selectedTag: model.selectedTag,
                    selectedScope: model.selectedScope, selectedKind: model.tagSelection?.kind,
                    strings: chromeStrings,
                    onTagChange: model.selectTopFilter,
                    onSettings: callbacks.onSettings,
                    onRestart: callbacks.onRestart,
                    onSettingsWithOrigin: callbacks.onSettingsWithOrigin,
                    onSettingsFrameChange: callbacks.onSettingsFrameChange,
                    interactions: model.chromeInteractions)
                    .modifier(chromePresentation(edge: .top))
                    .modifier(StartupSkilletChrome())
            }
            .onChange(of: geometry.size, initial: true) { _, size in model.setCollectionWindowSize(size) }
        }
        .nativeOverviewActivity(visible: chromeVisible && !landing && model.facts.overviewVisible
            && model.facts.documentVisible && !model.facts.settingsOpen)
        .environment(\.nativeCanvasInputRegions, inputRegions)
        .environment(\.locale, Locale(identifier: locale.rawValue))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(locale.text("会话俯瞰", "Conversation overview"))
    }

    private func chromePresentation(edge: Edge) -> some ViewModifier {
        OverviewChromePresentation(edge: edge, interactive: chromeVisible, travel: readingMotion?.parentTravel,
                                   reduceMotion: reduceMotion)
    }

    public static func viewport(in size: CGSize, hasFilters: Bool, hasDock: Bool) -> NativeOverviewViewport {
        // Visibility probes measure the persistent header and idle Dock extents.
        let dock = NativeMokuCapsuleLayout.idleSurface(in: CGRect(origin: .zero, size: size))
        return .init(width: size.width, height: size.height,
                     toolbarBottom: size.width <= CGFloat(NativeOverviewCameraGeometry.compactViewportWidth) && hasFilters
                        ? OverviewTagMetrics.narrowToolbarClearance : OverviewTagMetrics.wideToolbarClearance,
                     bottomReservedHeight: hasDock ? size.height - dock.minY : 0)
    }

    private var emptyTitle: String {
        switch model.statusFilter {
        case .running: return locale.text("没有运行中的会话", "No running conversations")
        case .unread: return locale.text("没有未读会话", "No unread conversations")
        case .completed: return locale.text("没有已完成的会话", "No completed conversations")
        case .all: break
        }
        return locale.text("没有 \(model.selectedFilter?.tag ?? model.selectedTag) 会话", "No \(model.selectedFilter?.tag ?? model.selectedTag) conversations")
    }
    private var chromeStrings: NativeOverviewChromeStrings { .init(locale: locale) }
}

private struct OverviewChromePresentation: ViewModifier {
    let edge: Edge
    let interactive: Bool
    let travel: NativeReadingPageMotion.ParentTravel?
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: travel == nil || reduceMotion)) { _ in
            let position = travel?.visibility(at: CACurrentMediaTime()) ?? (interactive ? 1 : 0)
            let offset = reduceMotion ? 0 : 16 * (position - 1)
            content.geometryGroup()
                .offset(x: edge == .leading ? offset : 0, y: edge == .top ? offset : 0)
                // The reading stack already fades its entire parent during travel.
                .opacity(interactive || travel != nil ? 1 : 0)
        }
        .allowsHitTesting(interactive)
        .accessibilityHidden(!interactive)
        .disabled(!interactive)
    }
}

@MainActor
private struct NativeOverviewWorkspaceCard: View {
    let item: NativeOverviewItem
    let model: NativeOverviewWorkspaceModel
    let callbacks: NativeOverviewWorkspaceCallbackStore
    @State private var lifetime = PluginLifetime()
    @State private var error: String?
    @State private var archivePending = false
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    var body: some View {
        let completedOnly = model.statusFilter == .completed
        Group {
            switch model.snapshot(for: item) {
            case .harness(let snapshot):
                let thread = snapshot.input.thread
                snapshot.card(respond: { try await respond($0, thread: thread) }, openThread: { open(thread.id) })
                    .environment(\.threadCardUnread, thread.bookmarkVersion.map {
                        model.workspace.preferences.threadReadHistory.isUnread(.init(threadID: thread.id, typeID: "agent"), version: $0)
                    } ?? false)
                    .environment(\.threadCardArchiveAction, archiveAction(for: thread))
                    .environment(\.threadCardArchivePending, archivePending)
                    .environment(\.nativeThreadIdentityKey, thread.id.string)
                    .environment(\.threadCardLogo, { @MainActor in
                        (try? model.workspace.harnessHost.registry.require(thread.harnessID))?.logo(size: 12) ?? AnyView(EmptyView())
                    })
                    // Keep one opening action per card while preserving its
                    // readable children and independently actionable controls.
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(thread.title.string)
                    .contentShape(RoundedRectangle(cornerRadius: 22))
                    .onTapGesture { open(thread.id) }
                    .focusable()
                    .focused($focused)
                    .focusEffectDisabled()
                    .onKeyPress(.return) { open(thread.id); return .handled }
                    .onKeyPress(keys: [.leftArrow, .rightArrow], action: model.canvasState.scrollWithArrow)
                    .accessibilityAction(named: Text(model.workspace.locale.text("打开会话", "Open conversation"))) { open(thread.id) }
            case .application(let plugin, let snapshot):
                applicationCard(plugin: plugin, snapshot: snapshot)
            case .collection(let plugin, let members):
                collectionCard(plugin: plugin, members: members)
            case nil:
                // Removed entities retain an inert geometric slot until the queued
                // exit/reflow commits. They never acquire fresh execution authority.
                Color.clear.allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay {
            if completedOnly && focused {
                RoundedRectangle(cornerRadius: NativeGeometry.overviewCardRadius)
                    .strokeBorder(NativePalette.overview.accent.swiftUI, lineWidth: 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background {
            if let request = model.readingSource, model.visibleCardID(for: request.member) == item.id,
               model.sourceCardID(for: request.member) == nil {
                NativeReadingEntranceStage(enabled: true, onReady: request.onReady).id(request.id)
            }
        }
        .environment(\.locale, locale)
        .overlay(alignment: .bottomLeading) {
            if let error { Text(error).font(NativeTypography.inter(size: 10)).foregroundStyle(NativePalette.overview.danger.swiftUI).padding(12) }
        }
        .onAppear { if lifetime.isCancelled { lifetime = PluginLifetime() } }
        .onDisappear { lifetime.cancel() }
    }
    private func open(_ id: JSONText) {
        guard !archivePending, model.canvasState.allowsActivation(cardID: item.id) else { return }
        callbacks.current.openThread(id, nil)
        Task { await model.recordUserAction(kind: "open-thread", thread: .init(threadID: id, typeID: JSONText("agent"))) }
    }
    private func archiveAction(for thread: HarnessThread) -> (@MainActor () -> Void)? {
        guard canArchive(thread) else { return nil }
        return { Task { await archive(thread.id) } }
    }
    private func canArchive(_ thread: HarnessThread) -> Bool {
        guard thread.isOrdinaryAgent, thread.archived != true,
              !thread.pendingInput, thread.observation.backgroundWork == nil,
              let execution = thread.observation.latestExecution else { return false }
        return execution.status == .interrupted && thread.userInterruptedExecutionID == execution.executionID
    }
    private func archive(_ id: JSONText) async {
        guard !archivePending, model.canvasState.allowsActivation(cardID: item.id),
              let current = model.workspace.catalog.thread(id), canArchive(current) else { return }
        archivePending = true
        error = nil
        model.canvasState.beginInteraction(cardID: item.id)
        defer {
            archivePending = false
            model.canvasState.endInteraction(cardID: item.id)
        }
        do {
            try lifetime.checkCancellation()
            _ = try await model.workspace.client.invoke("thread:set-archived", args: [.string(id), .bool(true)])
        } catch {
            if !lifetime.isCancelled { self.error = error.localizedDescription }
        }
    }
    private func respond(_ request: HarnessRespondRequest, thread: HarnessThread) async throws {
        model.canvasState.beginInteraction(cardID: item.id)
        defer { model.canvasState.endInteraction(cardID: item.id) }
        try await model.workspace.harnessHost.actions(for: thread).respond(request)
    }
    private func collectionCard(plugin: AnyApplicationThreadPlugin, members: [ApplicationOverviewSnapshot]) -> AnyView {
        do {
            let props = try members.map { snapshot in
                ApplicationThreadProps(entry: snapshot.entry,
                    context: try model.applicationFactories.rendererContext(plugin, snapshot.entry, lifetime))
            }
            return AnyView(try plugin.collectionCard(props: props, initialSelection: model.selectedCollectionMember(for: item),
                active: model.presentationActive && model.facts.overviewVisible && model.facts.focused
                    && model.facts.documentVisible && !model.facts.settingsOpen,
                onSelection: { model.selectCollectionMember($0, cardID: item.id) }, openThread: { reference in
                    guard plugin.hasDetail, model.canvasState.allowsActivation(cardID: item.id),
                          members.contains(where: { $0.entry.ref == reference }) else { return }
                    callbacks.current.openApplication(reference, nil)
                }).environment(\.collectionReturnMember, model.returnMember)
                .environment(\.collectionReadingSource,
                    model.readingSource.flatMap { model.sourceCardID(for: $0.member) == item.id ? $0 : nil }))
        } catch {
            return AnyView(Text(error.localizedDescription).font(NativeTypography.inter(size: 11))
                .foregroundStyle(NativePalette.overview.danger.swiftUI).padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(NativePalette.overview.surface.swiftUI))
        }
    }

    private func applicationCard(plugin: AnyApplicationThreadPlugin, snapshot: ApplicationOverviewSnapshot) -> AnyView {
        do {
            let provided = try model.applicationFactories.rendererContext(plugin, snapshot.entry, lifetime)
            let context = ApplicationRendererContext(theme: provided.theme, locale: provided.locale, lifetime: provided.lifetime,
                domain: provided.domain, capabilities: provided.capabilities, openThread: { reference, target in
                    guard model.canvasState.allowsActivation(cardID: item.id) else { return }
                    provided.openThread(reference, target)
                }, openExecution: { reference in
                    guard model.canvasState.allowsActivation(cardID: item.id) else { return }
                    provided.openExecution(reference)
                })
            return try AnyView(snapshot.card(context: context, openThread: {
                guard plugin.hasDetail, model.canvasState.allowsActivation(cardID: item.id) else { return }
                callbacks.current.openApplication(snapshot.entry.ref, nil)
                Task { await model.recordUserAction(kind: "open-thread", thread: snapshot.entry.ref) }
            }).environment(\.threadCardCloudAnimationsEnabled,
                model.presentationActive && model.facts.focused && model.facts.overviewVisible
                    && model.facts.documentVisible && !model.facts.settingsOpen))
        } catch {
            return AnyView(VStack(alignment: .leading, spacing: 8) {
                Text(snapshot.entry.title.string).font(NativeTypography.inter(size: 15, weight: 620))
                Text(error.localizedDescription).font(NativeTypography.inter(size: 11)).foregroundStyle(NativePalette.overview.danger.swiftUI)
            }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        }
    }
}


public extension View {
    func nativeOverviewActivity(visible: Bool) -> some View {
        coordinateSpace(name: OverviewTagActivityIndicator.Space.workspace)
            .environment(\.overviewTagActivityVisible, visible)
    }
}
