import Observation
import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI

/// The window owns routes and drafts; plugins own the contents of their pages.
@MainActor @Observable
public final class NativeWorkspacePresentation {
    public let workspace: NativeWorkspaceModel
    public let settingsNavigation = NativeSettingsNavigation()
    public let canvas = NativeOverviewCanvasState()
    @ObservationIgnored lazy var collectionPanel = NativeCollectionPanelPresentation { [weak self] in
        self?.overview.releaseCollectionRanks()
        self?.overview.applyDeferredFirstTag()
    }
    var readingCollectionMember: Bool { collectionPanel.readingMember != nil }
    var browsingCollection: Bool { collectionPanel.owner != nil && selected == nil }
    var openingCollectionMember: Bool { readingCollectionMember && !readingEntranceAdmitted }
    public let messageMotion = NativeReadingPageMotion()
    let localSteers = ThreadLocalSteers()
    public let threadIdentityRegistry = NativeThreadIdentityRegistry()
    public private(set) var threadIdentityVisit: NativeThreadIdentityVisit?
    public let readingNavigation = NativeReadingNavigationState()
    public let readingInteractions = NativeReadingInteractions()
    public private(set) var reportSidecards = NativeReportSidecardPresentation()
    public let draft: NativeComposerDraft
    public private(set) var dockDraft: NativeComposerDraft
    public private(set) var dockThreadID: JSONText?
    public private(set) var dockThread: HarnessThread?
    public private(set) var reportExecution: ApplicationExecutionRef?
    public private(set) var agentInputTarget: ThreadConversationInputTarget?
    @ObservationIgnored private var agentInputOwner: UUID?
    @ObservationIgnored private var visibleReportDocument: NativeApplicationHTMLReadiness?
    private var reportInputReady = false
    @ObservationIgnored private var executionDrafts: [ApplicationExecutionRef: NativeComposerDraft] = [:]
    private let executionContinuation: NativeExecutionContinuation
    private let mokuSubmission: NativeMokuSubmission
    @ObservationIgnored private var reportInputBack: (() -> Void)?
    private struct ExecutionSendNavigation {
        let request: UUID
        let route: UUID
        let generation: UUID
        let reference: ApplicationExecutionRef
        let destination: ApplicationExecutionRef
        let reportSelection: UUID?
        let text: String
    }
    private var executionSendNavigation: ExecutionSendNavigation? {
        didSet {
            if let oldValue { reportSidecards.endConnection(request: oldValue.request) }
        }
    }
    fileprivate var retainsReportComposer: Bool {
        guard let source = reportSidecards.connection?.source else { return false }
        return selected?.typeID == "report.document" && reportExecution == source && !scene.dockCovered
    }
    var awaitingExecutionContinuation: Bool {
        if retainsReportComposer { return true }
        guard let pending = executionSendNavigation else { return false }
        return pending.route == navigationRouteID && pending.generation == scene.composerGeneration
            && pending.reference == dockExecution && !scene.dockCovered
    }
    public private(set) var sidecardComposer: SidecardComposerRequest?
    @ObservationIgnored private var sidecardDraft: NativeComposerDraft?
    @ObservationIgnored private var sidecardComposerThread: JSONText?
    public private(set) var threadExecutionReveal: SidecardExecutionReveal?
    public private(set) var readingEntranceAdmitted = false
    @ObservationIgnored private var threadDrafts: [JSONText: NativeComposerDraft] = [:]
    @ObservationIgnored private var superThreadDrafts: [JSONText: NativeComposerDraft] = [:]
    public private(set) var selected: ApplicationThreadRef?
    public fileprivate(set) var mountedReadingThread: ApplicationThreadRef?
    public private(set) var readingTarget: HarnessReadingTarget?
    public private(set) var readingPanelSource: CGRect?
    private var readingPanelSourceCardID: String?
    public var usesReadingPanel: Bool {
        guard let type = selected?.typeID else { return false }
        return type == "agent" || type == "report.document"
    }
    public var navigation: ThreadDetailBackAction?
    @ObservationIgnored var navigationRouteID = UUID()
    public var nativeApplicationNavigation = false
    public private(set) var followUpVisible = false
    @ObservationIgnored private var applicationReturn: (thread: ApplicationThreadRef, target: HarnessReadingTarget?)?
    @ObservationIgnored public lazy var scene = makeScene()
    @ObservationIgnored lazy var onboarding = NativeOnboardingState(workspace: workspace)
    @ObservationIgnored public lazy var applicationHost = NativeApplicationHost(workspace: workspace,
        navigationCallbacks: NativeApplicationNavigationCallbacks(
            openThread: { [weak self] thread, target in self?.open(thread, target: target) },
            openExecution: { [weak self] in self?.openExecution($0) },
            followUp: { [weak self] id, draft in self?.openFollowUp(id, draft: draft) },
            openExternal: { [weak self] url in
                guard let self else { throw CancellationError() }
                try await self.workspace.services.openExternal(JSONText(url.absoluteString))
            }))
    @ObservationIgnored public lazy var overview = NativeOverviewWorkspaceModel(workspace: workspace,
        applications: applicationHost.overviewFactories, canvasState: canvas)
    @ObservationIgnored public lazy var moku = NativeMokuWorkspacePresentation(workspace: workspace, overview: overview)
    private var focused = false
    private var documentVisible = true
    private(set) var readingWindowActive = false

    fileprivate func setReadingWindowActive(_ active: Bool) {
        readingWindowActive = active
        publishPresence()
    }
    @ObservationIgnored private var started = false
    public var interactionReady: Bool { started && !workspace.stopping && !workspace.waitingForInitialCatalog }
    @ObservationIgnored private var restored = false
    @ObservationIgnored private var snapshotAuthority: UUID?
    @ObservationIgnored private var releaseTask: Task<Void, Never>?

    public init(workspace: NativeWorkspaceModel) {
        self.workspace = workspace
        executionContinuation = NativeExecutionContinuation(workspace: workspace)
        mokuSubmission = NativeMokuSubmission(workspace: workspace)
        draft = NativeComposerDraft(services: workspace.services.composer(receipts: mokuSubmission.receipts),
            persistence: NativeComposerDraftPersistence(storageDirectory: workspace.client.storageDirectory, scope: "moku"))
        dockDraft = draft
        // Reload retains the current catalog. Restore the route before the
        // first hosting-view layout so it cannot briefly build an overview
        // underneath a conversation that was already selected.
        restoreSavedSelection()
    }

    private func makeScene() -> NativeMokuSceneState {
        let state = NativeMokuSceneState(replyReadFileURL: workspace.client.storageDirectory.appendingPathComponent("native-moku-reply-read.json"),
            readingPanelMotion: messageMotion)
        state.executionDockPlacement.beginRoute(navigationRouteID)
        // Route is restored before the first layout. Do not wait for start()
        // or a saved thread briefly mounts the Overview capsule.
        state.readingPanelVisible = usesReadingPanel
        state.overviewVisible = selected == nil
        configureDockInput(in: state)
        state.onSettingsOpenChange = { [weak self] value in
            self?.workspace.settingsOpen = value
            self?.publishPresence()
        }
        state.onFlightActiveChange = { [weak self] value in self?.workspace.settingsModel.mokuInFlight = value }
        return state
    }

