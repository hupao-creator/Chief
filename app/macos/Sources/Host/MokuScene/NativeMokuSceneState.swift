import Foundation
import AppKit
import CoreGraphics
import Observation
import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI

/// Navigation lifetime shared by the overview, dock, thread and settings seats.
/// SwiftUI owns presentation and animation; the model owns navigation intent.
@MainActor @Observable public final class NativeMokuSceneState {
    public let settingsCharacter = MokuCharacterController()
    /// Controls outside the Dock that an outside click must treat as inside,
    /// such as the Overview's Return to Automatic View button.
    let outsideClickExclusions = NativeClickExclusions()
    /// One registry spans the canvas and its overlaid Moku surfaces. A drag
    /// over the capsule must retain control ownership on touch and pointer.
    let canvasInputRegions = NativeCanvasInputRegions()
    let swipeRegions = NativeOverviewSwipeRegions()
    let executionDockPlacement = NativeExecutionDockPlacement()
    private var landingActive = false
    // The handoff can cue only the Dock currently mounted in this scene.
    @ObservationIgnored weak var dockCharacter: NativeMokuCharacterMotion?
    public private(set) var inputOpen = false {
        didSet { if !inputOpen { conversationOpen = false; cancelComposerFocusRequest() } }
    }
    private(set) var conversationOpen = false
    public private(set) var inputPinnedOpen = false
    public private(set) var inputAdmissionReady = true
    private var inputIdentityReady = true
    private let readingPanelMotion: NativeReadingPageMotion?
    var readingPanelReturning: Bool { readingPanelVisible && readingPanelMotion?.isReturning == true }
    public var inputInteractionReady: Bool {
        inputAdmissionReady && inputIdentityReady && (!readingPanelVisible || readingPanelMotion?.active != true)
    }
    enum RetiringInput { case composer, conversation }
    private(set) var retiringInput: RetiringInput?
    public var inputLeaving: Bool { retiringInput != nil }
    public private(set) var composerGeneration = UUID() {
        didSet { cancelComposerFocusRequest() }
    }
    public private(set) var composerAutofocus = true
    struct ComposerFocusRequest: Equatable {
        let key: Int
        let generation: UUID
    }
    private(set) var composerFocusRequest: ComposerFocusRequest?
    @ObservationIgnored private var composerFocusSequence = 0
    @ObservationIgnored private var composeKeys: NativeMokuComposeKeyHandoff?
    @ObservationIgnored private var composerIdentity: ObjectIdentifier?
    public private(set) var talkPresentation = NativeMokuTalkState()
    public private(set) var settingsOpen = false
    public private(set) var settingsClosing = false
    public private(set) var settingsTransitioning = false
    var settingsExpanded = false
    private(set) var settingsTransitionRequest = 0
    @ObservationIgnored var settingsSettle: (() -> Void)?
    public private(set) var flightActive = false
    public private(set) var readReplies: Set<JSONText> = []
    struct NoteReadingOrigin {
        enum Phase: String { case dismissing, locating, reading }
        let id = UUID()
        let reference: ApplicationExecutionRef
        var space: String
        var phase = Phase.dismissing
        var returnsToNote = false
    }
    var noteReadingOrigin: NoteReadingOrigin?

    func finishLinkedNoteDismissal(_ id: UUID?) {
        guard let id, noteReadingOrigin?.id == id, noteReadingOrigin?.phase == .dismissing else { return }
        noteReadingOrigin?.phase = .locating
    }

