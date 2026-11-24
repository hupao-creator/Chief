import Foundation
import Observation
import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI

@MainActor
public struct NativeOverviewApplicationFactories {
    public let gitStatus: (HarnessThread) -> HarnessGitStatus?
    public let projectionCapabilities: (AnyApplicationThreadPlugin, ApplicationThreadCatalogEntry<JSONValue>) throws -> ApplicationCapabilityAccess<ApplicationProjectionPhase>
    public let rendererContext: (AnyApplicationThreadPlugin, ApplicationThreadCatalogEntry<JSONValue>, PluginLifetime) throws -> ApplicationRendererContext
    public init(projectionCapabilities: @escaping (AnyApplicationThreadPlugin, ApplicationThreadCatalogEntry<JSONValue>) throws -> ApplicationCapabilityAccess<ApplicationProjectionPhase>,
                rendererContext: @escaping (AnyApplicationThreadPlugin, ApplicationThreadCatalogEntry<JSONValue>, PluginLifetime) throws -> ApplicationRendererContext,
                gitStatus: @escaping (HarnessThread) -> HarnessGitStatus? = { _ in nil }) {
        self.gitStatus = gitStatus
        self.projectionCapabilities = projectionCapabilities; self.rendererContext = rendererContext
    }
}

public struct NativeOverviewPresentationFacts: Equatable, Sendable {
    public var overviewVisible: Bool
    public var settingsOpen: Bool
    public var selectedThread: ApplicationThreadRef?
    public var followUpThread: ApplicationThreadRef?
    public var focused: Bool
    public var documentVisible: Bool
    public var available: Bool
    public init(overviewVisible: Bool = true, settingsOpen: Bool = false,
                selectedThread: ApplicationThreadRef? = nil, followUpThread: ApplicationThreadRef? = nil,
                focused: Bool = true, documentVisible: Bool = true, available: Bool = true) {
        self.overviewVisible = overviewVisible; self.settingsOpen = settingsOpen
        self.selectedThread = selectedThread; self.followUpThread = followUpThread
        self.focused = focused; self.documentVisible = documentVisible; self.available = available
    }
}

@MainActor
public enum NativeOverviewCardSnapshot {
    case harness(HarnessOverviewSnapshot)
    case application(AnyApplicationThreadPlugin, ApplicationOverviewSnapshot)
    case collection(AnyApplicationThreadPlugin, [ApplicationOverviewSnapshot])
}

enum NativeOverviewStatusFilter: String {
    case running, all, completed

    func includes(_ thread: HarnessThread) -> Bool {
        switch self {
        case .all: true
        case .running: thread.pendingInput || thread.observation.isExecutionActive || thread.observation.backgroundWork != nil
        case .completed: !thread.pendingInput && thread.observation.backgroundWork == nil && thread.observation.latestExecution?.status == .completed
        }
    }
}

/// Owns public catalog selection and the committed presentation session. Call receive
/// synchronously after EACH runtime transaction has been installed in the workspace;
/// observing SwiftUI renders instead would lose A → B → A structural transitions.
@MainActor @Observable
public final class NativeOverviewWorkspaceModel {
    public let workspace: NativeWorkspaceModel
    public let canvasState: NativeOverviewCanvasState
    public let content = NativeOverviewContentStore()
    public let applicationFactories: NativeOverviewApplicationFactories
    public let chromeInteractions = NativeOverviewChromeInteractions()
    public private(set) var tagSelection: NativeOverviewTagSelection?
    private var inboxStatus = NativeOverviewStatusFilter.all
    var isInboxTagSelected: Bool { selectedScope == NativeOverviewSelection.inboxScope }
    var statusFilter: NativeOverviewStatusFilter {
        if tagSelection?.runningTag == true { return .running }
        return isInboxTagSelected ? inboxStatus : .all
    }
    var railChoices: [NativeOverviewRailChoice] {
        guard selectedFilter != nil else { return [] }
        if let directory = selectedDirectory {
            return directory.children.map(NativeOverviewRailChoice.tag) + [.status(.running)]
        }
        return [.status(.running), .status(.all), .status(.completed)]
    }
    var selectedRailID: String? {
        if isInboxTagSelected || tagSelection?.runningTag == true {
            return statusFilter.rawValue
        }
        guard let selectedFilter, !selectedFilter.isDirectory else { return nil }
        return selectedFilter.id
    }
    // The delta path must also detect a selected tag member becoming visible.
    @ObservationIgnored private var statusHiddenThreads = Set<JSONText>()
    public private(set) var selectedTag = ""
    public private(set) var selectedScope = ""
    public private(set) var selectedFilter: NativeOverviewFilter?
    public private(set) var filters: [NativeOverviewFilter] = []
    public var visibleFilters: [NativeOverviewFilter] {
        filters.filter { $0.count > 0 }.map(visibleDirectory)
    }
    var selectedDirectory: NativeOverviewFilter? {
        guard !selectedScope.isEmpty else { return nil }
        return filters.first { $0.scope == selectedScope && $0.isDirectory && $0.count > 0 }.map(visibleDirectory)
    }
    private func visibleDirectory(_ filter: NativeOverviewFilter) -> NativeOverviewFilter {
        var visible = filter
        visible.children.removeAll { child in
            // Retain an active semantic selection when it becomes redundant:
            // promoting it would silently broaden future catalog updates.
            child.count == 0 || (redundantSemanticFilterKeys.contains(child.selectionKey)
                && tagSelection.map { child.matches($0.tag, kind: $0.kind, scope: $0.scope) } != true)
        }
        return visible
    }
    public private(set) var sceneKey = "\u{0}default"
    public var items: [NativeOverviewItem] { content.items }
    /// Global eligible cards, before tags and report coverage. Nil means
    /// no catalog has been projected yet; an unloaded workspace is not empty.
    public private(set) var globalConversationCount: Int?
    public private(set) var hasEstablishedConversation = false
    public private(set) var revisions: [NativeOverviewLayoutRevision] = [] {
        didSet { queuedPresentationIDs = Set(revisions.flatMap { $0.items.map(\.presentationID) }) }
    }
    public private(set) var recoveryEpoch: UInt64 = 0
    public private(set) var operations: [NativeOverviewMokuOperation] = []
    public var featuredOperation: NativeOverviewMokuOperation? { operations.last(where: { $0.phase == .running }) ?? operations.last }
    public private(set) var error: String?
    public private(set) var facts = NativeOverviewPresentationFacts()
    public private(set) var presentationActive = true
    @ObservationIgnored private var presentationDirty = false
    @ObservationIgnored private var collectionSources: [ApplicationThreadRef: String] = [:]
    @ObservationIgnored private var collectionReadingOwners: [ApplicationThreadRef: Set<ApplicationThreadRef>] = [:]
    @ObservationIgnored private var collectionSelections: [String: ApplicationThreadRef] = [:]
    @ObservationIgnored private var recentApplicationReading: [ApplicationThreadRef: ApplicationCollectionReading] = [:]
    @ObservationIgnored private var applicationVisit: NativeOverviewCollectionVisit?
    @ObservationIgnored private var applicationReadDeadline: Task<Void, Never>?
    private(set) var returnMember: ApplicationThreadRef?
    var readingSource: NativeOverviewReadingSource?
    // A member reader covers a live grid. Save its ranking inputs before the
    // visit writes reading evidence, so Back can restore the same grid seat.
    @ObservationIgnored private var heldCollectionRanks: [ApplicationThreadRef: (idle: Bool, qualifiedAt: Double?)] = [:]
    @ObservationIgnored private var projectedCollectionScene: String?
    @ObservationIgnored private var collectionWindowSize: CGSize?
    @ObservationIgnored private var hasCollectionCandidates = false
    @ObservationIgnored private var collectionAgeSample = Date().timeIntervalSince1970
    @ObservationIgnored private var snapshots: [String: NativeOverviewCardSnapshot] = [:]
    @ObservationIgnored private var harnessCache: [JSONText: HarnessOverviewSnapshot] = [:]
    @ObservationIgnored private var applicationCache: [JSONText: (JSONValue, ApplicationOverviewSnapshot)] = [:]
    @ObservationIgnored private(set) var membershipBuildCount = 0
    @ObservationIgnored private var queuedPresentationIDs = Set<String>()
    @ObservationIgnored private var catalogIDs = Set<String>()
    @ObservationIgnored private var catalogGeneration: UInt64?
    @ObservationIgnored private var membershipFacts: NativeOverviewMembershipFacts?
    @ObservationIgnored private(set) var filterContextFacts: [JSONValue] = []
    @ObservationIgnored private var membershipIndex = NativeOverviewMembershipIndex()
    private var filterMembers: [String: NativeOverviewMembership] { membershipIndex.members }
    private var redundantSemanticFilterKeys: Set<String> { membershipIndex.redundant }
    @ObservationIgnored private var unreadVersions: [ApplicationThreadRef: JSONText] = [:]
    @ObservationIgnored private var activeThreadIDs = Set<JSONText>()
    @ObservationIgnored private var globalApplicationIDs = Set<JSONText>()
    @ObservationIgnored private var establishedThreadIDs = Set<JSONText>()
    @ObservationIgnored private var pendingInsertedIDs = Set<String>()
    @ObservationIgnored private var globalThreadIDs = Set<JSONText>()
    @ObservationIgnored private var overviewEntries: [ApplicationThreadRef: (JSONValue, NativeOverviewApplicationEntry)] = [:]
    @ObservationIgnored private var operationProjectionReady = false
    @ObservationIgnored private var operationThreadID: JSONText?
    @ObservationIgnored private var operationTranscript: JSONValue?
    private var catalogThreads: [HarnessThread] { workspace.catalog.threads }
    @ObservationIgnored private var applicationRecords = RuntimeRecordCollection<NativeOverviewApplicationEntry>()
    // Whole reads use the runtime's authoritative order. The typed index only
    // owns decoding, so changed-ID Set iteration cannot reorder tied cards.
    private var catalogApplications: [NativeOverviewApplicationEntry] {
        workspace.catalog.applicationIDs.compactMap { applicationRecords[$0] }
    }
    @ObservationIgnored private var applicationsByRef: [ApplicationThreadRef: NativeOverviewApplicationEntry] = [:]
    @ObservationIgnored private var catalogApplicationJSON: [JSONText: JSONValue] = [:]
    @ObservationIgnored private var directoryTags = NativeOverviewDirectoryTagCache()
    @ObservationIgnored private var retainedPresentationIDs = Set<String>()
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var snapshotAuthority: UUID?
    @ObservationIgnored private var contextID = UUID().uuidString
    @ObservationIgnored private var contextRevision = 0
    @ObservationIgnored private var committedContext: JSONValue?
    @ObservationIgnored private var committedFacts: JSONValue?
    @ObservationIgnored private var actions: [JSONValue] = []
    @ObservationIgnored private var actionSequence = 0
    @ObservationIgnored private var publication: Task<Void, Never>?
    @ObservationIgnored private var active = true