    public func start() {
        guard !started else { return }
        started = true
        _ = overview; _ = moku; _ = scene
        onboarding.admitIfNeeded()
        applicationHost.git.start { [weak self] in self?.overview.refreshCardExtensions() }
        workspace.onCatalogChange = { [weak self] event in
            guard let self else { return }
            self.localSteers.retainRunning { reference in
                guard let observation = self.workspace.catalog.thread(reference.thread.threadID)?.observation else { return false }
                return observation.isExecutionActive && observation.latestExecution?.id == reference.executionID
            }
            // An expanded collection still owns its source card in the canvas.
            self.overview.receive(event, deferFirstTag: self.collectionPanel.owner != nil)
            self.moku.receive(event)
            if case .snapshot(_, let authority) = event, self.snapshotAuthority != authority {
                self.snapshotAuthority = authority
                // Rehydration interrupts rendering, not an accepted Close.
                self.scene.settle(); NativeReadingPageMotion.cancelAll(finishingClose: true)
            }
            self.reconcileSelection()
            self.onboarding.admitIfNeeded()
            self.publishPresence()
        }
        workspace.onOverviewFilter = { [weak self] request in self?.overview.receiveFilter(request) }
        workspace.onFollowUp = { [weak self] id, draft in self?.openFollowUp(id, draft: draft) }
        workspace.onStopped = { [weak self] in await self?.release(runtimeStopped: true) }
        workspace.onConnectionChange = { [weak self] status in
            guard let self else { return }
            self.overview.receive(.connection(status)); self.moku.receive(.connection(status))
            if status != .connected {
                self.scene.settle(); NativeReadingPageMotion.cancelAll(finishingClose: true)
            }
            self.publishPresence()
        }
        if let state = workspace.state, let authority = workspace.snapshotAuthority {
            snapshotAuthority = authority
            overview.receive(.snapshot(state, authority: authority)); moku.refresh(); reconcileSelection()
        }
        publishPresence()
    }

    public func setScenePhase(_ phase: ScenePhase) {
        focused = phase == .active; documentVisible = phase != .background
        scene.setWindowVisible(documentVisible)
        publishPresence()
    }

    private func restoreSavedSelection() {
        // Connection/hydration events can precede the first catalog. Preserve
        // the one-time saved selection until there is authoritative state.
        guard workspace.state != nil else { return }
        if !restored {
            restored = true
            if let id = workspace.preferences.selectedThreadID {
                let key = JSONText(id)
                guard workspace.catalog.thread(key)?.canOpenReader(at: nil) == true else {
                    persistSelection(nil)
                    return
                }
                selected = ApplicationThreadRef(threadID: key, typeID: "agent")
                readingPanelSourceCardID = key.string
            }
        }
    }

    func reconcileSelection() {
        guard workspace.state != nil else { return }
        restoreSavedSelection()
        if let previous = applicationReturn {
            let thread = workspace.catalog.thread(previous.thread.threadID)
            if thread == nil || thread?.isHiddenFromUser == true { applicationReturn = nil }
        }
        if let selected {
            let visible = selected.typeID == "agent" ? workspace.catalog.thread(selected.threadID)?.canOpenReader(at: readingTarget) == true
                : (try? applicationHost.entry(selected)) != nil
            if !visible {
                if selected.typeID == "agent" { NativeReadingPageMotion.cancelAll(); finishBack() }
                else { closeApplication() }
            }
        }
    }

    public func open(_ ref: ApplicationThreadRef, target: HarnessReadingTarget? = nil, sourceCardID: String? = nil) {
        guard !onboarding.blocksWorkspace, !scene.settingsOpen else { return }
        if ref.typeID == "agent" {
            guard workspace.catalog.thread(ref.threadID)?.canOpenReader(at: target) == true else { return }
        } else if !applicationHost.canOpen(ref.typeID) { return }
        sidecardComposer?.cancel()
        threadExecutionReveal = nil
        NativeReadingPageMotion.cancelAll(); scene.settle(); scene.setInputOpen(false)
        if selected != ref {
            if ref.typeID != "agent", let selected, selected.typeID == "agent" {
                applicationReturn = (selected, readingTarget)
            } else if ref.typeID == "agent" { applicationReturn = nil }
            followUpVisible = false; resetNavigation(); nativeApplicationNavigation = false
        }
        if selected != ref {
            if selected == nil { collectionPanel.acceptOpening(ref) }
            if collectionPanel.owner != nil && collectionPanel.readingMember != ref { collectionPanel.retire() }
            if readingCollectionMember { overview.holdCollectionRank(for: ref) }
            readingPanelSourceCardID = selected == nil ? sourceCardID ?? overview.sourceCardID(for: ref) ?? ref.threadID.string : nil
            readingPanelSource = readingCollectionMember ? collectionPanel.memberFrame : readingPanelSourceCardID.flatMap { canvas.visibleFrame(for: $0) }
            threadIdentityVisit = ref.typeID == "agent" && (target == nil || sourceCardID != nil)
                ? readingPanelSourceCardID.flatMap { threadIdentityRegistry.capture($0) } : nil
        }
        selected = ref; readingTarget = target
        if ref.typeID == "agent" { persistSelection(ref.threadID) }
        publishPresence()
        if ref.typeID == "agent" { scene.setInputOpen(true) }
        Task { await overview.recordUserAction(kind: "open-thread", thread: ref) }
    }

    public func openExecution(_ reference: ApplicationExecutionRef) {
        let current = reference.thread.typeID == "agent"
            ? workspace.catalog.thread(reference.thread.threadID)?.observation.latestExecution?.executionID : nil
        open(reference.thread, target: HarnessReadingTarget(executionID: reference.executionID,
            requestID: JSONText(UUID().uuidString), mode: current == reference.executionID ? .current : .history))
    }

    public func openTalkExecution(_ reference: ApplicationExecutionRef) {
        guard selected == nil, scene.overviewVisible, !scene.dockCovered, !browsingCollection,
              !onboarding.blocksWorkspace, !scene.dockInteractionVisible else { return }
        // The public catalog excludes private background agents. Failed and
        // interrupted ordinary threads remain valid explicit reading targets.
        guard reference.thread.typeID == "agent",
              let thread = workspace.catalog.thread(reference.thread.threadID),
              thread.isOrdinaryAgent else {
            workspace.report(PluginContractError(NativePluginLocalization.localize("链接指向的执行不可用。", locale: Locale(identifier: workspace.locale.rawValue))))
            return
        }
        scene.setInputOpen(false)
        scene.dismissTalk()
        scene.talkReadingOrigin = .init(reference: reference, space: overview.sceneKey)
    }

    fileprivate struct TalkSourcePreparation: Equatable {
        let visit: UUID
        let destination: ApplicationThreadRef
        let space: String
        let card: String?
        let layoutRevision: UInt64
    }

    fileprivate var talkSourcePreparation: TalkSourcePreparation? {
        guard let origin = scene.talkReadingOrigin, origin.phase == .locating, selected == nil,
              focused, documentVisible else { return nil }
        // Membership and ownership indexes update at the catalog boundary.
        // Restart only if this destination or its actual card changes.
        _ = workspace.catalog.revision
        let thread = origin.reference.thread
        let destination = overview.collectionReadingOwner(of: thread).flatMap { $0.typeID == "report.document" ? $0 : nil } ?? thread
        return .init(visit: origin.id, destination: destination, space: overview.sceneKey,
            card: overview.visibleCardID(for: destination), layoutRevision: overview.content.structureRevision)
    }

    fileprivate func prepareTalkSource(_ request: TalkSourcePreparation?) async {
        guard !Task.isCancelled, request == talkSourcePreparation else { return }
        overview.readingSource = nil
        guard let request else { return }
        guard request.space == scene.talkReadingOrigin?.space else { scene.cancelPendingTalkReading(); return }
        overview.revealExecutionDestination(request.destination)
        if request.space != overview.sceneKey {
            // The locating task for the new space must wait for its own canvas layout.
            scene.talkReadingOrigin?.space = overview.sceneKey
            return
        }
        if overview.error == nil {
            await canvas.prepareForPresentation()
            guard !Task.isCancelled, request == talkSourcePreparation else { return }
            if let card = request.card, canvas.layoutError == nil,
               canvas.visibleFrame(for: card) != nil {
                overview.readingSource = .init(member: request.destination) { [weak self] in
                    guard let self, request == talkSourcePreparation else { return }
                    finishTalkOpening(request, sourceCardID: card)
                }
                return
            }
        }
        // Explicit links also admit archived or failed Threads with no canvas card.
        finishTalkOpening(request, sourceCardID: nil)
    }