    func cancelPendingNoteReading() {
        if let origin = noteReadingOrigin, origin.phase != .reading { noteReadingOrigin = nil }
    }
    public private(set) var notePanelOpen = false
    public private(set) var noteOpenGeneration = 0
    public var readingPanelVisible = false {
        didSet {
            if !dockRouteVisible { setInputOpen(false); dockHitRects = []; dockMentionHitRect = nil }
        }
    }
    public var dockRouteVisible: Bool { overviewVisible || readingPanelVisible }
    public var overviewVisible = true {
        didSet {
            guard overviewVisible != oldValue, !overviewVisible else { return }
            talkPresentation.setPresented(false)
            closeNotePanel()
            setInputOpen(false)
            if !dockRouteVisible { dockHitRects = []; dockMentionHitRect = nil }
            if !dockRouteVisible, dockInteractionVisible { setDockInteractionVisible(false, question: false) }
        }
    }
    public var disabled = false
    private(set) var dockVisibleViewport: CGRect?
    public var onSettingsOpenChange: ((Bool) -> Void)?
    public var onFlightActiveChange: ((Bool) -> Void)?
    @ObservationIgnored var command: ((Command) -> Void)?
    @ObservationIgnored var hostOwner: UUID?
    @ObservationIgnored var capsuleTask: Task<Void, Never>?
    @ObservationIgnored var retainedText = ""
    @ObservationIgnored var retainedAttachments: [NativeComposerAttachment] = []
    @ObservationIgnored var retainedDirectories: [NativeComposerDirectory] = []
    /// Caret/selection of the last open Dock editor. It outlives the editor
    /// view so reopening restores the reader's place instead of resetting it.
    @ObservationIgnored var retainedSelection: NSRange?
    @ObservationIgnored private var retainedSelectionText: String?
    @ObservationIgnored var capsuleSealed = false
    @ObservationIgnored var coordinatorFrame: CGRect?
    /// The normal-flow operation notice can scroll the shell without resizing
    /// its viewport. Fixed descendants compensate imperatively, without a new
    /// SwiftUI update while the enclosing clip view is publishing its bounds.
    @ObservationIgnored public private(set) var shellScrollOffset = CGPoint.zero
    public private(set) var windowVisible = false
    @ObservationIgnored var dockHitRects: [CGRect] = []
    @ObservationIgnored var dockMentionHitRect: CGRect?
    @ObservationIgnored private(set) var inputHandledOutsideClick = false
    @ObservationIgnored var capsuleFrame = CGRect.zero
    private(set) var dockInteractionVisible = false
    private(set) var dockInteractionIsQuestion = false
    @ObservationIgnored private var replyReadOrder: [JSONText]
    @ObservationIgnored private let replyReadFileURL: URL?
    @ObservationIgnored public var submitNoteExposure: ((JSONText, Int) async throws -> String)?
    @ObservationIgnored private var pendingNoteExposure: (id: JSONText, revision: Int)?
    @ObservationIgnored private var noteExposureTask: Task<Void, Never>?
    @ObservationIgnored private var noteExposureAuthority = UUID()
    @ObservationIgnored private var claimedNoteOpenGeneration = 0