    public init(workspace: NativeWorkspaceModel, applications: NativeOverviewApplicationFactories,
                canvasState: NativeOverviewCanvasState = .init()) {
        self.workspace = workspace; applicationFactories = applications; self.canvasState = canvasState
    }

    public func receive(_ event: RuntimeClientEvent) {
        guard active else { return }
        switch event {
        case .snapshot(_, let authority):
            acceptAuthority(authority)
            // Observer overflow replays the same authority's current catalog.
            // Refresh its content without invalidating an already issued filter
            // request or discarding the structural stages still in flight.
            reconcile(captureMutation: false)
        case .mutation(_, _, let authority):
            acceptAuthority(authority)
            reconcile(captureMutation: true)
        case .connection, .synchronizing: publishContext()
        case .overviewFilter(let request): receiveFilter(request)
        case .failure, .threadContent: break
        }
    }

    private func acceptAuthority(_ authority: UUID) {
        if snapshotAuthority != authority {
            if snapshotAuthority == workspace.client.cachedSnapshotAuthority {
                // A fallback shown offline is provisional. The live catalog
                // resolves the saved preference again.
                tagSelection = nil
            }
            snapshotAuthority = authority
            catalogGeneration = nil; membershipFacts = nil
            overviewEntries.removeAll()
            operationThreadID = nil; operationTranscript = nil; operationProjectionReady = false
            recoveryEpoch += 1
            contextID = UUID().uuidString
            committedFacts = nil
            revisions.removeAll()
        }
    }

    /// Also useful after a host factory or plugin registry changes at startup.
    public func refresh() { catalogGeneration = nil; membershipFacts = nil; operationThreadID = nil; operationTranscript = nil; operationProjectionReady = false; reconcile(captureMutation: false) }

    /// Host observations can change card geometry without changing catalog membership.
    public func refreshCardExtensions() { reconcile(captureMutation: true) }