    private func finishTalkOpening(_ request: TalkSourcePreparation, sourceCardID: String?) {
        guard request == talkSourcePreparation, var origin = scene.talkReadingOrigin else { return }
        overview.readingSource = nil
        guard !scene.dockCovered, !scene.inputOpen, !browsingCollection, !onboarding.blocksWorkspace,
              let thread = workspace.catalog.thread(origin.reference.thread.threadID),
              thread.isOrdinaryAgent else {
            scene.cancelPendingTalkReading()
            return
        }
        let reference = origin.reference
        if request.destination == reference.thread {
            open(reference.thread, target: HarnessReadingTarget(executionID: reference.executionID,
                requestID: JSONText(origin.id.uuidString), mode: .history, position: .executionStart), sourceCardID: sourceCardID)
        } else {
            open(request.destination, sourceCardID: sourceCardID)
            reportSidecards.selectExecution(reference, position: .executionStart)
        }
        guard selected == request.destination else { scene.cancelPendingTalkReading(); return }
        origin.phase = .reading
        scene.talkReadingOrigin = origin
        if sourceCardID == nil { readingPanelSource = nil; readingPanelSourceCardID = nil }
    }

    public func openFollowUp(_ id: JSONText, draft: JSONText) {
        guard !onboarding.blocksWorkspace else { return }
        guard let thread = workspace.catalog.thread(id), !thread.isHiddenFromUser else { return }
        if selected?.threadID != id || selected?.typeID != "agent" {
            open(ApplicationThreadRef(threadID: id, typeID: "agent"))
        }
        guard dockThreadID == id else { return }
        if !draft.codeUnits.isEmpty {
            // An explicit follow-up suggestion appends to this Thread's draft;
            // it cannot replace unsent text or attachments from the reader.
            dockDraft.text += (dockDraft.text.isEmpty ? "" : "\n\n") + draft.string
        }
        scene.setInputOpen(true)
    }

    func backFromReader() {
        if selected?.typeID == "agent" { showOverview() }
        else { closeApplication() }
    }

    public func showOverview() {
        guard !onboarding.blocksWorkspace else { return }
        scene.cancelPendingTalkReading()
        if scene.settingsOpen {
            guard settingsNavigation.requestClose(model: workspace.settingsModel,
                onClose: { _ in scene.closeSettings() }) else { return }
            return
        }
        if browsingCollection, let owner = collectionPanel.owner {
            collectionPanel.close(owner: owner)
            return
        }
        if readingCollectionMember { collectionPanel.retire() }
        // Reversal keeps the opening's source frozen. A settled return samples
        // its new destination only after the retained canvas has been prepared.
        if selected != nil, !scene.settingsOpen { messageMotion.close() }
        else { finishBack() }
    }

    fileprivate func prepareOverviewReturn() async {
        guard !Task.isCancelled else { return }
        let route = navigationRouteID, target = selected
        func returnCardID() -> String? {
            guard usesReadingPanel, overview.error == nil, readingPanelSourceCardID != nil,
                  let target else { return nil }
            return overview.visibleCardID(for: target)
        }
        // Reactivating Overview has already refreshed membership. A removed
        // card has no frame to prepare, even if the retained canvas still has
        // its old placement or another card now occupies the same position.
        if usesReadingPanel, !readingCollectionMember, returnCardID() == nil {
            readingPanelSource = nil
            return
        }
        if target?.typeID != "agent" { await scene.waitForReturningEyes() }
        guard !Task.isCancelled, navigationRouteID == route, selected == target else { return }
        if readingCollectionMember {
            readingPanelSource = collectionPanel.memberFrame ?? readingPanelSource
            return
        }
        await canvas.prepareForPresentation()
        guard !Task.isCancelled, navigationRouteID == route, selected == target else { return }
        readingPanelSource = canvas.layoutError == nil ? returnCardID().flatMap { canvas.visibleFrame(for: $0) } : nil
    }

    public func finishBack() {
        overview.recordApplicationClose()
        collectionPanel.returnToMembers()
        selected = nil; readingTarget = nil; threadIdentityVisit = nil; resetNavigation(); followUpVisible = false
        nativeApplicationNavigation = false
        applicationReturn = nil
        persistSelection(nil); publishPresence()
    }

    public func closeApplication() {
        guard selected?.typeID != "agent" else { return }
        if applicationReturn == nil, !scene.settingsOpen {
            messageMotion.close()
            return
        }
        NativeReadingPageMotion.cancelAll()
        selected = applicationReturn?.thread; readingTarget = applicationReturn?.target
        applicationReturn = nil; resetNavigation(); nativeApplicationNavigation = false
        followUpVisible = false
        publishPresence()
    }

    private func persistSelection(_ id: JSONText?) {
        do {
            if let id, JSONText(id.string) != id { throw PluginContractError("Thread identity cannot be stored as a native preference") }
            try workspace.preferences.selectThread(id?.string)
        } catch { workspace.report(error) }
    }

    private func resetNavigation() {
        scene.talkReadingOrigin = nil
        clearSidecardComposer()
        visibleReportDocument = nil
        reportSidecards = NativeReportSidecardPresentation()
        reportExecution = nil; reportInputReady = false; reportInputBack = nil; executionSendNavigation = nil
        agentInputTarget = nil; agentInputOwner = nil
        readingEntranceAdmitted = false
        threadExecutionReveal = nil
        navigation = nil
        mountedReadingThread = nil
        navigationRouteID = UUID()
        scene.executionDockPlacement.beginRoute(navigationRouteID)
    }

    public var canOpenSettings: Bool {
        workspace.hasInitialContent && !workspace.stopping
            && !onboarding.blocksWorkspace
            && selected == nil && scene.canOpenSettings && !messageMotion.active
    }
    public func openSettings() {
        guard canOpenSettings else { workspace.settingsOpen = scene.settingsOpen; return }
        if !scene.settingsOpen || scene.settingsClosing {
            workspace.settingsModel.draft.beginPageEditing()
            settingsNavigation.visit = UUID()
            settingsNavigation.section = NativeSettingsNavigation.defaultSection
        }
        NativeReadingPageMotion.cancelAll(); scene.openSettings()
    }

    public func setFollowUpVisible(_ value: Bool) { followUpVisible = value; publishPresence() }

    var readingForeground: Bool {
        focused && documentVisible && readingWindowActive && workspace.connection == .connected
            && readingEntranceAdmitted && !scene.settingsOpen
    }

    public func publishPresence() {
        guard started else { return }
        // Keep Dock eligibility continuous while moving between its two routes.
        if selected == nil { scene.overviewVisible = true; scene.readingPanelVisible = false }
        else { scene.readingPanelVisible = usesReadingPanel; scene.overviewVisible = false }
        scene.disabled = workspace.stopping || workspace.catalog.moku == nil
            || (onboarding.blocksWorkspace && onboarding.step != .landing)
        configureDockInput(in: scene)
        finishExecutionSendNavigation()
        overview.setPresentation(NativeOverviewPresentationFacts(
            overviewVisible: selected == nil,
            settingsOpen: scene.settingsOpen,
            selectedThread: selected,
            followUpThread: followUpVisible ? selected : nil,
            focused: focused, documentVisible: documentVisible,
            available: workspace.runtimeAvailable))
        // Hide Overview before writing the open marker to retain its backdrop.
        // Catalog changes also reconcile association ownership while reading.
        overview.recordReadingRoute(selected)
        overview.updateApplicationReading(visible: readingForeground)
        recordVisibleBookmarks()
    }

    fileprivate func updateReportDocument(_ document: NativeApplicationHTMLReadiness?, route: UUID) {
        guard navigationRouteID == route else { return }
        visibleReportDocument = document
        recordVisibleBookmarks()
    }

    fileprivate func recordVisibleBookmarks() {
        guard started, !workspace.stopping, readingForeground, !messageMotion.active,
              !onboarding.blocksWorkspace, let selected else { return }
        do {
            if selected.typeID == "report.document", let document = visibleReportDocument,
               document.ready, document.thread == selected {
                try overview.markRead(selected, version: document.source.contentRevision)
            }
            let shown: ApplicationExecutionRef?
            if selected.typeID == "agent", let target = agentInputTarget, target.ready,
               target.threadID == selected.threadID, target.requestID == readingTarget?.requestID,
               let id = target.displayedExecutionID {
                shown = .init(thread: selected, executionID: id)
            } else if selected.typeID == "report.document", let reportExecution, dockInputAvailable,
                      reportSidecards.displayedExecutionID == reportExecution.executionID {
                shown = reportExecution
            } else { shown = nil }
            if let shown, workspace.catalog.thread(shown.thread.threadID)?.bookmarkVersion == shown.executionID {
                try overview.markRead(shown.thread, version: shown.executionID)
            }
        } catch { workspace.report(error) }
    }