    enum Command { case settings(Bool), coordinator(CGRect?, Bool), position, visibility, shellScroll, settle }
    public init(replyReadFileURL: URL? = nil,
                readingPanelMotion: NativeReadingPageMotion? = nil) {
        self.readingPanelMotion = readingPanelMotion
        self.replyReadFileURL = replyReadFileURL
        let stored = replyReadFileURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONValue.parse(data: $0) }?.arrayValue ?? []
        replyReadOrder = Array(stored.compactMap { value -> JSONText? in
            guard case let .string(text) = value else { return nil }
            return text
        }.suffix(256))
        readReplies = Set(replyReadOrder)
    }
    public var dockCovered: Bool { settingsOpen || flightActive }
    /// The resident Dock is available in Overview and ordinary Agent reading.
    /// Settings and flights own their own surfaces.
    public var dockContentVisible: Bool {
        windowVisible && !dockCovered && (dockRouteVisible || inputOpen || dockInteractionVisible)
    }
    public var interactionPaused: Bool { settingsOpen || flightActive || inputOpen }
    public var canOpenSettings: Bool { overviewVisible && !flightActive }

    /// Entrance belongs to the scene, so remounting or uncovering the Dock
    /// cannot reopen input over the resident character or a waiting notification.
    func updateLanding(_ active: Bool) -> Bool {
        guard active != landingActive else { return false }
        landingActive = active
        return true
    }
    public func toggleInput(focusOnOpening: Bool = false) {
        guard dockRouteVisible, inputInteractionReady else { return }
        let opening = !inputOpen
        let refocusingPinnedInput = inputPinnedOpen && inputOpen && !dockCovered
        if !refocusingPinnedInput { setInputOpen(!inputOpen) }

        // Compose accepts typing during the ink animation. In a pinned Agent
        // editor it can refocus even when TOC navigation suppressed autofocus.
        if refocusingPinnedInput || opening && focusOnOpening {
            focusOpenComposer(bufferOpeningKeys: opening && !inputPinnedOpen)
        }
    }
    func focusOpenComposer(bufferOpeningKeys: Bool = false) {
        guard inputOpen, inputInteractionReady, dockRouteVisible, !dockCovered else { return }
        let key = nextComposerFocusKey()
        composerFocusRequest = .init(key: key, generation: composerGeneration)
        if bufferOpeningKeys { composeKeys = .init(key: key) }
    }
    func nextComposerFocusKey() -> Int {
        composerFocusSequence += 1
        return composerFocusSequence
    }
    func cancelComposerFocusRequest() {
        composerFocusRequest = nil
        composeKeys?.cancel()
        composeKeys = nil
    }
    func composerDidAcquireFocus(key: Int, editor: NSTextView) {
        guard composeKeys?.key == key else { return }
        composeKeys?.focused(editor)
    }
    /// Draft ownership changes synchronously with navigation. Retiring ink and
    /// editor selection must never cross from Moku or one Thread to another.
    public func setComposerContext(_ draft: NativeComposerDraft, opensInput: Bool, keepsInputOpen: Bool = false,
                                   inputAdmissionReady: Bool = true, waitsForHarnessIdentity: Bool = false,
                                   autofocus: Bool = true, retainingOpenInput: Bool = false) {
        let identity = ObjectIdentifier(draft)
        // A document change inside an admitted reader replaces the draft, but
        // the pinned shell and its settled Harness mark still belong to the visit.
        let retainOpenInput = retainingOpenInput && opensInput && keepsInputOpen && inputPinnedOpen
            && inputOpen && inputInteractionReady && inputAdmissionReady
        inputPinnedOpen = keepsInputOpen
        if !waitsForHarnessIdentity { inputIdentityReady = true }
        else if !retainOpenInput, !inputAdmissionReady || composerIdentity != identity { inputIdentityReady = false }
        if self.inputAdmissionReady != inputAdmissionReady {
            self.inputAdmissionReady = inputAdmissionReady
            if !inputAdmissionReady {
                // Route entry must retire the previous editor immediately, even
                // when the same draft is retained. No leaving ink or focus task
                // may cross the primary entrance into a replacement visit.
                composerGeneration = UUID()
                capsuleTask?.cancel(); capsuleTask = nil
                inputOpen = false; retiringInput = nil; capsuleSealed = false
            }
        }
        guard composerIdentity != identity else { return }
        composerIdentity = identity
        composerAutofocus = autofocus
        composerGeneration = UUID()
        capsuleTask?.cancel(); capsuleTask = nil
        inputOpen = retainOpenInput; retiringInput = nil; capsuleSealed = false
        retainedSelection = nil; retainedSelectionText = nil
        retainDraft(draft)
        setInputOpen(opensInput)
        command?(.position)
    }
    func retireInputIdentity(generation: UUID) {
        // Reopening the same reader during its fold retains the draft and
        // generation. Its next expansion still needs a settled Harness mark.
        if composerGeneration == generation { inputIdentityReady = false }
    }
    func completeInputIdentity(generation: UUID) {
        // A removed flip may report after route replacement or Dock teardown.
        // Only the admitted composer visit can release its own expansion.
        guard composerGeneration == generation, inputAdmissionReady, !readingPanelReturning, !inputIdentityReady else { return }
        inputIdentityReady = true
        if inputPinnedOpen, !dockCovered, !dockInteractionVisible { setInputOpen(true) }
    }
    func ownsComposer(_ draft: NativeComposerDraft) -> Bool {
        composerIdentity == nil || composerIdentity == ObjectIdentifier(draft)
    }
    func openConversation() {
        guard overviewVisible, !readingPanelVisible, !dockCovered, !dockInteractionVisible,
              !notePanelOpen, !disabled, inputInteractionReady else { return }
        let openingEditor = !inputOpen
        setInputOpen(true)
        conversationOpen = true
        if openingEditor { focusOpenComposer(bufferOpeningKeys: true) }
    }
    func closeConversation() {
        if !landingActive { setInputOpen(false) }
        conversationOpen = false
    }
    public func setInputOpen(_ open: Bool) {
        guard !open || inputInteractionReady else { return }
        guard !settingsOpen else { return }
        guard !disabled || !open else { return }
        // Agent detail owns a persistent editor. Covering routes/interventions
        // may replace its surface; ordinary toggles and sends cannot fold it.
        guard open || !inputPinnedOpen || !dockRouteVisible || dockCovered || dockInteractionVisible else { return }
        guard open != inputOpen else { return }
        capsuleTask?.cancel(); capsuleTask = nil
        if open {
            talkPresentation.setPresented(false)
            closeNotePanel()
            retiringInput = nil; capsuleSealed = false; inputOpen = true
        }
        else if inputOpen {
            retiringInput = conversationOpen ? .conversation : .composer
            inputOpen = false
            capsuleTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(420))
                guard !Task.isCancelled, let self else { return }
                self.retiringInput = nil
            }
        }
        command?(.position)
    }

    /// Outside clicks leave bottom-Dock input mode; landing keeps its composer open.
    @discardableResult
    public func dismissInputForOutsideClick() -> Bool {
        guard inputOpen, !inputPinnedOpen, !landingActive || conversationOpen, dockRouteVisible, !dockCovered else { return false }
        closeConversation()
        inputHandledOutsideClick = true
        return true
    }
    func beginOutsideClick() {
        inputHandledOutsideClick = false
    }
    func preserveInputForOwnedClick() {
        // Composition or a transient control owns this press, even if AppKit
        // commits the mark or removes the popup before mouse-up.
        inputHandledOutsideClick = true
    }
    /// Reading and the Dock share cancellation priority even after focus has
    /// moved away from the editor. Landing retains input, just as for outside clicks.
    /// This retires presentation, never its draft.
    func dismissInputForEscape() -> Bool {
        guard inputOpen, !inputPinnedOpen, !landingActive || conversationOpen, dockContentVisible, !dockInteractionVisible else { return false }
        closeConversation()
        return true
    }
    public func receiveTalk(_ message: NativeMokuTalkMessage?) { talkPresentation.receive(message) }
    func setTalkPresented(_ visible: Bool) { talkPresentation.setPresented(visible) }
    func expireTalk(id: JSONText, deadline: ContinuousClock.Instant) { talkPresentation.expire(id: id, deadline: deadline) }
    public func dismissTalk() { talkPresentation.dismiss() }

    /// The note panel belongs to the Overview dock only. Composer and
    /// permission/question panels take priority; opening either closes it.
    public func toggleNotePanel() { setNotePanelOpen(!notePanelOpen) }
    /// Only the existing user entry points may start a fresh reading session.
    public func openNotePanelFromUser() {
        setNotePanelOpen(true)
        if notePanelOpen { noteOpenGeneration &+= 1 }
    }
    public func toggleNotePanelFromUser() {
        if notePanelOpen { setNotePanelOpen(false) }
        else { openNotePanelFromUser() }
    }
    public func claimNoteOpenArm() -> Bool {
        guard notePanelOpen, noteOpenGeneration > claimedNoteOpenGeneration else { return false }
        claimedNoteOpenGeneration = noteOpenGeneration
        return true
    }
    public func setNotePanelOpen(_ open: Bool) {
        guard !settingsOpen else { return }
        guard open != notePanelOpen else { return }
        guard !open || (overviewVisible && !disabled && !dockCovered && !dockInteractionVisible) else { return }
        if open { cancelPendingNoteReading(); setInputOpen(false) }
        notePanelOpen = open
        command?(.position)
    }
    private func closeNotePanel(cancelReading: Bool = true) {
        if cancelReading { cancelPendingNoteReading() }
        guard notePanelOpen else { return }
        notePanelOpen = false
        command?(.position)
    }
    public func noteUnread(_ note: NativeMokuNote?) -> Bool {
        note?.hasUnexposedUpdate == true
    }

    public func reconcileNoteExposure(_ note: NativeMokuNote?) {
        guard let pending = pendingNoteExposure else { return }
        guard let note, note.id == pending.id, note.revision == pending.revision,
              note.hasUnexposedUpdate else {
            pendingNoteExposure = nil
            noteExposureAuthority = UUID()
            noteExposureTask?.cancel(); noteExposureTask = nil
            return
        }
    }

    public func resetNoteExposureAuthority() {
        pendingNoteExposure = nil
        suspendNoteExposureSubmission()
    }

    public func suspendNoteExposureSubmission() {
        noteExposureAuthority = UUID()
        noteExposureTask?.cancel(); noteExposureTask = nil
    }

    public func recordNoteExposure(_ note: NativeMokuNote) {
        guard note.hasUnexposedUpdate else { return }
        pendingNoteExposure = (note.id, note.revision)
        retryNoteExposure()
    }

    public func retryNoteExposure() {
        guard noteExposureTask == nil, let pending = pendingNoteExposure,
              let submitNoteExposure else { return }
        let authority = noteExposureAuthority
        noteExposureTask = Task { [weak self] in
            let status = try? await submitNoteExposure(pending.id, pending.revision)
            guard let self, self.noteExposureAuthority == authority,
                  self.pendingNoteExposure?.id == pending.id,
                  self.pendingNoteExposure?.revision == pending.revision else { return }
            self.noteExposureTask = nil
            if status == "stale" { self.pendingNoteExposure = nil }
            // Accepted/duplicate only become visible after the authoritative
            // catalog arrives; failures wait for the next UI activity.
        }
    }
    public func retainDraft(_ draft: NativeComposerDraft, seal: Bool = false) {
        // A retiring view or late preview/import may still publish after
        // navigation has admitted another draft into this shared capsule.
        guard ownsComposer(draft), !capsuleSealed else { return }
        retainedText = draft.text; retainedAttachments = draft.attachments; retainedDirectories = draft.directories
        capsuleSealed = seal
    }
    func retainSelection(_ selection: NSRange, text: String) {
        guard selection.location != NSNotFound else { return }
        retainedSelection = selection; retainedSelectionText = text
    }
    func selectionForReopening(text: String) -> NSRange? {
        guard let retainedSelection, let retainedSelectionText else { return nil }
        // A send, paste or external draft replacement may have changed the
        // UTF-16 buffer while hidden. Never apply offsets from different text.
        return retainedSelectionText.utf16.elementsEqual(text.utf16)
            ? retainedSelection : NSRange(location: text.utf16.count, length: 0)
    }
    public func openSettings() {
        guard canOpenSettings else { return }
        guard !settingsOpen || settingsClosing else { return }
        cancelPendingNoteReading()
        talkPresentation.setPresented(false)
        // Keep the underlying input/Note visit alive. Settings temporarily owns
        // the capsule; a pending intervention is admitted after it retires.
        if !settingsOpen { settle() }
        settingsClosing = false; settingsOpen = true
        settingsTransitioning = settingsSettle != nil
        settingsTransitionRequest += 1
        onSettingsOpenChange?(true)
        command?(.settings(true))
    }
    public func closeSettings() {
        guard settingsOpen, !settingsClosing else { return }
        settingsClosing = true
        settingsTransitioning = settingsSettle != nil
        settingsTransitionRequest += 1
        if settingsSettle == nil { finishSettingsTransition() }
    }
    public func setCoordinatorFrame(_ rect: CGRect?, pending: Bool) {
        coordinatorFrame = rect
        command?(.coordinator(rect, pending))
    }
    public func setShellScrollOffset(_ offset: CGPoint) {
        guard offset.x.isFinite, offset.y.isFinite, shellScrollOffset != offset else { return }
        shellScrollOffset = offset
        command?(.shellScroll)
    }
    public func settle() { settingsSettle?(); command?(.settle) }
    func setDockInteractionVisible(_ value: Bool, question: Bool) {
        if value && !settingsOpen { talkPresentation.setPresented(false); closeNotePanel() }
        dockInteractionVisible = value; dockInteractionIsQuestion = question; command?(.position)
    }
    public func markReplyRead(_ key: JSONText) {
        guard !readReplies.contains(key) else { return }
        replyReadOrder = Array((replyReadOrder + [key]).suffix(256))
        readReplies = Set(replyReadOrder)
        guard let replyReadFileURL else { return }
        // Each native data directory has the same isolation as an Electron
        // profile's localStorage. A storage failure never interrupts reading.
        do {
            try FileManager.default.createDirectory(at: replyReadFileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONValue.array(replyReadOrder.map(JSONValue.string)).encodedData().write(to: replyReadFileURL, options: .atomic)
        } catch {}
    }
    func finishSettingsTransition() {
        settingsTransitioning = false
        guard settingsClosing else { return }
        settingsClosing = false; settingsOpen = false
        if dockInteractionVisible { closeNotePanel(); setInputOpen(false) }
        onSettingsOpenChange?(false)
    }
    func setWindowVisible(_ value: Bool) {
        if !value {
            dockCharacter?.cancelOnboardingBlink()
            talkPresentation.setPresented(false); closeNotePanel(cancelReading: false)
        }
        windowVisible = value
    }
    func dockViewport(in size: CGSize) -> CGRect {
        dockVisibleViewport ?? CGRect(origin: .zero, size: size)
    }
}