    func setCollectionWindowSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, collectionWindowSize != size else { return }
        collectionWindowSize = size
        if hasCollectionCandidates, presentationActive { reconcile(captureMutation: false, refreshSelection: false) }
    }

    /// The reading stack owns this gate: its parent still participates in opening
    /// and return motion even though the logical route already points at detail.
    public func setPresentationActive(_ value: Bool) {
        guard active, presentationActive != value else { return }
        presentationActive = value
        revisions.removeAll()
        if value {
            collectionAgeSample = Date().timeIntervalSince1970
            recoveryEpoch += 1
            if presentationDirty { reconcile(captureMutation: false) }
        } else {
            presentationDirty = true
        }
    }

    public func setPresentation(_ value: NativeOverviewPresentationFacts) {
        guard facts != value else { return }
        let becameVisible = !facts.overviewVisible && value.overviewVisible
        if facts.overviewVisible != value.overviewVisible {
            revisions.removeAll()
            // Leaving retains the committed canvas as the reading backdrop.
            // Recover hidden structural changes when Overview becomes active.
            if value.overviewVisible { recoveryEpoch += 1 }
        }
        facts = value
        if becameVisible { collectionAgeSample = Date().timeIntervalSince1970 }
        // Direct navigation/recovery can bypass an animated return.
        if value.overviewVisible {
            setPresentationActive(true)
            if presentationDirty || becameVisible { reconcile(captureMutation: false) }
        }
        pruneSnapshots()
        publishContext()
    }

    func selectTopFilter(_ filter: NativeOverviewFilter?) {
        guard let filter, filter.isDirectory, filter.scope != selectedScope,
              let directory = filters.first(where: { $0.isDirectory && $0.scope == filter.scope && $0.count > 0 }) else {
            selectTag(filter)
            return
        }
        if workspace.preferences.overviewRunningDirectories.contains(directory.scope) {
            selectRunningTag(in: directory)
            return
        }
        let children = visibleDirectory(directory).children
        let saved = workspace.preferences.overviewDirectoryTags[directory.scope].flatMap { tag in
            redirected(.init(tag: tag, kind: .semantic, scope: directory.scope))
        }
        let child = saved.flatMap { selection in children.first { $0.matches(selection.tag) } }
        selectTag(child ?? children.first ?? directory)
    }

    public func selectTag(_ filter: NativeOverviewFilter?) {
        let tag = filter?.tag ?? ""
        appendAction(["kind": .text("filter"), "tag": tag.isEmpty ? .null : .text(tag)])
        selectTagValue(tag, scope: filter?.scope ?? "",
                       kind: filter.map { $0.isDirectory ? .directory : .semantic })
    }

    func stepRail(up: Bool) {
        let choices = railChoices
        guard let selectedRailID else {
            if up, let first = choices.first { selectRailChoice(first) }
            return
        }
        guard choices.count > 1, let index = choices.firstIndex(where: { $0.id == selectedRailID }) else { return }
        let next = (index + (up ? choices.count - 1 : 1)) % choices.count
        selectRailChoice(choices[next])
    }

    func selectRailChoice(_ choice: NativeOverviewRailChoice) {
        switch choice {
        case .tag(let filter):
            selectTag(filter)
        case .status(let status):
            if let directory = selectedDirectory {
                if status == .running { selectRunningTag(in: directory) }
            } else if isInboxTagSelected, inboxStatus != status {
                inboxStatus = status
                reconcile(captureMutation: false, refreshSelection: false)
            }
        }
    }

    private func selectRunningTag(in directory: NativeOverviewFilter) {
        // Running owns the folder's membership, including work under its other tags.
        selectTagValue(directory.tag, scope: directory.scope, kind: .directory, runningTag: true)
    }

    private var browseSceneKey: String {
        (selectedFilter?.selectionKey.nonEmpty ?? (selectedScope.isEmpty ? selectedTag : "\(selectedScope)\u{0}\(selectedTag)"))
            + (tagSelection?.runningTag == true ? "\u{0}running" : "\u{0}default")
    }

    public func consumeRevisions(through value: UInt64) {
        revisions.removeAll { $0.revision <= value }
        pruneSnapshots()
    }
    public func retainPresentations(_ values: Set<String>) {
        retainedPresentationIDs = values
        pruneSnapshots()
    }
    public func snapshot(for item: NativeOverviewItem) -> NativeOverviewCardSnapshot? { snapshots[item.presentationID] }

    public func sourceCardID(for reference: ApplicationThreadRef) -> String? { collectionSources[reference] }

    func visibleCardID(for reference: ApplicationThreadRef) -> String? {
        let id = sourceCardID(for: reference) ?? reference.threadID.string
        return content.activeIDs.contains(id) ? id : nil
    }

    func revealNoteDestination(_ reference: ApplicationThreadRef) {
        if let current = selectedFilter, filterMembers[current.selectionKey]?.contains(reference) == true {
            if tagSelection?.runningTag == true,
               reference.typeID != "agent" || workspace.catalog.thread(reference.threadID).map(statusFilter.includes) != true {
                selectTag(current)
            }
            return
        }
        // A citation from a semantic tag can lead to a sibling in the same folder.
        // Keep that level of detail before broadening to the directory.
        func matches(_ filter: NativeOverviewFilter) -> Bool {
            filterMembers[filter.selectionKey]?.contains(reference) == true
        }
        let sibling = tagSelection?.kind == .semantic ? selectedDirectory?.children.first(where: matches) : nil
        if let match = sibling ?? allFilters.first(where: matches) {
            selectTag(match)
        } else if reference.typeID == "agent", let thread = workspace.catalog.thread(reference.threadID),
                  let directory = filters.first(where: { $0.isDirectory && $0.scope == NativeOverviewSelection.scope(thread) }),
                  directory.selectionKey != selectedFilter?.selectionKey {
            // An archived or failed Thread can still have a directory even without a card.
            selectTag(directory)
        }
    }

    public func selectedCollectionMember(for item: NativeOverviewItem) -> ApplicationThreadRef? {
        guard case .collection(_, let members) = snapshot(for: item) else { return nil }
        if let returnMember, members.contains(where: { $0.entry.ref == returnMember }) { return returnMember }
        if let selected = collectionSelections[item.id], members.contains(where: { $0.entry.ref == selected }) { return selected }
        return members.first?.entry.ref
    }

    public func selectCollectionMember(_ reference: ApplicationThreadRef, cardID: String) {
        guard collectionSources[reference] == cardID else { return }
        if let returnMember, collectionSources[returnMember] == cardID, returnMember != reference { self.returnMember = nil }
        collectionSelections[cardID] = reference
    }

    func collectionReadingOwner(of thread: ApplicationThreadRef) -> ApplicationThreadRef? {
        guard let owners = collectionReadingOwners[thread], owners.count == 1 else { return nil }
        return owners.first
    }

    /// Report and associated Agent routes share one visit while their owner is
    /// unchanged. Coverage is matched by Thread, not by its current execution.
    public func recordReadingRoute(_ route: ApplicationThreadRef?, at date: Date = .now,
                                   uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let reference: ApplicationThreadRef?
        if let route, route.typeID == "agent" {
            reference = collectionReadingOwner(of: route)
        } else { reference = route }
        guard applicationVisit?.reference != reference else { return }
        recordApplicationClose(at: date, uptime: uptime)
        if let reference { recordApplicationOpen(reference, at: date, uptime: uptime) }
    }

    /// Repeated opens of the same reading owner do not reset foreground dwell.
    public func recordApplicationOpen(_ reference: ApplicationThreadRef, at date: Date = .now,
                                      uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard applicationVisit?.reference != reference,
              let plugin = try? workspace.plugins.applications.requireThread(reference.typeID),
              plugin.overviewCollection != nil,
              let entry = try? workspace.catalog.applicationEntry(reference),
              let estimate = try? plugin.estimatedReadingSeconds(entry) else { return }
        recordApplicationClose(at: date, uptime: uptime)
        let now = date.timeIntervalSince1970
        var evidence = reading(reference) ?? .init()
        applicationVisit = .init(reference: reference, openedAt: now, estimate: estimate,
                                 createdAt: entry.createdAt / 1000, evidence: &evidence)
        returnMember = reference
        saveReading(reference, evidence)
        readingChanged()
    }

    public func recordApplicationClose(at date: Date = .now, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        updateApplicationReading(visible: false, uptime: uptime)
        guard let visit = applicationVisit else { return }
        applicationVisit = nil
        var evidence = reading(visit.reference) ?? .init()
        visit.close(at: date.timeIntervalSince1970, evidence: &evidence)
        saveReading(visit.reference, evidence)
        readingChanged()
    }

    public func updateApplicationReading(visible: Bool, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        applicationReadDeadline?.cancel()
        applicationReadDeadline = nil
        guard var visit = applicationVisit else { return }
        let wasQualified = visit.qualified
        visit.advance(visible: visible, uptime: uptime)
        applicationVisit = visit
        guard !wasQualified else { return }
        if visit.qualified {
            var evidence = reading(visit.reference) ?? .init()
            visit.promote(&evidence)
            saveReading(visit.reference, evidence)
            readingChanged()
        } else if visible {
            let delay = max(0.01, visit.threshold - visit.elapsed)
            applicationReadDeadline = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(delay))
                    try Task.checkCancellation()
                    self?.updateApplicationReading(visible: true)
                } catch { }
            }
        }
    }

    func holdCollectionRank(for reference: ApplicationThreadRef) {
        guard heldCollectionRanks[reference] == nil,
              let entry = try? workspace.catalog.applicationEntry(reference) else { return }
        heldCollectionRanks[reference] = (isIdle(entry, now: collectionAgeSample), reading(reference)?.lastQualifiedAt)
    }

    func releaseCollectionRanks() {
        guard !heldCollectionRanks.isEmpty else { return }
        heldCollectionRanks.removeAll()
        readingChanged()
    }

    private func reading(_ reference: ApplicationThreadRef) -> ApplicationCollectionReading? {
        recentApplicationReading[reference] ?? workspace.preferences.applicationCollectionReading[readingHistoryKey(reference)]
    }

    private func updateCollectionReadingOwners(_ entry: NativeOverviewApplicationEntry, inserting: Bool) {
        guard (try? workspace.plugins.applications.requireThread(entry.entry.ref.typeID))?.overviewCollection != nil else { return }
        for reference in entry.coveredExecutions where reference.thread.typeID == "agent" {
            if inserting { collectionReadingOwners[reference.thread, default: []].insert(entry.entry.ref) }
            else {
                collectionReadingOwners[reference.thread]?.remove(entry.entry.ref)
                if collectionReadingOwners[reference.thread]?.isEmpty == true { collectionReadingOwners.removeValue(forKey: reference.thread) }
            }
        }
    }

    private func isIdle(_ entry: ApplicationThreadCatalogEntry<JSONValue>, now: Double) -> Bool {
        let evidence = reading(entry.ref) ?? .init()
        if applicationVisit?.reference == entry.ref { return evidence.staysCollected == true }
        return evidence.isIdle(createdAt: entry.createdAt / 1000, now: now)
    }

    private func saveReading(_ reference: ApplicationThreadRef, _ value: ApplicationCollectionReading) {
        // Failed writes preserve session evidence but cannot claim disk recovery.
        recentApplicationReading[reference] = value
        do { try workspace.preferences.recordApplicationReading(key: readingHistoryKey(reference), value: value) }
        catch { workspace.report(error) }
    }

    private func readingChanged() {
        presentationDirty = true
        if facts.overviewVisible && presentationActive { reconcile(captureMutation: true) }
    }

    public func collectionEligibility(_ reference: ApplicationThreadRef, at now: Date = .now) -> JSONValue? {
        guard let entry = overviewEntries[reference]?.1.entry,
              (try? workspace.plugins.applications.requireThread(reference.typeID))?.overviewCollection != nil else { return nil }
        let state = reading(reference)
        return .object([
            "lastClosedAt": state?.lastClosedAt.map { .number($0 * 1000) } ?? .null,
            "lastQualifiedAt": state?.lastQualifiedAt.map { .number($0 * 1000) } ?? .null,
            "defaultsToCollection": .bool(isIdle(entry, now: now.timeIntervalSince1970)),
            "collected": .bool(collectionSources[reference] != nil)
        ])
    }

    private func readingHistoryKey(_ reference: ApplicationThreadRef) -> String {
        reference.typeID.string + ":" + reference.threadID.string
    }

    /// Await this before a user submission so its intent has crossed the runtime
    /// boundary. UTF-16 truncation matches JS slice(0, 4000), including surrogates.
    public func recordUserAction(kind: String, thread: ApplicationThreadRef? = nil, text: JSONText? = nil) async {
        var fields: [JSONText: JSONValue] = ["kind": .text(kind)]
        fields["thread"] = thread?.json
        fields["text"] = text.map { .string(JSONText(codeUnits: Array($0.codeUnits.prefix(4000)))) }
        appendAction(fields)
        publishContext()
        await publication?.value
    }

    private func selectTagValue(_ tag: String, scope: String = "", kind: NativeOverviewTagKind? = nil, runningTag: Bool = false) {
        let filter = matchingFilter(tag: tag, scope: scope, kind: kind)
        let resolvedKind = kind ?? (filter?.isDirectory == true ? .directory : .semantic)
        tagSelection = tag.isEmpty ? filters.first(where: { $0.count > 0 })?.selection
            : .init(tag: tag, kind: resolvedKind, scope: filter?.scope ?? scope, runningTag: runningTag)
        reconcile(captureMutation: false, explicitSelection: true)
    }

    private var allFilters: [NativeOverviewFilter] {
        filters + filters.flatMap(\.children)
    }

    private func matchingFilter(tag: String, scope: String = "", kind: NativeOverviewTagKind? = nil) -> NativeOverviewFilter? {
        guard !tag.isEmpty else { return nil }
        return allFilters.first { $0.matches(tag, kind: kind, scope: scope.isEmpty ? nil : scope) }
    }

    private func redirected(_ selection: NativeOverviewTagSelection) -> NativeOverviewTagSelection? {
        NativeOverviewSelection.resolve(selection, redirects: workspace.catalog.tagRedirects)
    }

    private func resolveSelection(_ requested: NativeOverviewTagSelection?, refreshRedirects: Bool) -> NativeOverviewFilter? {
        // Use the same top-row order and eligibility as the mounted chrome.
        // An unloaded or temporarily empty catalog must leave the saved choice intact.
        guard let first = filters.first(where: { $0.count > 0 }) else { return nil }
        guard let selection = requested else { return first }
        let directory = filters.first { $0.isDirectory && $0.scope == selection.scope && $0.count > 0 }
        if selection.kind == .directory { return directory ?? first }
        let candidate = refreshRedirects ? redirected(selection) : selection
        if let candidate, let match = matchingFilter(tag: candidate.tag, scope: candidate.scope, kind: candidate.kind),
           match.count > 0 {
            return match
        }
        // Keep the existing in-session child-removal behavior. A saved child
        // missing on first admission falls back in top-row order.
        return (tagSelection != nil ? directory : nil) ?? first
    }

    private func reconcile(captureMutation: Bool, refreshSelection: Bool = true, explicitSelection: Bool = false) {
        do {
            if try applyCatalogChanges(captureMutation: captureMutation) { return }
            let previousCatalogIDs = catalogIDs
            let previousItems = items
            let previousScene = sceneKey
            if catalogGeneration != workspace.catalog.installGeneration {
                let nextApplications = try workspace.catalog.applicationThreads.map { raw in
                    guard case .string(let id)? = raw["ref"]?["threadId"], case .string(let type)? = raw["ref"]?["typeId"] else {
                        throw PluginContractError("Invalid application thread identity")
                    }
                    let ref = ApplicationThreadRef(threadID: id, typeID: type)
                    if let cached = overviewEntries[ref], cached.0 == raw { return cached.1 }
                    let entry = try NativeOverviewApplicationEntry(entry: workspace.catalog.applicationEntry(json: raw))
                    overviewEntries[ref] = (raw, entry)
                    return entry
                }
                let liveRefs = Set(nextApplications.map { $0.entry.ref })
                overviewEntries = overviewEntries.filter { liveRefs.contains($0.key) }
                refreshMokuOperations()
                applicationRecords = .init()
                for item in nextApplications { applicationRecords.updateValue(item, forKey: item.entry.ref.threadID) }
                catalogIDs = Set(catalogThreads.map { $0.id.string } + nextApplications.map { $0.entry.ref.threadID.string })
                applicationsByRef = Dictionary(uniqueKeysWithValues: nextApplications.map { ($0.entry.ref, $0) })
                collectionReadingOwners.removeAll()
                for entry in nextApplications { updateCollectionReadingOwners(entry, inserting: true) }
                catalogApplicationJSON = Dictionary(uniqueKeysWithValues: zip(nextApplications, workspace.catalog.applicationThreads).map { ($0.0.entry.ref.threadID, $0.1) })
                directoryTags.update(threads: catalogThreads)
                let nextActiveThreadIDs = Set(catalogThreads.filter { $0.moku != true && $0.observation.isExecutionActive }.map(\.id))
                let changedActivity = activeThreadIDs != nextActiveThreadIDs
                activeThreadIDs = nextActiveThreadIDs
                var nextUnread: [ApplicationThreadRef: JSONText] = [:]
                for thread in catalogThreads {
                    let ref = ApplicationThreadRef(threadID: thread.id, typeID: "agent")
                    nextUnread[ref] = unreadAgentVersion(ref, thread)
                }
                for item in nextApplications {
                    nextUnread[item.entry.ref] = try unreadApplicationVersion(item)
                }
                let changedUnread = nextUnread != unreadVersions
                unreadVersions = nextUnread
                let nextFacts = NativeOverviewMembershipFacts(threads: catalogThreads, applications: nextApplications)
                if membershipFacts != nextFacts {
                    rebuildMembership()
                    membershipFacts = nextFacts
                } else if changedActivity || changedUnread {
                    refreshFilterIndicators(filters)
                }
                let harnessIDs = Set(catalogThreads.map(\.id)), applicationIDs = Set(nextApplications.map { $0.entry.ref.threadID })
                harnessCache = harnessCache.filter { harnessIDs.contains($0.key) }
                applicationCache = applicationCache.filter { applicationIDs.contains($0.key) }
                catalogGeneration = workspace.catalog.installGeneration
            }
            // Redirects depend on selection too; selecting another tag must not
            // wait for the next catalog transaction.
            let requested = tagSelection ?? workspace.preferences.overviewSelection
            let nextFilter = resolveSelection(requested, refreshRedirects: refreshSelection || tagSelection == nil)
            var resolved = nextFilter?.selection
            if requested?.runningTag == true, requested?.kind == .directory,
               nextFilter?.isDirectory == true, requested?.scope == nextFilter?.scope {
                resolved?.runningTag = true
            }
            tagSelection = resolved
            selectedTag = tagSelection?.tag ?? ""
            selectedScope = tagSelection?.scope ?? ""
            if selectedFilter?.id != nextFilter?.id { inboxStatus = .all }
            selectedFilter = nextFilter
            if let tagSelection, explicitSelection || snapshotAuthority != workspace.client.cachedSnapshotAuthority {
                do { try workspace.preferences.selectOverviewSpace(tagSelection) }
                catch { workspace.report(error) }
            }
            guard presentationActive else {
                presentationDirty = true
                publishContext()
                return
            }
            // Scene identity belongs to the retained presentation too. Advancing
            // it while hidden could bookmark the old camera under a new selection.
            sceneKey = browseSceneKey
            let selected = selectedFilter.flatMap { filterMembers[$0.selectionKey] }.map(resolve)
                ?? NativeOverviewCollection(threads: [], applications: [])
            let nextItems = try project(filterByStatus(selected))
            if sceneKey != previousScene { revisions.removeAll() }
            if captureMutation, facts.overviewVisible, previousScene == sceneKey,
               previousItems.map(\.structuralIdentity) != nextItems.map(\.structuralIdentity) {
                revision += 1
                let inserted = catalogIDs.subtracting(previousCatalogIDs).union(pendingInsertedIDs)
                revisions.append(.init(revision: revision, sceneKey: sceneKey, items: nextItems, instantEntryIDs: inserted))
            }
            content.install(nextItems)
            presentationDirty = false
            error = nil
            pendingInsertedIDs.removeAll()
            pruneSnapshots()
            publishContext()
        } catch { self.error = error.localizedDescription; workspace.report(error) }
    }

    /// A catalog mutation carries its accepted identities all the way to card
    /// slots. Unchanged membership/order leaves every other card and filter alone.
    private func applyCatalogChanges(captureMutation: Bool) throws -> Bool {
        let change = workspace.catalog.changes
        guard error == nil, let generation = catalogGeneration, generation &+ 1 == workspace.catalog.installGeneration,
              !change.reset, let membershipFacts, membershipFacts.localeIsCurrent,
              !change.threadOrderChanged, !change.applicationOrderChanged,
              change.fields.isDisjoint(with: ["tagRedirects", "plugins", "settings"]) else { return false }
        var changedThreads: [HarnessThread] = []
        var changedApplications: [(id: JSONText, raw: JSONValue?, old: NativeOverviewApplicationEntry?, next: NativeOverviewApplicationEntry?)] = []
        var membershipThreads = Set<JSONText>(), membershipApplications = Set<JSONText>()
        var changedActivity = false, changedUnread = false
        for id in change.threadIDs {
            let thread = workspace.catalog.thread(id)
            let ordinary = thread.flatMap { $0.moku == true ? nil : $0 }
            if !membershipFacts.matches(thread, id: id)
                || (change.threadStructureIDs.contains(id) && (ordinary != nil || !membershipFacts.matches(nil, id: id))) {
                membershipThreads.insert(id)
            }
            if let ordinary { changedThreads.append(ordinary) }
        }
        for id in change.applicationIDs {
            let raw = workspace.catalog.applicationJSON(id), previous = applicationRecords[id]
            let next = try raw.map { try NativeOverviewApplicationEntry(entry: workspace.catalog.applicationEntry(json: $0)) }
            let ref = next?.entry.ref ?? previous?.entry.ref
            if change.applicationStructureIDs.contains(id) || previous?.entry.ref != next?.entry.ref
                || ref.map({ !membershipFacts.matches(next, ref: $0) }) == true { membershipApplications.insert(id) }
            changedApplications.append((id, raw, previous, next))
        }
        let changedMembership = !membershipThreads.isEmpty || !membershipApplications.isEmpty
        for id in change.threadIDs {
            let thread = workspace.catalog.thread(id)
            if thread?.moku != true && thread?.observation.isExecutionActive == true {
                changedActivity = activeThreadIDs.insert(id).inserted || changedActivity
            } else {
                changedActivity = activeThreadIDs.remove(id) != nil || changedActivity
            }
            let ref = ApplicationThreadRef(threadID: id, typeID: "agent")
            let version = unreadAgentVersion(ref, thread)
            if unreadVersions[ref] != version { unreadVersions[ref] = version; changedUnread = true }
            directoryTags.update(thread, id: id)
            if let thread, thread.moku != true {
                if catalogIDs.insert(id.string).inserted { pendingInsertedIDs.insert(id.string) }
            } else { catalogIDs.remove(id.string); harnessCache.removeValue(forKey: id) }
            if membershipThreads.contains(id) {
                membershipFacts.update(thread, id: id)
                let candidates = NativeOverviewSelection.candidates(threads: thread.map { $0.moku == true ? [] : [$0] } ?? [], applications: [])
                if let candidate = candidates.threads.first {
                    globalThreadIDs.insert(id)
                    if candidate.observation.latestExecution != nil { establishedThreadIDs.insert(id) }
                    else { establishedThreadIDs.remove(id) }
                } else { globalThreadIDs.remove(id); establishedThreadIDs.remove(id) }
            }
        }
        for (id, raw, previous, next) in changedApplications {
            if let previous { updateCollectionReadingOwners(previous, inserting: false) }
            if let next { updateCollectionReadingOwners(next, inserting: true) }
            if let previous, previous.entry.ref != next?.entry.ref {
                if unreadVersions.removeValue(forKey: previous.entry.ref) != nil { changedUnread = true }
                overviewEntries.removeValue(forKey: previous.entry.ref); applicationsByRef.removeValue(forKey: previous.entry.ref)
                applicationCache.removeValue(forKey: id)
            }
            if let raw, let next {
                let version = try unreadApplicationVersion(next)
                if unreadVersions[next.entry.ref] != version { unreadVersions[next.entry.ref] = version; changedUnread = true }
                overviewEntries[next.entry.ref] = (raw, next); applicationsByRef[next.entry.ref] = next
                applicationRecords.updateValue(next, forKey: id); catalogApplicationJSON[id] = raw
                if catalogIDs.insert(id.string).inserted { pendingInsertedIDs.insert(id.string) }
            } else {
                applicationRecords.removeValue(forKey: id); catalogApplicationJSON.removeValue(forKey: id)
                catalogIDs.remove(id.string); applicationCache.removeValue(forKey: id)
            }
            if membershipApplications.contains(id) {
                membershipFacts.update(next, previous: previous?.entry.ref)
                if !NativeOverviewSelection.candidates(threads: [], applications: next.map { [$0] } ?? []).applications.isEmpty { globalApplicationIDs.insert(id) }
                else { globalApplicationIDs.remove(id) }
            }
        }
        var affectedScopes = Set<String>()
        if changedMembership {
            membershipBuildCount += 1
            affectedScopes = membershipIndex.update(threadIDs: membershipThreads, applicationIDs: membershipApplications,
                catalog: workspace.catalog, directoryTags: directoryTags.values, application: { applicationRecords[$0] })
            publishMembership(); refreshGlobalAvailability()
        } else if changedActivity || changedUnread {
            refreshFilterIndicators(filters)
            selectedFilter = matchingFilter(tag: selectedTag, scope: selectedScope, kind: tagSelection?.kind)
        }
        if !operationProjectionReady || operationThreadID != workspace.catalog.moku?.id
            || workspace.catalog.moku.map({ change.threadIDs.contains($0.id) }) == true { refreshMokuOperations() }
        catalogGeneration = workspace.catalog.installGeneration
        // A covered canvas retains its cards and camera, but the published selection
        // must already refer to the new membership when a tag or directory disappears.
        if changedMembership {
            let current = matchingFilter(tag: selectedTag, scope: selectedScope, kind: tagSelection?.kind)
            if current == nil || current?.count == 0 || affectedScopes.contains(selectedScope) {
                reconcile(captureMutation: captureMutation, refreshSelection: false)
                return true
            }
            selectedFilter = current
            publishContext()
        }
        guard presentationActive else {
            presentationDirty = true
            return true
        }
        if statusFilter != .all, changedThreads.contains(where: { thread in
            statusFilter.includes(thread) ? statusHiddenThreads.contains(thread.id) : content.activeIDs.contains(thread.id.string)
        }) {
            reconcile(captureMutation: captureMutation, refreshSelection: false)
            return true
        }
        if changedApplications.contains(where: { change in
            collectionSources.keys.contains(where: { $0.threadID == change.id })
        }) {
            reconcile(captureMutation: captureMutation, refreshSelection: false)
            return true
        }
        let selected = NativeOverviewCollection(
            threads: changedThreads.filter { content.activeIDs.contains($0.id.string) },
            applications: changedApplications.compactMap(\.next).filter { content.activeIDs.contains($0.entry.ref.threadID.string) })
        let next = try project(selected, groupCollections: false)
        let previousTokens = next.compactMap { content.records[$0.id]?.presentationID }
        guard content.update(next) else {
            reconcile(captureMutation: captureMutation, refreshSelection: false)
            return true
        }
        let currentTokens = Set(next.map(\.presentationID))
        for token in previousTokens where !retainedPresentationIDs.contains(token) && !queuedPresentationIDs.contains(token) {
            if !currentTokens.contains(token) { snapshots.removeValue(forKey: token) }
        }
        error = nil
        return true
    }

    private func filterByStatus(_ selected: NativeOverviewCollection) -> NativeOverviewCollection {
        statusHiddenThreads.removeAll(keepingCapacity: true)
        let status = statusFilter
        guard status != .all else { return selected }
        let threads = selected.threads.filter { thread in
            if status.includes(thread) { return true }
            statusHiddenThreads.insert(thread.id)
            return false
        }
        return .init(threads: threads, applications: status == .completed ? selected.applications : [])
    }

    private func refreshMokuOperations() {
        operationThreadID = workspace.catalog.moku?.id
        if !operationProjectionReady || operationTranscript != workspace.catalog.moku?.transcript {
            operationProjectionReady = true
            operationTranscript = workspace.catalog.moku?.transcript
            operations = NativeOverviewMokuOperation.project(transcript: operationTranscript)
        }
    }

    private func resolve(_ membership: NativeOverviewMembership) -> NativeOverviewCollection {
        .init(threads: membership.threads.map { workspace.catalog.thread($0)! },
              applications: membership.applications.map { applicationsByRef[$0]! })
    }

    private func rebuildMembership() {
        membershipBuildCount += 1
        let threads = catalogThreads, applications = catalogApplications
        let candidates = NativeOverviewSelection.candidates(threads: threads, applications: applications)
        globalThreadIDs = Set(candidates.threads.map(\.id))
        globalApplicationIDs = Set(candidates.applications.map { $0.entry.ref.threadID })
        establishedThreadIDs = Set(candidates.threads.filter { $0.observation.latestExecution != nil }.map(\.id))
        refreshGlobalAvailability()
        membershipIndex.reset(threads: threads, applications: applications, catalog: workspace.catalog,
            directoryTags: directoryTags.values, application: { applicationRecords[$0] })
        publishMembership()
    }

    private func refreshGlobalAvailability() {
        globalConversationCount = workspace.catalog.revision >= 0 ? globalThreadIDs.count + globalApplicationIDs.count : nil
        hasEstablishedConversation = !globalApplicationIDs.isEmpty || !establishedThreadIDs.isEmpty
    }

    private func publishMembership() {
        refreshFilterIndicators(membershipIndex.filters)
        filterContextFacts = membershipIndex.contextFacts(filters: filters)
    }

    private func refreshFilterIndicators(_ source: [NativeOverviewFilter]) {
        // Reuse the exact browsing memberships, including report coverage and
        // hidden/archived exclusions. Activity never changes membership/context.
        func hasActiveTasks(_ membership: NativeOverviewMembership) -> Bool {
            membership.threads.contains { activeThreadIDs.contains($0) }
        }
        func decorated(_ filter: NativeOverviewFilter) -> NativeOverviewFilter {
            let members = filterMembers[filter.selectionKey]!
            var result = filter
            result.hasActiveTasks = hasActiveTasks(members)
            result.unreadCount = members.threads.count {
                unreadVersions[ApplicationThreadRef(threadID: $0, typeID: "agent")] != nil
            } + members.applications.count { unreadVersions[$0] != nil }
            result.children = filter.children.map(decorated)
            return result
        }
        let next = source.map(decorated)
        if filters != next { filters = next }
    }

    private func unreadVersion(_ ref: ApplicationThreadRef, _ version: JSONText?) -> JSONText? {
        guard let version, workspace.preferences.threadReadHistory.isUnread(ref, version: version) else { return nil }
        return version
    }

    private func unreadAgentVersion(_ ref: ApplicationThreadRef, _ thread: HarnessThread?) -> JSONText? {
        guard let thread, thread.archived != true, !thread.isHiddenFromUser else { return nil }
        return unreadVersion(ref, thread.bookmarkVersion)
    }

    private func unreadApplicationVersion(_ item: NativeOverviewApplicationEntry) throws -> JSONText? {
        guard item.visible, !item.entry.archived,
              let plugin = try? workspace.plugins.applications.requireThread(item.entry.ref.typeID),
              let version = try plugin.bookmarkVersion?(item.entry.view) else { return nil }
        return unreadVersion(item.entry.ref, version)
    }

    func markRead(_ ref: ApplicationThreadRef, version: JSONText) throws {
        if try recordReadReceipt(ref, version: version) { refreshUnreadIndicators() }
    }

    func clearUnread(inTag id: String) {
        // Resolve the mounted choice again so a hold cannot acknowledge a tag
        // that moved out of the rail while the catalog or selection changed.
        guard let filter = selectedDirectory?.children.first(where: { $0.id == id }),
              filter.unreadCount > 0, let members = filterMembers[filter.selectionKey] else { return }
        let agents = members.threads.map { ApplicationThreadRef(threadID: $0, typeID: "agent") }
        var changed = false
        for ref in agents + members.applications {
            guard let version = unreadVersions[ref] else { continue }
            do {
                if try recordReadReceipt(ref, version: version) { changed = true }
            } catch { workspace.report(error) }
        }
        if changed { refreshUnreadIndicators() }
    }

    private func recordReadReceipt(_ ref: ApplicationThreadRef, version: JSONText) throws -> Bool {
        try workspace.preferences.threadReadHistory.markRead(ref, version: version)
        // A ready reader can still acknowledge an older document during a revision change.
        guard unreadVersions[ref] == version else { return false }
        unreadVersions.removeValue(forKey: ref)
        return true
    }

    private func refreshUnreadIndicators() {
        refreshFilterIndicators(filters)
        selectedFilter = matchingFilter(tag: selectedTag, scope: selectedScope, kind: tagSelection?.kind)
    }

    func containsGlobalThread(_ id: JSONText) -> Bool { globalThreadIDs.contains(id) }

    private typealias CardEntry = (created: Double, index: Int, item: NativeOverviewItem)

    private func project(_ collection: NativeOverviewCollection, groupCollections: Bool = true) throws -> [NativeOverviewItem] {
        var entries: [CardEntry] = []
        for thread in collection.threads {
            let input = HarnessThreadInput(thread: thread, git: applicationFactories.gitStatus(thread))
            let projection: HarnessOverviewSnapshot
            if let cached = harnessCache[thread.id], cached.input == input { projection = cached }
            else { projection = try workspace.harnessHost.overview(input: input, availableColumns: HarnessOverviewCapacity.maximumColumns); harnessCache[thread.id] = projection }
            let token = "agent:\(thread.id.string):\(ObjectIdentifier(projection))"
            snapshots[token] = .harness(projection)
            let completed = NativeOverviewStatusFilter.completed.includes(thread)
            entries.append((thread.createdAt, entries.count, .init(id: thread.id.string,
                columns: projection.envelope.footprint.columns, rows: projection.envelope.footprint.rows,
                structureKey: projection.envelope.structureKey.string,
                needsAttention: thread.observation.latestExecution?.status == .waitingForUser, presentationID: token,
                completed: completed)))
        }
        for application in collection.applications {
            let entry = application.entry
            let plugin = try workspace.plugins.applications.requireThread(entry.ref.typeID)
            let projection: ApplicationOverviewSnapshot
            let json = catalogApplicationJSON[entry.ref.threadID]!
            if let cached = applicationCache[entry.ref.threadID], cached.0 == json { projection = cached.1 }
            else {
                projection = try plugin.projectCard(entry: entry, availableColumns: HarnessOverviewCapacity.maximumColumns,
                    capabilities: applicationFactories.projectionCapabilities(plugin, entry))
                applicationCache[entry.ref.threadID] = (json, projection)
            }
            let token = "application:\(entry.ref.typeID.string):\(entry.ref.threadID.string):\(ObjectIdentifier(projection))"
            snapshots[token] = .application(plugin, projection)
            entries.append((entry.createdAt, entries.count, .init(id: entry.ref.threadID.string,
                columns: projection.envelope.footprint.columns, rows: projection.envelope.footprint.rows,
                structureKey: projection.envelope.structureKey.string, presentationID: token, completed: true)))
        }
        entries.sort { a, b in
            return a.created == b.created ? a.index < b.index : a.created < b.created
        }
        if groupCollections {
            try groupApplications(collection.applications, in: &entries)
        }
        return entries.map(\.item)
    }

    private func groupApplications(_ applications: [NativeOverviewApplicationEntry], in entries: inout [CardEntry]) throws {
        if projectedCollectionScene != browseSceneKey { collectionAgeSample = Date().timeIntervalSince1970 }
        projectedCollectionScene = browseSceneKey
        let now = collectionAgeSample
        var plans: [(group: NativeOverviewCollectionBudget, plugin: AnyApplicationThreadPlugin,
                     providesCardSurface: Bool, snapshots: [ApplicationOverviewSnapshot])] = []
        var visitedTypes = Set<JSONText>()
        for application in applications where visitedTypes.insert(application.entry.ref.typeID).inserted {
            let typeID = application.entry.ref.typeID
            let plugin = try workspace.plugins.applications.requireThread(typeID)
            guard let policy = plugin.overviewCollection else { continue }
            let snapshotsForType = applications.filter { $0.entry.ref.typeID == typeID }.map { applicationCache[$0.entry.ref.threadID]!.1 }
            guard snapshotsForType.count >= 2 else { continue }
            let ranked = snapshotsForType.map { snapshot in
                let entry = snapshot.entry
                let rank = heldCollectionRanks[entry.ref] ?? (isIdle(entry, now: now), reading(entry.ref)?.lastQualifiedAt)
                let qualified = rank.qualifiedAt
                return (snapshot: snapshot, qualified: qualified != nil, idle: rank.idle,
                        priority: qualified ?? entry.createdAt / 1000)
            }.sorted { a, b in
                if a.idle != b.idle { return a.idle }
                if a.qualified != b.qualified { return !a.qualified }
                return a.priority < b.priority
            }
            let id = "\u{0}application-collection:\(plugin.id.string):\(browseSceneKey)"
            let card = NativeOverviewMember(id: id, columns: policy.footprint.columns, rows: policy.footprint.rows)
            plans.append((.init(card: card, rankedIDs: ranked.map { $0.snapshot.entry.ref.threadID.string },
                                idleCount: ranked.prefix(while: { $0.idle }).count), plugin, policy.providesCardSurface, snapshotsForType))
        }
        let counts = plans.isEmpty ? [] : try NativeOverviewCollectionBudget.memberCounts(in: entries.map { $0.item.member },
            groups: plans.map(\.group), windowSize: collectionWindowSize)
        hasCollectionCandidates = !plans.isEmpty
        collectionSources.removeAll()
        for (plan, count) in zip(plans, counts) where count > 0 {
            let card = plan.group.card
            let ids = Set(plan.group.rankedIDs.prefix(count))
            let members = plan.snapshots.filter { ids.contains($0.entry.ref.threadID.string) }
            let token = card.id + ":" + members.map { String(describing: ObjectIdentifier($0)) }.joined(separator: ",")
            snapshots[token] = .collection(plan.plugin, members)
            for member in members { collectionSources[member.entry.ref] = card.id }
            let origin = entries.firstIndex { ids.contains($0.item.id) }!
            entries[origin].item = .init(id: card.id, columns: card.columns, rows: card.rows,
                structureKey: "application-collection", presentationID: token, completed: true,
                providesCardSurface: plan.providesCardSurface)
            entries.removeAll { ids.contains($0.item.id) }
        }
    }

    private func pruneSnapshots() {
        let used = retainedPresentationIDs.union(content.retainedPresentationIDs)
            .union(items.map(\.presentationID)).union(revisions.flatMap { $0.items.map(\.presentationID) })
        snapshots = snapshots.filter { used.contains($0.key) }
    }

    private func appendAction(_ fields: [JSONText: JSONValue]) {
        var fields = fields
        fields["at"] = .number(Date().timeIntervalSince1970 * 1000)
        actions.append(.object(fields)); actions = Array(actions.suffix(20)); actionSequence += 1
    }

    @discardableResult
    private func publishContext() -> JSONValue? {
        guard active else { return nil }
        var fields: [JSONText: JSONValue] = [
            "overviewVisible": .bool(facts.overviewVisible), "mokuOpen": .bool(false), "settingsOpen": .bool(facts.settingsOpen),
            "selectedThread": facts.selectedThread?.json ?? .null, "followUpThread": facts.followUpThread?.json ?? .null,
            "focused": .bool(facts.focused), "documentVisible": .bool(facts.documentVisible), "view": .text("default"),
            "selectedTag": (selectedFilter?.tag ?? selectedTag).nonEmpty.map(JSONValue.text) ?? .null,
            "selectedScope": (selectedFilter?.scope ?? selectedScope).nonEmpty.map(JSONValue.text) ?? .null,
            "filters": .array(filterContextFacts), "recentActions": .array(actions)]
        let factKey = JSONValue.array([.text(contextID), .object(fields), .integer(actionSequence)])
        guard factKey != committedFacts else { return committedContext }
        committedFacts = factKey
        contextRevision += 1
        fields["contextId"] = .text(contextID); fields["revision"] = .integer(contextRevision)
        let context = JSONValue.object(fields)
        committedContext = context
        let previous = publication, client = workspace.client
        publication = Task { await previous?.value; try? await client.updateOverviewContext(context) }
        return context
    }

    public func receiveFilter(_ request: JSONValue) {
        guard active, let requestID = request["requestId"]?.stringValue else { return }
        publishContext()
        Task { [weak self] in
            guard let self, self.active, let before = self.committedContext else { return }
            var status = self.filterStatus(request, context: before)
            if status == nil || status == "unchanged" {
                let claimed = (try? await self.workspace.client.claimOverviewFilter(requestID)) ?? false
                guard self.active else { return }
                self.publishContext()
                status = claimed && self.committedContext != nil ? self.filterStatus(request, context: self.committedContext!) : "unavailable"
                if status == nil {
                    let scope = request["scope"]?.stringValue ?? ""
                    self.selectTagValue(request["tag"]?.stringValue ?? "", scope: scope)
                    status = self.committedContext?["selectedTag"] == request["tag"] && (scope.isEmpty || self.selectedScope == scope)
                        ? "applied" : "unavailable"
                }
            }
            guard let context = self.committedContext else { return }
            try? await self.workspace.client.acknowledgeOverviewFilter(.object([
                "requestId": .text(requestID), "status": .text(status ?? "unavailable"), "context": context]))
        }
    }

    private func filterStatus(_ request: JSONValue, context: JSONValue) -> String? {
        guard facts.available, workspace.connection == .connected,
              let expiry = request["expiresAt"]?.numberValue, Date().timeIntervalSince1970 * 1000 < expiry else { return "unavailable" }
        guard request["contextId"] == context["contextId"], request["revision"] == context["revision"] else { return "stale" }
        let scope = request["scope"]?.stringValue ?? ""
        if request["tag"] == .null { return selectedFilter == nil ? "unchanged" : "unavailable" }
        guard allFilters.contains(where: { $0.count > 0 && .text($0.tag) == request["tag"] && (scope.isEmpty || $0.scope == scope) }) else {
            return "unavailable"
        }
        // A catalog request for the directory itself also leaves its Running tag.
        return tagSelection?.runningTag != true && request["tag"] == context["selectedTag"]
            && (scope.isEmpty || scope == selectedScope) ? "unchanged" : nil
    }

    public func stop() async {
        active = false
        collectionSources.removeAll(); collectionSelections.removeAll(); recentApplicationReading.removeAll()
        collectionReadingOwners.removeAll(); heldCollectionRanks.removeAll()
        applicationReadDeadline?.cancel(); applicationReadDeadline = nil
        applicationVisit = nil
        await publication?.value
        try? await workspace.client.updateOverviewContext(nil)
        content.stop()
        snapshots.removeAll(); revisions.removeAll(); harnessCache.removeAll(); applicationCache.removeAll(); directoryTags.removeAll()
        membershipFacts = nil; membershipIndex = .init(); applicationsByRef.removeAll()
        statusHiddenThreads.removeAll()
        unreadVersions.removeAll(); activeThreadIDs.removeAll()
        globalThreadIDs.removeAll(); globalConversationCount = nil; hasEstablishedConversation = false
        applicationRecords = .init(); catalogIDs.removeAll()
        globalApplicationIDs.removeAll(); establishedThreadIDs.removeAll(); pendingInsertedIDs.removeAll()
    }
}

private extension String { var nonEmpty: String? { isEmpty ? nil : self } }