    var mokuSubmissionSource: JSONValue {
        var source: [JSONText: JSONValue] = [:]
        if let id = mokuSuperThreadID { source["superThreadId"] = .string(id) }
        if selected == nil, !scene.settingsOpen,
           let filter = overview.selectedFilter, filter.isDirectory {
            source["directoryScopeId"] = .text(filter.scope)
        }
        return .object(source)
    }

    public func sendMoku(_ submission: NativeComposerSubmission, source: JSONValue = .object([:])) async throws {
        guard !onboarding.blocksWorkspace else { throw PluginContractError("Complete onboarding before sending a task.") }
        guard !reportExecutionSelected, source == mokuSubmissionSource,
              var request = source.objectValue else { throw CancellationError() }
        let input = submission.input(knownDirectoryReferencesAsText: true)
        request["input"] = input
        workspace.dismissOperationError()
        try await moku.showConversationSend(submission, input: input) {
            try await mokuSubmission.send(input: input, source: source, commandID: submission.commandID) {
                await overview.recordUserAction(kind: "moku-input", text: JSONText(submission.text))
                return .object(request)
            }
        }
    }

    private func captureSteer(_ submission: NativeComposerSubmission, thread: HarnessThread?,
                              from executionID: JSONText? = nil) -> ApplicationExecutionRef? {
        guard workspace.supportsFollowUpRowIdentity, let thread, let run = thread.observation.latestExecution,
              run.status == .running, executionID == nil || executionID == run.executionID else { return nil }
        let target = ApplicationExecutionRef(thread: .init(threadID: thread.id, typeID: "agent"), executionID: run.executionID)
        localSteers.capture(submission, in: target)
        return target
    }

    /// A selected execution keeps the existing direct Agent route. The report
    /// document/list uses Moku, with a captured document identity on every send.
    public var mokuSuperThreadID: JSONText? {
        guard selected?.typeID == "report.document", reportExecution == nil, !reportExecutionSelected,
              !scene.settingsOpen else { return nil }
        return selected?.threadID
    }

    private var reportExecutionSelected: Bool {
        selected?.typeID == "report.document" && reportSidecards.selectedExecution != nil
            && (reportSidecards.active == .relatedExecutions || reportSidecards.pending == .relatedExecutions)
    }

    public var dockExecution: ApplicationExecutionRef? {
        if selected?.typeID == "report.document" { return reportExecution }
        guard let selected, selected.typeID == "agent" else { return nil }
        let executionID: JSONText?
        if let target = agentInputTarget, target.requestID == readingTarget?.requestID {
            executionID = target.followsLatest ? nil : target.executionID
        }
        else { executionID = readingTarget?.executionID }
        return executionID.map { ApplicationExecutionRef(thread: selected, executionID: $0) }
    }

    var dockInputAvailable: Bool {
        if sidecardComposer != nil { return true }
        if selected?.typeID == "agent" {
            guard let target = agentInputTarget, target.requestID == readingTarget?.requestID else { return false }
            return target.ready && (target.followsLatest || target.executionID != nil)
        }
        guard let reportExecution else { return true }
        return reportSidecards.connection == nil && reportInputReady && reportSidecards.executionReady && reportSidecards.inputReady
            && reportSidecards.active == .relatedExecutions
            && reportSidecards.inputExecution == reportExecution && !reportSidecards.retainingForReturn
    }

    func updateAgentInput(owner: UUID, target: ThreadConversationInputTarget?, route: UUID) {
        guard navigationRouteID == route, selected?.typeID == "agent" else { return }
        if let target {
            guard target.threadID == selected?.threadID, target.requestID == readingTarget?.requestID else { return }
        } else if agentInputOwner != owner { return }
        agentInputOwner = target == nil ? nil : owner
        guard agentInputTarget != target else { return }
        agentInputTarget = target
        recordVisibleBookmarks()
        // TOC navigation changes the draft without taking keyboard focus from
        // the history rail or the document the user just selected.
        configureDockInput(in: scene, autofocus: !readingEntranceAdmitted,
            retainingOpenInput: readingEntranceAdmitted && target != nil)
    }

    func updateReportExecution(_ reference: ApplicationExecutionRef?, ready: Bool, onBack: (() -> Void)?, route: UUID) {
        guard navigationRouteID == route, selected?.typeID == "report.document" else { return }
        reportInputBack = onBack
        if reportExecution == reference, reportInputReady == ready { return }
        let switchingExecution = reportExecution != nil && reference != nil && (reportExecution?.thread == reference?.thread || (reportInputReady && ready))
        reportExecution = reference; reportInputReady = ready
        recordVisibleBookmarks()
        configureDockInput(in: scene, autofocus: !switchingExecution, retainingOpenInput: switchingExecution)
        if reference != nil, ready { scene.setInputOpen(true) }
    }

    func closeReportExecutionInput() { reportInputBack?() }

    func closeSuperThreadInput() {
        if let reportInputBack { reportInputBack() }
        else { showOverview() }
    }

    private func finishExecutionSendNavigation() {
        guard let pending = executionSendNavigation else { return }
        guard navigationRouteID == pending.route, dockExecution == pending.reference,
              scene.composerGeneration == pending.generation, !scene.dockCovered else {
            executionSendNavigation = nil; return
        }
        if let selection = pending.reportSelection {
            guard reportSidecards.selectionID == selection,
                  reportSidecards.active == .relatedExecutions,
                  reportSidecards.inputExecution == pending.reference,
                  !reportSidecards.retainingForReturn else { executionSendNavigation = nil; return }
        }
        // The command receipt may precede the public catalog event, especially
        // for a new fork. Wait for that event without delaying draft admission.
        guard let thread = workspace.catalog.thread(pending.destination.thread.threadID) else { return }
        if let selection = pending.reportSelection {
            reportSidecards.continueExecution(pending.destination, from: pending.reference, selection: selection, text: pending.text, request: pending.request)
            executionSendNavigation = nil
            return
        }
        executionSendNavigation = nil
        let previousDockFrame = scene.executionDockPlacement.frame
        // Even a continuation in the same Thread is a new exact-result visit.
        // Its retained predecessor must not publish layout/input for this one.
        if selected == pending.destination.thread { resetNavigation() }
        open(pending.destination.thread, target: HarnessReadingTarget(executionID: pending.destination.executionID,
            requestID: JSONText(UUID().uuidString), mode: thread.observation.latestExecution?.executionID == pending.destination.executionID ? .current : .history,
            position: .result))
        if selected == pending.destination.thread {
            // Receipt admission permits this route handoff, not a speculative
            // central stop while its readers and final column are preparing.
            scene.executionDockPlacement.beginRoute(navigationRouteID, retaining: previousDockFrame,
                threadID: pending.destination.thread.threadID, continuing: true)
        }
    }

    private func clearSidecardComposer() {
        let request = sidecardComposer, oldDraft = sidecardDraft
        sidecardComposer = nil; sidecardDraft = nil; sidecardComposerThread = nil
        request?.cancel()
        if let oldDraft { Task { await oldDraft.dispose() } }
    }

    private func updateSidecardComposer(thread: JSONText, request: SidecardComposerRequest?) {
        guard selected == ApplicationThreadRef(threadID: thread, typeID: "agent") else { return }
        if request == nil && sidecardComposerThread != thread { return }
        if sidecardComposer?.id == request?.id,
           sidecardComposer?.ready == request?.ready,
           sidecardComposer?.placeholder == request?.placeholder { return }
        if sidecardComposer?.id != request?.id {
            clearSidecardComposer()
            if request != nil {
                sidecardDraft = NativeComposerDraft(services: NativeComposerServices(stageFiles: { _, _ in
                    throw PluginContractError("Annotation descriptions accept text only.")
                }, discardAttachments: { _ in }))
            }
        }
        sidecardComposerThread = request == nil ? nil : thread
        sidecardComposer = request
        configureDockInput(in: scene)
    }

    private func configureDockInput(in state: NativeMokuSceneState, autofocus: Bool = true,
                                    retainingOpenInput: Bool = false) {
        let superThread = selected?.typeID == "report.document" && reportExecution == nil
            ? selected?.threadID : nil
        let thread = selected.flatMap { ref -> HarnessThread? in
            let id: JSONText
            if ref.typeID == "agent" { id = ref.threadID }
            else if ref.typeID == "report.document", let reference = reportExecution { id = reference.thread.threadID }
            else { return nil }
            guard let thread = workspace.catalog.thread(id),
                  thread.isOrdinaryAgent else { return nil }
            return thread
        }
        dockThreadID = thread?.id
        // The catalog's indexed lookup intentionally does not publish reads.
        // Retain the selected record as an observed value so a running/stopped
        // execution updates the action seat without another navigation event.
        if dockThread != thread { dockThread = thread }
        if sidecardComposer != nil, sidecardComposerThread != thread?.id { clearSidecardComposer() }
        let normalDraft: NativeComposerDraft
        if let reference = dockExecution, let thread, reference.thread.threadID == thread.id {
            if executionDrafts[reference] == nil {
                // Share the existing exact-execution storage identity so lending
                // a Report draft to Agent history does not discard unsent input.
                let scope = JSONText(codeUnits: JSONText("report-execution:\(thread.id.codeUnits.count):").codeUnits
                    + thread.id.codeUnits + reference.executionID.codeUnits)
                executionDrafts[reference] = NativeComposerDraft(services: workspace.services.composer(receipts: executionContinuation.receipts),
                    persistence: NativeComposerDraftPersistence(storageDirectory: workspace.client.storageDirectory, scope: scope))
            }
            normalDraft = executionDrafts[reference]!
        } else if let thread {
            if threadDrafts[thread.id] == nil {
                let scope = JSONText(codeUnits: Array("thread-detail:".utf16) + thread.id.codeUnits)
                threadDrafts[thread.id] = NativeComposerDraft(services: workspace.services.composer(receipts: executionContinuation.receipts),
                    persistence: NativeComposerDraftPersistence(storageDirectory: workspace.client.storageDirectory, scope: scope))
            }
            normalDraft = threadDrafts[thread.id]!
        } else if let superThread {
            if superThreadDrafts[superThread] == nil {
                superThreadDrafts[superThread] = NativeComposerDraft(services: workspace.services.composer(receipts: mokuSubmission.receipts),
                    persistence: NativeComposerDraftPersistence(storageDirectory: workspace.client.storageDirectory,
                        scope: JSONText("super-thread-moku:\(superThread.string)")))
            }
            normalDraft = superThreadDrafts[superThread]!
        } else { normalDraft = draft }
        dockDraft = sidecardComposer != nil ? sidecardDraft ?? normalDraft : normalDraft
        // A Report lends input only to its selected Thread. Keep the default
        // document/list closed at the shared admission boundary so capsule,
        // keyboard and scripted open requests obey the same route policy.
        let previousGeneration = state.composerGeneration
        state.setComposerContext(dockDraft, opensInput: thread != nil, keepsInputOpen: thread != nil,
            inputAdmissionReady: (selected == nil || readingEntranceAdmitted)
                && (selected?.typeID != "report.document" || (thread != nil && reportInputReady)),
            waitsForHarnessIdentity: thread != nil,
            autofocus: autofocus && selected != nil, retainingOpenInput: retainingOpenInput)
        if previousGeneration != state.composerGeneration || state.dockCovered { threadExecutionReveal = nil }
    }

    fileprivate func admitReadingEntrance(routeID: UUID, reference: ApplicationThreadRef) -> Bool {
        // The native layout commit can arrive after Close, replacement or release.
        // Admission belongs to this visit, never just to a matching Thread ID.
        guard started, !workspace.stopping, navigationRouteID == routeID,
              selected == reference, !messageMotion.active else { return false }
        guard !readingEntranceAdmitted else { return true }
        readingEntranceAdmitted = true
        publishPresence()
        configureDockInput(in: scene)
        if dockThreadID != nil, !scene.dockCovered, !scene.dockInteractionVisible {
            scene.setInputOpen(true)
        }
        return true
    }

    public func sendThread(_ submission: NativeComposerSubmission, to id: JSONText,
                           from executionID: JSONText? = nil, route: UUID? = nil) async throws {
        guard !onboarding.blocksWorkspace else { throw CancellationError() }
        if let route {
            guard navigationRouteID == route, dockThreadID == id,
                  dockExecution?.executionID == executionID, dockInputAvailable else { throw CancellationError() }
        }
        workspace.dismissOperationError()
        let route = route ?? navigationRouteID, generation = scene.composerGeneration, request = UUID()
        let sidecards = reportSidecards
        let reportSelection = selected?.typeID == "report.document" ? sidecards.selectionID : nil
        let thread = workspace.catalog.thread(id)
        let previousExecutionID = thread?.observation.latestExecution?.executionID
        let source = ApplicationThreadRef(threadID: id, typeID: "agent")
        // Steers already have an execution and a local input row. A finished or
        // historical Report selection needs feedback before either receipt or row exists.
        if reportSelection != nil, let executionID, let thread, workspace.canExecute(thread),
           executionID != previousExecutionID || !thread.observation.isExecutionActive,
           let harness = try? workspace.plugins.harnesses.require(thread.harnessID) {
            sidecards.beginConnection(request: request, from: .init(thread: source, executionID: executionID),
                harness: harness.descriptor.displayName.string, text: submission.text)
        }
        defer {
            // A fork receipt may arrive before the destination enters the catalog.
            if executionSendNavigation?.request != request { sidecards.endConnection(request: request) }
        }
        let steer = captureSteer(submission, thread: thread, from: executionID)
        if executionID == nil, selected == source, !scene.dockCovered {
            threadExecutionReveal = SidecardExecutionReveal(id: request, previousExecutionID: previousExecutionID)
        }
        await overview.recordUserAction(kind: "thread-input", thread: source, text: JSONText(submission.text))
        do {
            let accepted = try await executionContinuation.send(threadID: id, executionID: executionID, input: submission.input, commandID: submission.commandID)
            if let steer, steer != accepted { localSteers.remove(submission.commandID, from: steer) }
            // Runtime admission belongs to the submitted draft. Presentation
            // authority belongs only to the still-current reading visit.
            if navigationRouteID == route, scene.composerGeneration == generation,
               threadExecutionReveal?.id == request, !scene.dockCovered {
                threadExecutionReveal = SidecardExecutionReveal(id: request, previousExecutionID: previousExecutionID,
                    receipt: .init(executionID: accepted.executionID))
            }
            if let executionID, (reportSelection != nil || accepted != steer), navigationRouteID == route, scene.composerGeneration == generation {
                let reference = ApplicationExecutionRef(thread: .init(threadID: id, typeID: "agent"), executionID: executionID)
                if dockExecution == reference {
                    executionSendNavigation = .init(request: request, route: route, generation: generation,
                        reference: reference, destination: accepted, reportSelection: reportSelection, text: submission.text)
                    finishExecutionSendNavigation()
                }
            }
        } catch {
            if let steer { localSteers.remove(submission.commandID, from: steer) }
            if threadExecutionReveal?.id == request { threadExecutionReveal = nil }
            throw error
        }
    }

    public func cancelMoku(observed thread: HarnessThread) {
        guard let target = thread.cancellationID else { return }
        perform {
            let result = try await self.workspace.invoke("moku:cancel", args: [.object([
                "threadId": .string(thread.id), "expectedCancellationId": .string(target)
            ])])
            if result["status"]?.stringValue == "stale" { throw PluginContractError("The observed Chief execution has ended or changed; refresh before stopping another execution") }
        }
    }

    fileprivate var overviewSwipeAvailable: Bool {
        started && scene.overviewVisible && !workspace.stopping && !scene.dockCovered
            && !onboarding.blocksWorkspace && scene.windowVisible && scene.inputInteractionReady
            && !scene.conversationOpen && !scene.inputLeaving
            && !scene.dockInteractionVisible && moku.interaction == nil
            && !browsingCollection && !messageMotion.active
    }

    public func perform(_ operation: @escaping () async throws -> Void) {
        workspace.dismissOperationError()
        Task { do { try await operation() } catch { workspace.report(error) } }
    }

    public func sidecardServices() -> NativeSidecardWorkspaceServices {
        let route = navigationRouteID
        return NativeSidecardWorkspaceServices(send: { [weak self] thread, input in
            guard let self else { throw CancellationError() }
            let parts = input["parts"]?.arrayValue ?? []
            let text = parts.compactMap { $0["kind"] == .text("text") ? $0["text"]?.stringValue : nil }.joined(separator: "\n")
            await self.overview.recordUserAction(kind: "thread-input", thread: ApplicationThreadRef(threadID: thread, typeID: "agent"), text: JSONText(text))
            return try await self.workspace.services.followUp(threadID: thread, input: input)
        }, stageAttachments: { [weak self] urls in
            guard let self else { throw CancellationError() }
            return try await self.workspace.services.stage(urls.map(NativeComposerFile.init(url:))).map { SidecardStagedAttachment(id: $0.id) }
        }, discardAttachments: { [weak self] ids in
            guard let self else { throw CancellationError() }; try await self.workspace.services.discard(ids)
        }, openExternal: { [weak self] url in
            guard let self else { throw CancellationError() }; try await self.workspace.services.openExternal(url)
        }, attachmentImport: SidecardAttachmentImport(stage: { [weak self] sources, lifetime in
            guard let self else { throw CancellationError() }
            let files = sources.map { source -> NativeComposerFile in
                switch source {
                case .file(let url): return NativeComposerFile(url: url)
                case .bytes(let bytes, let name, let mime): return NativeComposerFile(data: bytes, name: name, mimeType: mime)
                }
            }
            return try await self.workspace.services.composer().stageFiles(files, lifetime).map {
                SidecardImportedAttachment(id: $0.id, path: $0.path, name: $0.name, mimeType: $0.mimeType,
                    size: $0.size, kind: SidecardImportedAttachment.Kind(rawValue: $0.kind.rawValue)!)
            }
        }, policy: { [weak self] lifetime in
            guard let self else { throw CancellationError() }
            return try await self.workspace.services.composer().attachmentPolicy!(lifetime)
        }), compose: { [weak self] id, draft in self?.openFollowUp(id, draft: draft) },
        composer: { [weak self] thread, request in
            guard let self, navigationRouteID == route else { return }
            updateSidecardComposer(thread: thread, request: request)
        })
    }

    public func release(runtimeStopped: Bool = false) async {
        if let releaseTask { await releaseTask.value; return }
        guard started else { return }
        overview.recordApplicationClose()
        started = false
        clearSidecardComposer()
        workspace.onCatalogChange = nil; workspace.onConnectionChange = nil
        workspace.onOverviewFilter = nil; workspace.onFollowUp = nil; workspace.onStopped = nil
        scene.settle(); applicationHost.release()
        let task = Task {
            await overview.stop(); await draft.dispose(discardRemoteAttachments: !runtimeStopped)
            for draft in threadDrafts.values { await draft.dispose(discardRemoteAttachments: !runtimeStopped) }
            for draft in superThreadDrafts.values { await draft.dispose(discardRemoteAttachments: !runtimeStopped) }
            for draft in executionDrafts.values { await draft.dispose(discardRemoteAttachments: !runtimeStopped) }
        }
        releaseTask = task
        await task.value
    }
}

@MainActor
public struct NativeWorkspaceView: View {
    public let model: NativeWorkspaceModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var presentation: NativeWorkspacePresentation
    @State private var canvasInputRegions = NativeCanvasInputRegions()
    public init(model: NativeWorkspaceModel, presentation: NativeWorkspacePresentation? = nil) {
        self.model = model; _presentation = State(initialValue: presentation ?? NativeWorkspacePresentation(workspace: model))
    }
    private var disabled: Bool { !model.runtimeAvailable }
    private var applicationSuppressed: Bool {
        presentation.scene.settingsOpen
            // Report selection revokes Moku send context before the execution
            // preference lends its Agent composer. The resident input stays
            // non-covering throughout that handoff, including unavailable links.
            || (presentation.scene.inputOpen && presentation.dockThreadID == nil && presentation.selected?.typeID != "report.document")
            || presentation.moku.interaction != nil
    }

    public var body: some View {
        NativeOperationNotice(error: model.localizedOperationError,
            suppressed: presentation.scene.settingsOpen,
            onScroll: { presentation.scene.setShellScrollOffset($0) },
            onDismiss: { model.dismissOperationError() }) {
            workspaceScene
        }
        .environment(\.threadLocalSteers, presentation.localSteers)
        .environment(\.locale, Locale(identifier: model.locale.rawValue))
        .environment(\.nativeOfflineDraftEditing, model.hasInitialContent && !model.runtimeAvailable && !model.stopping)
        .environment(\.nativeCanvasInputRegions, canvasInputRegions)
        .coordinateSpace(name: "workspace")
        .onChange(of: scenePhase, initial: true) { _, phase in presentation.setScenePhase(phase) }
        .onChange(of: controlActiveState, initial: true) { _, state in presentation.setReadingWindowActive(state == .key) }
        .focusedSceneValue(\.workspacePresentation, presentation)
        .onAppear { presentation.start() }
        .task(id: presentation.talkSourcePreparation) { [request = presentation.talkSourcePreparation] in
            await presentation.prepareTalkSource(request)
        }
        .onDisappear { Task { await presentation.release() } }
        .onChange(of: model.settingsOpen) { _, value in
            if value { presentation.openSettings() }
            else if presentation.scene.settingsOpen { presentation.scene.closeSettings() }
        }
        .onChange(of: colorScheme) { _, _ in
            presentation.scene.settle(); NativeReadingPageMotion.cancelAll(finishingClose: true)
        }
        .onChange(of: presentation.collectionPanel.owner) { _, owner in
            if owner != nil { presentation.scene.cancelPendingTalkReading() }
        }
        .onChange(of: model.stopping) { _, _ in presentation.publishPresence() }
        .onChange(of: presentation.onboarding.blocksWorkspace) { _, _ in presentation.publishPresence() }
        .onChange(of: presentation.onboarding.step) { _, _ in presentation.publishPresence() }
    }

    private var workspaceScene: some View {
        let routeID = presentation.navigationRouteID
        return NativeMokuScene(state: presentation.scene) {
            NativeRuntimeSurface(model: model) {
                if presentation.onboarding.blocksWorkspace { Color.clear }
                else { outside }
            }
        } dock: {
            if presentation.onboarding.mountDock, let thread = model.catalog.moku {
                let detail = presentation.dockThread
                let reportExecution = presentation.reportExecution
                let superThreadID = presentation.mokuSuperThreadID
                let mokuSource = presentation.mokuSubmissionSource
                let execution = presentation.dockExecution
                let sidecardComposer = presentation.sidecardComposer
                let detailRunning = detail.map {
                    presentation.dockInputAvailable && $0.observation.isExecutionActive
                        && (execution == nil || execution?.executionID == $0.observation.latestExecution?.executionID)
                }
                NativeMokuDock(state: presentation.scene, draft: presentation.dockDraft, cwd: detail?.cwd ?? "",
                    landing: detail == nil && superThreadID == nil && presentation.moku.landing,
                    threadID: detail?.id,
                    threadHarness: detail.flatMap { try? model.plugins.harnesses.require($0.harnessID) },
                    onThreadClose: {
                        if superThreadID != nil {
                            guard presentation.navigationRouteID == routeID, presentation.mokuSuperThreadID == superThreadID,
                                  !presentation.scene.dockCovered, !presentation.messageMotion.active else { return }
                            presentation.closeSuperThreadInput()
                            return
                        }
                        guard let detail, presentation.navigationRouteID == routeID,
                              presentation.dockThreadID == detail.id, !presentation.scene.dockCovered,
                              !presentation.messageMotion.active else { return }
                        if reportExecution != nil { presentation.closeReportExecutionInput() }
                        else { presentation.backFromReader() }
                    },
                    sidecardComposer: sidecardComposer,
                    awaitingContinuation: presentation.awaitingExecutionContinuation,
                    mode: detailRunning.map { $0 ? .running : .idle } ?? presentation.moku.dockMode,
                    running: sidecardComposer == nil && (detailRunning ?? presentation.moku.running),
                    talk: presentation.moku.talk, replyKey: detail == nil ? presentation.moku.replyKey : nil,
                    disabled: disabled || (detail.map { !model.canExecute($0) || (!presentation.dockInputAvailable && !presentation.retainsReportComposer) } ?? false),
                    interaction: presentation.moku.interaction, interactionIsQuestion: presentation.moku.interactionIsQuestion,
                    presentation: presentation.moku,
                    openExecution: presentation.openTalkExecution,
                    loadMentionDirectories: detail == nil ? nil : { try await model.services.knownDirectories() },
                    onSend: { submission in
                        if let sidecardComposer {
                            guard presentation.sidecardComposer?.id == sidecardComposer.id,
                                  presentation.navigationRouteID == routeID else { throw CancellationError() }
                            try await sidecardComposer.submit(submission.text)
                        } else if let detail {
                            try await presentation.sendThread(submission, to: detail.id, from: execution?.executionID, route: routeID)
                        }
                        else {
                            guard presentation.navigationRouteID == routeID,
                                  presentation.mokuSuperThreadID == superThreadID else { throw CancellationError() }
                            try await presentation.sendMoku(submission, source: mokuSource)
                        }
                    }, onCancel: {
                        if let detail {
                            guard presentation.navigationRouteID == routeID, presentation.dockThreadID == detail.id,
                                  presentation.dockExecution == execution, presentation.dockInputAvailable else { return }
                            presentation.perform { try await model.harnessHost.actions(for: detail).interrupt() }
                        }
                        else { presentation.cancelMoku(observed: thread) }
                    })
                    .opacity(presentation.collectionPanel.parentVisible || presentation.selected != nil ? 1 : 0)
                    .animation(NativeReadingPageTiming.openingAnimation, value: presentation.collectionPanel.parentVisible)
                    .opacity(presentation.onboarding.dockVisible ? 1 : 0)
                    .animation(nil, value: presentation.onboarding.dockVisible)
                    .disabled(presentation.browsingCollection)
                    .allowsHitTesting(!presentation.browsingCollection && !presentation.onboarding.blocksWorkspace)
                    .accessibilityHidden(presentation.browsingCollection || presentation.onboarding.blocksWorkspace)
            }
        } onCloseSettings: {
            presentation.settingsNavigation.requestClose(model: model.settingsModel) { _ in presentation.scene.closeSettings() }
        } settings: {
            if presentation.scene.settingsOpen { settings }
        }
        .overlay {
            if presentation.onboarding.blocksWorkspace, model.hasInitialContent {
                NativeOnboardingSurface(state: presentation.onboarding, scene: presentation.scene,
                    applicationSections: presentation.applicationHost.settingsSections(model: model.settingsModel))
            }
        }
        .overlay(alignment: .topLeading) {
            NativeWindowNavigationView(action: presentation.navigation, hidden: presentation.browsingCollection || presentation.nativeApplicationNavigation || presentation.usesReadingPanel,
                suspended: presentation.scene.settingsOpen,
                managesNativeButtons: !presentation.nativeApplicationNavigation || applicationSuppressed,
                reading: presentation.readingNavigation)
                .allowsHitTesting(!presentation.scene.settingsOpen && !presentation.onboarding.blocksWorkspace)
                .accessibilityHidden(presentation.scene.settingsOpen || presentation.onboarding.blocksWorkspace)
        }
    }

    @ViewBuilder private var outside: some View {
        // A disappearing page can publish nil after its replacement has mounted.
        // Fence navigation callbacks to the route visit that installed them.
        let routeID = presentation.navigationRouteID
        NativeReadingPageStack(open: presentation.selected != nil,
                identity: readingIdentity, motion: presentation.messageMotion,
                enabled: !presentation.scene.settingsOpen,
                focusBlur: true, stationaryParent: true, emphasizedOpening: true,
                panel: presentation.usesReadingPanel, isolatesParent: true, panelSource: { presentation.readingPanelSource },
                panelIdentity: presentation.selected?.typeID == "agent" ? presentation.threadIdentityVisit : nil,
                panelFrontIdentity: "workspace-reading-front",
                threadPanelMotion: presentation.selected?.typeID == "agent",
                reportPanelMotion: presentation.selected?.typeID == "report.document",
                requiresPanelSource: presentation.scene.talkReadingOrigin != nil,
                onParentPresentationChange: { active in
                    guard presentation.navigationRouteID == routeID, active || presentation.selected != nil else { return }
                    if !active || !presentation.readingCollectionMember { presentation.overview.setPresentationActive(active) }
                },
                prepareParent: { await presentation.prepareOverviewReturn() },
                onPanelOutsideClick: applicationSuppressed ? nil : {
                    guard presentation.navigationRouteID == routeID else { return }
                    // The Dock observes mouse-down without swallowing it. A press
                    // folding Overview input or owned by IME/transient controls
                    // cannot also close this panel. Agent input stays expanded.
                    guard !presentation.scene.inputHandledOutsideClick else { return }
                    if presentation.scene.talkReadingOrigin != nil || presentation.selected?.typeID == "agent" {
                        presentation.showOverview()
                    } else { presentation.closeApplication() }
                },
                onClose: { if presentation.navigationRouteID == routeID { presentation.finishBack() } }) {
                NativeOverviewWorkspaceView(model: presentation.overview,
                    callbacks: NativeOverviewWorkspaceCallbacks(
                        openThread: { id, target in presentation.open(ApplicationThreadRef(threadID: id, typeID: "agent"), target: target) },
                        openApplication: { presentation.open($0, target: $1) },
                        onSettings: { presentation.openSettings() }),
                    interactionPaused: presentation.scene.interactionPaused || presentation.messageMotion.active,
                    landing: presentation.moku.landing,
                    chromeVisible: presentation.selected == nil,
                    readingMotion: presentation.messageMotion)
                    .environment(\.overviewSwipeActions, NativeOverviewSwipeActions(
                        regions: presentation.scene.swipeRegions,
                        available: { presentation.overviewSwipeAvailable },
                        canFilter: { !presentation.scene.inputOpen && !presentation.moku.landing && presentation.canvas.interactionPauseReasons.isEmpty },
                        openConversation: {
                            guard presentation.overviewSwipeAvailable, model.catalog.hasMoku else { return false }
                            presentation.scene.openConversation()
                            return presentation.scene.conversationOpen
                        },
                        stepRail: { presentation.overview.stepRail(up: $0) }))
                    .nativeCollectionPanelHost(enabled: presentation.readingCollectionMember || (!presentation.scene.settingsOpen
                        && !presentation.onboarding.blocksWorkspace),
                        presentation: presentation.collectionPanel)
                    .environment(\.isApplicationCardUnread, model.preferences.threadReadHistory.isUnread)
            } front: {
                readingFront.id(routeID)
                    .environment(\.nativeExecutionDockRoute, routeID)
            }
            .task(id: [readingIdentity, presentation.readingTarget?.executionID ?? ""]) {
                guard let selected = presentation.selected, selected.typeID == "agent",
                      let thread = model.catalog.thread(selected.threadID) else { return }
                await model.harnessHost.prefetchReading(input: HarnessThreadInput(thread: thread, readingTarget: presentation.readingTarget))
            }
            .environment(\.nativeCollectionPanel, presentation.collectionPanel)
            .environment(\.nativeThreadIdentityRegistry, presentation.threadIdentityRegistry)
            .environment(\.nativeReadingInteractions, presentation.readingInteractions)
            .environment(\.nativeReadingInteractionVisit, routeID)
            .environment(\.nativeReadingInteractionRefresh, presentation.readingInteractions.refresh)
            .nativeReadingActive(presentation.interactionPage == "thread" && !presentation.messageMotion.active)
    }

    @ViewBuilder private var readingFront: some View {
        let routeID = presentation.navigationRouteID
        if let selected = presentation.selected, selected.typeID != "agent" {
            presentation.applicationHost.detail(thread: selected, readingTarget: presentation.readingTarget,
                environment: NativeApplicationDetailEnvironment(suppressed: applicationSuppressed,
                    contentTopInset: presentation.usesReadingPanel ? 60 : 74,
                    onBack: { if presentation.navigationRouteID == routeID { presentation.backFromReader() } }, onSettings: { presentation.openSettings() },
                    onNativeNavigationChange: { if presentation.navigationRouteID == routeID { presentation.nativeApplicationNavigation = $0 } },
                    onNavigationChange: { if presentation.navigationRouteID == routeID { presentation.navigation = $0 } }))
                .modifier(NativeApplicationReadingPanel(enabled: presentation.usesReadingPanel,
                    suppressed: applicationSuppressed, returnsToCollection: presentation.readingCollectionMember,
                    dismissToOverview: presentation.scene.talkReadingOrigin != nil ? {
                        if presentation.navigationRouteID == routeID { presentation.showOverview() }
                    } : nil,
                    onClose: { if presentation.navigationRouteID == routeID { presentation.backFromReader() } }))
                .onPreferenceChange(NativeApplicationHTMLReadinessKey.self) { document in
                    presentation.updateReportDocument(document, route: routeID)
                }
                .onChange(of: presentation.reportSidecards.displayedExecutionID) {
                    if presentation.navigationRouteID == routeID { presentation.recordVisibleBookmarks() }
                }
                .environment(\.nativeReportSidecards, presentation.reportSidecards)
                .environment(\.nativeApplicationReadingPanel, presentation.usesReadingPanel)
                .environment(\.nativeReportExecutionInputChanged, { reference, ready, onBack in
                    presentation.updateReportExecution(reference, ready: ready, onBack: onBack, route: routeID)
                })
                .environment(\.nativeReadingNavigation, presentation.usesReadingPanel ? nil : presentation.readingNavigation)
                .background {
                    NativeWorkspaceApplicationEntrance(admitted: presentation.readingEntranceAdmitted) {
                        _ = presentation.admitReadingEntrance(routeID: routeID, reference: selected)
                    }
                }
                .id(ApplicationSurfaceIdentity(thread: selected, recovery: model.recoveryRevision))
                .onAppear { if presentation.navigationRouteID == routeID { presentation.mountedReadingThread = selected } }
                .onDisappear { if presentation.navigationRouteID == routeID, presentation.mountedReadingThread == selected { presentation.mountedReadingThread = nil } }
        } else if let selected = presentation.selected, let thread = model.catalog.thread(selected.threadID) {
            NativeAgentThreadWorkspace(harnessHost: model.harnessHost, thread: thread, registry: model.plugins.sidecards,
                executionDisabled: !model.executionAvailable(thread), readingTarget: presentation.readingTarget,
                sidecardsSuppressed: applicationSuppressed,
                enabledSidecardIDs: enabledSidecards, services: presentation.sidecardServices(),
                onBack: { if presentation.navigationRouteID == routeID { presentation.backFromReader() } },
                onFollowUpVisibilityChange: { presentation.setFollowUpVisible($0) },
                backLabel: model.locale.text("返回俯瞰", "Back to overview"),
                onNavigationChange: { if presentation.navigationRouteID == routeID { presentation.navigation = $0 } },
                executionReveal: presentation.threadExecutionReveal,
                onEntranceReady: { presentation.admitReadingEntrance(routeID: routeID, reference: selected) })
                .environment(\.nativeAgentPanelClose, {
                    if presentation.navigationRouteID == routeID { presentation.showOverview() }
                })
                .environment(\.nativeAgentInputTargetChanged, { owner, target in
                    presentation.updateAgentInput(owner: owner, target: target, route: routeID)
                })
                .environment(\.nativeReadingNavigation, nil)
                .onAppear { if presentation.navigationRouteID == routeID { presentation.mountedReadingThread = selected } }
                .onChange(of: selected) { _, ref in if presentation.navigationRouteID == routeID { presentation.mountedReadingThread = ref } }
                .onDisappear { if presentation.navigationRouteID == routeID, presentation.mountedReadingThread == selected { presentation.mountedReadingThread = nil } }
        }
    }

    private var readingIdentity: JSONText {
        guard let selected = presentation.selected else { return "overview" }
        // SwiftUI can retain a removed front under the Settings transition.
        // A new visit must mount/register navigation even when reopening the same thread.
        return JSONText(codeUnits: JSONText("\(presentation.navigationRouteID.uuidString):\(selected.typeID.codeUnits.count):").codeUnits
            + selected.typeID.codeUnits + selected.threadID.codeUnits)
    }

    private var enabledSidecards: Set<JSONText> {
        Set(model.plugins.sidecards.modules.compactMap { module in
            let key = JSONText(codeUnits: JSONText("sidecard:").codeUnits + module.descriptor.id.codeUnits)
            guard let plugin = model.catalog.plugins.first(where: { $0["key"] == .string(key) }),
                  plugin["enabled"] == .bool(true), (plugin["unavailableReason"]?.stringValue?.isEmpty ?? true) else { return nil }
            return module.descriptor.id
        })
    }

    private var settings: some View {
        NativeSettingsPage(model: model.settingsModel, navigation: presentation.settingsNavigation, locale: model.locale, harnesses: model.plugins.harnesses.modules,
            applicationSections: presentation.applicationHost.settingsSections(model: model.settingsModel),
            harnessSettings: { request in
                AnyView(NativeHarnessSettingsView(host: model.harnessHost,
                    configuration: NativeHarnessSettingsConfiguration(harnessID: request.harnessID,
                        cwd: JSONText(model.settingsModel.defaultCwd), source: request.savedValue,
                        scope: .global(applicationSettings: request.scopeID, executionOwner: request.executionSnapshot ? .moku : nil)),
                    section: request.section, executionSnapshot: request.executionSnapshot, settingsFormPage: true,
                    refreshSequence: request.refreshSequence, value: request.value))
            }, onClose: { _ in presentation.scene.closeSettings() },
            mokuController: presentation.scene.settingsCharacter,
            onCoordinatorFrame: { presentation.scene.setCoordinatorFrame($0, pending: $1) })
    }
}

/// Applications have no Agent workspace to commit a folded Sidecard layout.
/// They release the same input gate after their own initial reading layout.
private struct NativeWorkspaceApplicationEntrance: View {
    let admitted: Bool
    let onReady: () -> Void
    @Environment(\.nativeReadingEntranceReady) private var primaryReady
    var body: some View {
        NativeReadingEntranceStage(enabled: primaryReady && !admitted, onReady: onReady)
    }
}

private struct ApplicationSurfaceIdentity: Hashable {
    let thread: ApplicationThreadRef
    let recovery: Int
}

private struct WorkspacePresentationKey: FocusedValueKey {
    typealias Value = NativeWorkspacePresentation
}
public extension FocusedValues {
    var workspacePresentation: NativeWorkspacePresentation? {
        get { self[WorkspacePresentationKey.self] }
        set { self[WorkspacePresentationKey.self] = newValue }
    }
}

public struct NativeWorkspaceCommands: Commands {
    @FocusedValue(\.workspacePresentation) private var presentation
    private let locale: DesktopLocale
    public init(locale: DesktopLocale) { self.locale = locale }
    public var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(locale.text("会话俯瞰", "Overview")) { presentation?.showOverview() }.keyboardShortcut("k")
                .disabled(presentation?.onboarding.blocksWorkspace == true)
            Button(locale.text("输入", "Compose")) { presentation?.scene.toggleInput(focusOnOpening: true) }
                .keyboardShortcut("b", modifiers: [.command, .shift]).disabled(presentation?.onboarding.blocksWorkspace == true || presentation?.scene.dockRouteVisible != true || presentation?.scene.inputInteractionReady != true || presentation?.scene.settingsOpen == true)
        }
        CommandGroup(replacing: .appSettings) {
            Button(locale.text("设置…", "Settings…")) { presentation?.openSettings() }.keyboardShortcut(",")
                .disabled(presentation?.canOpenSettings != true)
        }
    }
}
