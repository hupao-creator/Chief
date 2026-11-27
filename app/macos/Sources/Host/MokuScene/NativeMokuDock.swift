import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI

private let composerRevealStart: CGFloat = 0.9
private let maximumConversationHeight: CGFloat = 648

/// The editor uses its final layout throughout the morph. Reveal it in the
/// last part of the shell's own travel, once the identity has cleared the row.
private struct ComposerInk: ViewModifier, @preconcurrency Animatable {
    var expansion: CGFloat
    let autofocusGeneration: UUID?
    let requestFocus: (UUID) -> Void

    var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }
    func body(content: Content) -> some View {
        let opacity = min(1, max(0, (expansion - composerRevealStart) / (1 - composerRevealStart)))
        content.opacity(opacity)
            .onChange(of: opacity >= 0.1 ? autofocusGeneration : nil, initial: true) { _, generation in
                if let generation { requestFocus(generation) }
            }
    }
}

/// Propose each presented size to the glass, its overlays and their alignment
/// together, from the expanded reader through the compact Overview row.
/// Settings retains its panel layout inside the same editor tree.
private struct CapsuleSurfaceFrame: ViewModifier, @preconcurrency Animatable {
    var size: CGSize
    let sizesRow: Bool
    let compactChanged: (Bool) -> Void

    var animatableData: CGSize.AnimatableData {
        get { size.animatableData }
        set { size.animatableData = newValue }
    }

    func body(content: Content) -> some View {
        let idle = NativeMokuCapsuleLayout.idleSize
        content.frame(width: sizesRow ? size.width : nil, height: sizesRow ? size.height : nil)
            .onChange(of: size.width <= idle.width && size.height <= idle.height, initial: true) { _, compact in
                compactChanged(compact)
            }
    }
}

/// One glass capsule. Production composer, transcript and interaction ownership stay in the scene.
/// Agent detail supplies its own Thread draft.
public struct NativeMokuDock: View {
    public let state: NativeMokuSceneState
    public let draft: NativeComposerDraft
    public let cwd: JSONText
    public var threadID: JSONText?
    public var threadHarness: AnyHarnessPlugin?
    public var onThreadClose: (() -> Void)?
    public var sidecardComposer: SidecardComposerRequest?
    public var landing: Bool
    public var mode: MokuCharacterMode
    public var running: Bool
    public var reasoning: MokuReasoningContent?
    public var talk: String?
    public var replyKey: JSONText?
    public var disabled: Bool
    public var interaction: AnyView?
    public var interactionIsQuestion: Bool
    public var onSend: (NativeComposerSubmission) async throws -> Void
    public var onSendConsumed: (NativeComposerSubmission) async -> Void
    public var awaitingContinuation: Bool
    public var onCancel: () -> Void
    public var presentation: NativeMokuWorkspacePresentation?
    public var openExecution: ((ApplicationExecutionRef) -> Void)?
    public var loadMentionDirectories: (() async throws -> [NativeComposerDirectory])?
    @Environment(\.nativeMokuSettingsContent) private var settingsContent
    @Environment(\.locale) private var locale
    @Environment(\.nativeOfflineDraftEditing) private var offlineDraftEditing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.nativeExecutionDockPlacement) private var executionPlacement
    @Environment(\.nativeMokuHorizontalTravel) private var travelHost
    @State private var hovered = false
    @State private var hoverTask: Task<Void, Never>?
    @FocusState private var stopFocused: Bool
    @AccessibilityFocusState private var stopAccessibilityFocused: Bool
    // The Report can withdraw its execution marker and draft before the shell
    // finishes folding. Retain only the seat occupied by the visible input.
    private struct InputColumn: Equatable {
        let frame: CGRect
        let viewport: CGSize
    }
    @State private var inputColumn: InputColumn?
    @State private var shellIsCompact = true
    @State private var settledDestination: NativeMokuHorizontalDestination?
    @State private var capsuleHeight: CGFloat = 58
    @State private var completionHeight: CGFloat = 0
    @State private var focusGeneration: UUID?
    @State private var explicitFocusGeneration: UUID?
    @State private var focusRequest = 0
    @State private var directoryMentions = NativeMokuDirectoryMentions()
    @State private var editorBottomInset: CGFloat = 29
    @State private var conversationContentHeight: CGFloat = 0
    @State private var settingsPreferredHeight: CGFloat = 900
    @State private var settingsHeaderScroll: CGFloat = 0
    @State private var linkedTalkHeight: CGFloat = NativeMokuTalkTypography.maximumHeight
    @State private var talkScrollbarStyle = NSScroller.preferredScrollerStyle
    @State private var character = NativeMokuCharacterMotion()
    @State private var reasoningRequested = false
    @State private var reasoningSeatReserved = false
    @State private var reasoningReady = false
    @State private var reasoningTransition = 0
    @State private var retainedReasoningGlyphs: [MokuReasoningGlyph] = []

    public init(state: NativeMokuSceneState, draft: NativeComposerDraft, cwd: JSONText,
                landing: Bool = false, threadID: JSONText? = nil,
                threadHarness: AnyHarnessPlugin? = nil, onThreadClose: (() -> Void)? = nil,
                sidecardComposer: SidecardComposerRequest? = nil,
                awaitingContinuation: Bool = false,
                mode: MokuCharacterMode = .idle, running: Bool = false, reasoning: MokuReasoningContent? = nil,
                talk: String? = nil,
                replyKey: JSONText? = nil, disabled: Bool = false,
                interaction: AnyView? = nil, interactionIsQuestion: Bool = false,
                presentation: NativeMokuWorkspacePresentation? = nil,
                openExecution: ((ApplicationExecutionRef) -> Void)? = nil,
                loadMentionDirectories: (() async throws -> [NativeComposerDirectory])? = nil,
                onSend: @escaping (NativeComposerSubmission) async throws -> Void,
                onSendConsumed: @escaping (NativeComposerSubmission) async -> Void = { _ in },
                onCancel: @escaping () -> Void) {
        self.state = state; self.draft = draft; self.cwd = cwd; self.mode = mode; self.running = running
        self.awaitingContinuation = awaitingContinuation
        self.reasoning = reasoning
        self.landing = landing
        self.threadID = threadID
        self.threadHarness = threadHarness; self.onThreadClose = onThreadClose
        self.sidecardComposer = sidecardComposer
        self.talk = talk; self.replyKey = replyKey; self.disabled = disabled; self.interaction = interaction
        self.interactionIsQuestion = interactionIsQuestion
        self.onSend = onSend; self.onSendConsumed = onSendConsumed; self.onCancel = onCancel
        self.presentation = presentation
        self.openExecution = openExecution
        self.loadMentionDirectories = loadMentionDirectories
    }
    private var retaining: Bool { state.inputLeaving || state.capsuleSealed }
    private var inputPresent: Bool {
        !state.settingsOpen && (state.inputOpen || state.inputLeaving) && interaction == nil
            && (state.inputOpen || displayedMessage == nil)
    }
    /// Settings retires the composer the moment it opens, but the face should
    /// leave from the composer seat it occupied. Holding that seat until the
    /// shell starts growing keeps the eyes from twitching down to the idle row
    /// before they travel to the panel.
    private var composerSeatHeld: Bool {
        state.settingsOpen && !state.settingsExpanded
            && (state.inputOpen || state.inputLeaving) && interaction == nil
    }
    private var composerMounted: Bool {
        guard state.dockRouteVisible, interaction == nil else { return false }
        if state.inputOpen || state.inputLeaving { return true }
        // Prepare the Overview editor at its reading width while the Bar is idle. Rich
        // drafts stay demand-loaded so a folded Bar never loads attachment previews.
        return ordinaryOverviewDock && state.windowVisible && scenePhase == .active
            && draft.inputAttachments.isEmpty && draft.inputDirectories.isEmpty
    }
    private var incomingTalk: NativeMokuTalkMessage? {
        if let presentation { return presentation.talkMessage }
        guard let talk, !talk.isEmpty else { return nil }
        return NativeMokuTalkMessage(id: JSONText(talk), text: talk)
    }
    // The Agent panel can reach Overview while its Dock mark is still turning.
    private var returningHarness: Bool {
        state.harnessSeat != nil && (state.readingPanelReturning
            || (state.overviewVisible && !state.dockCovered && !state.inputOpen && !landing))
    }
    private var visibleTalk: NativeMokuTalkMessage? {
        if returningHarness { return nil }
        guard threadID == nil, !state.inputOpen, interaction == nil, !state.dockCovered, state.dockRouteVisible,
              state.windowVisible, !disabled, !draft.submitting else { return nil }
        return state.talkPresentation.message
    }

    private var navigationDisabled: Bool { disabled && !offlineDraftEditing }
    private var landingInputAvailable: Bool {
        landing && state.overviewVisible && !state.dockCovered
            && interaction == nil && !navigationDisabled
    }
    private var rowControlAvailable: Bool {
        state.inputInteractionReady && state.dockRouteVisible && state.windowVisible && !state.dockCovered && !navigationDisabled
            && interaction == nil && !state.inputOpen && !state.inputLeaving
    }

    private var displayedMessage: NativeMokuTalkMessage? { visibleTalk }
    private var continuationPresenting: Bool {
        threadID != nil && sidecardComposer == nil && (awaitingContinuation || executionPlacement?.continuing == true)
    }
    // The outgoing draft stays open until route release. Its shell starts
    // folding when the reading panel withdraws input, alongside its ink.
    private var rowExpanded: Bool {
        (state.inputOpen && state.inputInteractionReady) || (continuationPresenting && !state.readingPanelReturning) || displayedMessage != nil
    }
    private var expanded: Bool { state.settingsExpanded || rowExpanded }
    private var capsuleFraction: CGFloat { expanded ? 1 : 0 }
    // The native replay supplies a sampling clock only for admitted reading input.
    var readingInputAnimation: Animation?
    private var surfaceAnimation: Animation? {
        if reduceMotion { return nil }
        guard state.readingPanelVisible else { return NativeMokuCapsuleLayout.overviewExpansionAnimation }
        if state.inputOpen && !rowExpanded { return .easeOut(duration: NativeReadingPageTiming.duration) }
        if let readingInputAnimation, state.inputOpen, state.inputInteractionReady { return readingInputAnimation }
        return NativeReadingPageTiming.openingAnimation
    }
    /// Centre of the resident face seat in shell-local points. The composer row
    /// carries the face with the editor; a retired composer keeps it on the row
    /// the shell's own layout reserves.
    private func faceSeatCenter(shell: CGSize, rowHeight: CGFloat,
                                       capsuleWidth: CGFloat, composerFraction: CGFloat,
                                       editorBottomInset: CGFloat, followsEditor: Bool) -> CGPoint {
        let idle = NativeMokuCapsuleLayout.idleSize
        let leading = (min(idle.width, capsuleWidth) - NativeMokuFaceLayout.seat.width) / 2 * (1 - composerFraction)
            + 15 * composerFraction
        let editorBottom = idle.height / 2 - 12.5 + (editorBottomInset - idle.height / 2) * composerFraction
        let centerY = followsEditor
            ? shell.height - editorBottom - NativeMokuFaceLayout.seat.height / 2
            : shell.height - rowHeight / 2
        let centerX = leading + NativeMokuFaceLayout.seat.width / 2
        return CGPoint(x: centerX, y: centerY)
    }

    /// Moku's face keeps its layout seat for its whole lifetime. While Settings
    /// owns the shell the same view is shifted into the page's header slot, and
    /// the shift returns to zero as the shell contracts.
    private func face(_ input: NativeMokuCharacterInput) -> some View {
        NativeMokuCharacterSurface(controller: character, input: input, seat: .face)
            .scaleEffect(landing && expanded && !state.settingsExpanded ? NativeMokuCapsuleLayout.landingScale : 1)
            .frame(width: NativeMokuFaceLayout.canvas.width, height: NativeMokuFaceLayout.canvas.height)
            .frame(width: NativeMokuFaceLayout.seat.width, height: NativeMokuFaceLayout.seat.height)
            .allowsHitTesting(false).accessibilityHidden(true)
    }

    @Environment(\.openURL) private var openURL

    private var talkLinkAction: OpenURLAction {
        OpenURLAction { url in
            if NativeMessageText.isWebURL(url) {
                openURL(url)
                return .handled
            }
            guard let reference = ApplicationExecutionLink.parse(url), let openExecution else { return .discarded }
            openExecution(reference)
            return .handled
        }
    }

    @ViewBuilder private func rowMessage(_ message: NativeMokuTalkMessage, width: CGFloat) -> some View {
        if let dispatch = message.dispatch {
            NativeMokuDispatchContent(dispatch: dispatch, harness: dispatchHarness(dispatch))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 32)
                .clipped()
                .padding(.trailing, 48)
        } else {
            // The legacy scroller occupies the trailing gutter; extend its
            // viewport so the remaining text clip stays centered in the shell.
            NativeMokuTalkContent(message: message, scrollbarStyle: talkScrollbarStyle, workspace: presentation?.workspace,
                linkedHeight: { linkedTalkHeight = $0 })
                .environment(\.openURL, talkLinkAction)
                .accessibilityIdentifier("moku-talk-content")
                .frame(width: max(1, width - NativeMokuTalkTypography.centeredInset * 2
                    + NativeMokuTalkTypography.scrollbarGutter(for: talkScrollbarStyle)),
                       height: max(0, surfaceHeight(width: width) - NativeMokuTalkTypography.verticalPadding * 2))
                .padding(.vertical, NativeMokuTalkTypography.verticalPadding)
                // Text snapshots change discretely. Interpolating the
                // native document/clip heights produces fractional
                // overflow and flashes the overlay scroller at wraps.
                // Keep the glass animation outside this transaction.
                .transaction { $0.animation = nil }
                // Resolve shell/row travel before the native viewport's discrete
                // layout. Otherwise its leaves adopt the final scene coordinates
                // while the glass is still moving.
                .geometryGroup()
                .transition(.opacity.animation(reduceMotion ? nil : .easeInOut(duration: 0.22)))
        }
    }
    private var ordinaryOverviewDock: Bool {
        state.overviewVisible && !state.readingPanelVisible && !landing && threadID == nil && sidecardComposer == nil
            && !state.dockCovered && !state.settingsOpen
            && state.talkReadingOrigin == nil && interaction == nil && displayedMessage == nil
    }
    private var overviewComposerAction: NativeOverviewComposerAction? {
        guard state.overviewVisible, !state.readingPanelVisible, threadID == nil, sidecardComposer == nil else { return nil }
        guard running, !draft.canSubmit else { return .send }
        return ordinaryOverviewDock ? .dockStop : .stop
    }
    private var stopControlPresent: Bool {
        running && !state.settingsOpen && (!inputPresent || overviewComposerAction == .dockStop)
    }
    private func stopCurrentRun() {
        // Text or an import can become ready before the old Stop target is removed.
        guard !inputPresent || overviewComposerAction != .send else { return }
        onCancel()
    }
    private var stopVisible: Bool {
        (ordinaryOverviewDock && composerVisible) || hovered || stopFocused || stopAccessibilityFocused
    }
    private func surfaceHeight(width: CGFloat) -> CGFloat {
        guard let message = displayedMessage else {
            return max(landing ? 76 : 58, capsuleHeight) + (completionVisible ? completionHeight : 0)
        }
        if message.dispatch != nil { return landing ? 76 : 58 }
        let maximumHeight = NativeMokuTalkTypography.maximumHeight
        if message.content.hasLinks {
            return max(landing ? 76 : 58, min(maximumHeight, linkedTalkHeight) + 2 * NativeMokuTalkTypography.verticalPadding)
        }
        return max(landing ? 76 : 58, NativeMokuTalkTypography.capsuleHeight(message.text, width: width,
            leadingInset: NativeMokuTalkTypography.centeredInset,
            trailingInset: NativeMokuTalkTypography.centeredInset - NativeMokuTalkTypography.scrollbarGutter(for: talkScrollbarStyle),
            maximumHeight: maximumHeight, scrollbarStyle: talkScrollbarStyle))
    }
    // The workspace retains the selected Agent while its reader returns to
    // Overview. Input is already closed to interaction during that motion.
    private var composerVisible: Bool { inputPresent && state.inputOpen && state.inputInteractionReady }
    private var conversationVisible: Bool {
        state.conversationOpen && composerVisible && threadID == nil && !state.readingPanelVisible
            && presentation?.workspace.catalog.moku != nil
    }
    private var composerCanFocus: Bool {
        state.inputInteractionReady && state.dockRouteVisible && state.inputOpen && !state.dockCovered
    }
    private var explicitFocusRequest: NativeMokuSceneState.ComposerFocusRequest? {
        guard inputPresent, composerCanFocus, state.ownsComposer(draft),
              let request = state.composerFocusRequest, request.generation == state.composerGeneration else { return nil }
        return request
    }
    private var autofocusGeneration: UUID? {
        guard inputPresent, composerCanFocus,
              state.composerAutofocus || explicitFocusGeneration == state.composerGeneration else { return nil }
        return state.composerGeneration
    }
    private var agentMentions: NativeMokuDirectoryMentions? {
        guard threadID != nil, sidecardComposer == nil, loadMentionDirectories != nil else { return nil }
        return directoryMentions
    }
    private var completionVisible: Bool { composerVisible && !retaining && agentMentions?.isOpen == true }
    private var mentionsEnabled: Bool {
        agentMentions != nil && state.dockRouteVisible && state.inputOpen && !disabled && !state.dockCovered && state.windowVisible && interaction == nil
    }
    private var showsUnreadReply: Bool {
        guard let replyKey, !state.readReplies.contains(replyKey) else { return false }
        return (presentation?.sessionIdle ?? !running) && mode == .idle
            && !state.inputOpen && interaction == nil && !state.dockCovered
    }
    private var inputSuppressesRunningFeedback: Bool {
        // Agent detail owns its persistent editor during travel and the Harness
        // flip, before inputOpen can become true. That wait is not a closed input.
        state.inputOpen || state.inputPinnedOpen
    }
    private var runningFeedback: Bool {
        guard !inputSuppressesRunningFeedback, !state.settingsOpen, interaction == nil,
              presentation?.workspace.runtimeAvailable ?? true else { return false }
        if threadID != nil, sidecardComposer == nil {
            // Submission is pending feedback only. It grants neither success,
            // Stop authority nor permission to consume the captured draft.
            // Closing input admits feedback immediately, even while the
            // retiring editor remains mounted. Open input owns its own controls.
            return (draft.submitting && draft.error == nil) || continuationPresenting || (!disabled && running && draft.error == nil)
        }
        return running && (mode == .running || incomingReasoning != nil)
            && !expanded && !inputPresent && interaction == nil
            && !disabled && (presentation?.workspace.runtimeAvailable ?? true)
    }
    private var incomingReasoning: MokuReasoningContent? {
        guard threadID == nil, running else { return nil }
        if let presentation { return presentation.reasoning }
        return reasoning
    }
    private var reasoningEligible: Bool {
        // Temporarily use the existing three-dot running expression for Moku's
        // live reasoning. Keep the source projection and Arc implementation so
        // this presentation choice does not change runtime or thread history.
        false
    }
    private var reasoningGlyphs: [MokuReasoningGlyph] {
        let incoming = incomingReasoning.map { $0.text.map { MokuReasoningGlyph(value: String($0), position: 0.5, opacity: 1) } }
            ?? retainedReasoningGlyphs
        // A FIFO may still paint an earlier, wider glyph after it leaves the
        // latest tail; keep that envelope until its actual retirement ends.
        return incoming + character.paintedReasoningGlyphs
    }
    private var eyeExpression: MokuExpression {
        if state.settingsOpen || state.inputOpen { return .focus }
        if interaction != nil { return .curious }
        if draft.submitting || running { return .deliberating }
        if showsUnreadReply { return .happy }
        return .idle
    }
    public var body: some View {
        GeometryReader { geometry in
            let viewport = state.dockViewport(in: geometry.size)
            // Keep the reading baseline; only the horizontal seat belongs to
            // the target execution column. Stacked layouts share its full width.
            let requestedFrame = state.readingPanelVisible && threadID != nil && !state.settingsOpen
                && executionPlacement?.threadID == threadID
                ? executionPlacement?.frame : nil
            let immediate = scenePhase != .active || reduceMotion
            let readingSeat = state.readingPanelVisible || returningHarness
            let holdingColumn = !expanded && (!shellIsCompact || returningHarness) && !immediate
                && inputColumn?.viewport == geometry.size && executionPlacement?.dragging != true
            let openColumn = expanded && (state.inputOpen || continuationPresenting)
                ? requestedFrame.map { InputColumn(frame: $0, viewport: geometry.size) } : nil
            let executionFrame = holdingColumn ? inputColumn?.frame : requestedFrame
            // Keep one sizing frame through the reader-to-Overview handoff.
            // A compact glass at the expanded row's origin would drift sideways.
            let sizesRow = !state.settingsOpen
            let column = executionFrame.map {
                CGRect(x: $0.minX, y: viewport.minY, width: $0.width, height: viewport.height).intersection(viewport)
            }
            let dockViewport = column.flatMap { $0.isNull || $0.isEmpty ? nil : $0 } ?? viewport
            let baseFrame = NativeMokuCapsuleLayout.frame(in: dockViewport, landing: landing,
                reading: readingSeat && !state.settingsOpen)
            let restingFrame = NativeMokuCapsuleLayout.frame(in: dockViewport, landing: landing)
            let readingOffset = baseFrame.maxY - restingFrame.maxY
            let messageWidth = displayedMessage?.dispatch != nil ? min(400, baseFrame.width) : baseFrame.width
            let frame = baseFrame.insetBy(dx: displayedMessage?.dispatch != nil ? max(0, (baseFrame.width - 400) / 2) : 0, dy: 0)
            let settingsSize = CGSize(width: min(780, max(0, viewport.width - 48)), height: min(settingsPreferredHeight, max(0, viewport.height - 48)))
            let width = state.settingsExpanded ? settingsSize.width : frame.width
            let rowHeight = rowExpanded && !state.settingsExpanded
                ? surfaceHeight(width: width) : NativeMokuCapsuleLayout.idleSize.height
            let conversationPanelHeight = min(rowHeight + conversationContentHeight, maximumConversationHeight, dockViewport.height * 0.96, frame.height)
            let conversationHeight = conversationVisible ? max(0, conversationPanelHeight - rowHeight) : 0
            let availableSurface = CGRect(x: frame.midX - width / 2,
                y: state.settingsExpanded ? viewport.minY : frame.minY,
                width: width, height: state.settingsExpanded ? viewport.height : frame.height)
            let surface = NativeMokuCapsuleLayout.surface(in: availableSurface, expanded: expanded,
                height: state.settingsExpanded ? settingsSize.height : rowHeight + conversationHeight,
                centered: landing || state.settingsExpanded)
            let arcSize = NativeMokuCapsuleLayout.idleSurface(in: viewport).size
            let arcBody = CGRect(x: surface.midX - arcSize.width / 2,
                                 y: surface.maxY - rowHeight / 2 - arcSize.height / 2,
                                 width: arcSize.width, height: arcSize.height)
            // Scale the resident as one group so the eyes, orbit and thinking
            // ink retain the ordinary capsule's proportions and shared clock.
            let residentScale = landing && !expanded && frame.width > 0 && frame.height > 0
                ? min(NativeMokuCapsuleLayout.landingScale, frame.width / max(1, surface.width), frame.height / max(1, surface.height)) : 1
            let placement = reasoningSeatReserved
                ? NativeMokuReasoningPlacement.fit(surface: surface, arcBody: arcBody, viewport: viewport,
                    glyphs: reasoningGlyphs, preferredScale: residentScale)
                : NativeMokuReasoningPlacement(surface: surface.insetBy(dx: surface.width * (1 - residentScale) / 2,
                    dy: surface.height * (1 - residentScale) / 2), scale: residentScale)
            let panel = NativeMokuCapsuleLayout.panel(in: viewport, above: placement.surface,
                                                     question: interactionIsQuestion)
            let destination = NativeMokuHorizontalDestination(offset: placement.surface.midX - geometry.size.width / 2,
                verticalOffset: readingOffset,
                frame: executionFrame, revision: executionPlacement?.travelRevision ?? 0, viewport: geometry.size,
                dragging: executionPlacement?.dragging == true, inactive: immediate,
                composer: state.composerGeneration, reading: readingSeat)
            ZStack(alignment: .topLeading) {
                capsule(width: width, room: max(58, frame.height - 18),
                    surface: surface, sizesRow: sizesRow, messageWidth: messageWidth, rowHeight: rowHeight,
                    decorationPadding: placement.decorationPadding, settingsSize: settingsSize,
                    holdsMark: returningHarness && !immediate
                        && (!shellIsCompact || (travelHost != nil && settledDestination != destination)))
                    .modifier(CapsuleSurfaceFrame(size: surface.size, sizesRow: sizesRow) { shellIsCompact = $0 })
                    .nativeCanvasNavigationRegion()
                    .nativeCanvasNavigationRegion(in: state.swipeRegions.bar)
                    .geometryGroup()
                    // Seat the native editor on the bottom edge. Animating a
                    // centre position as well as the shell height applies the
                    // destination row layout before its translation has moved,
                    // making retiring AppKit text jump vertically for a frame.
                    .scaleEffect(placement.scale, anchor: .bottom)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
                    .offset(y: placement.surface.maxY - geometry.size.height - readingOffset)
                    // Fit the shell to the column on the Sidecard's fold clock
                    // while its native host travels to the new seat.
                    .animation(executionPlacement?.dragging == true ? nil
                        : NativeSidecardTiming.foldAnimation, value: executionFrame)
                    // Text and catalog revisions only move the shell when
                    // they actually change its fitted geometry.
                    .animation(surfaceAnimation, value: placement)
                    .transaction { transaction in
                        if reduceMotion {
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                    }
                    // Keep the small reading-seat descent out of SwiftUI layout
                    // animation too: reader preparation must not stall its frames.
                    .geometryGroup()
                    .offset(y: destination.verticalOffset)
                    .animation(nil, value: destination.verticalOffset)
                    // Direct resize settles the native trip and shell together.
                    .transaction(value: geometry.size) {
                        $0.animation = nil; $0.disablesAnimations = true
                    }
                ZStack {
                    if let interaction, !state.settingsOpen {
                        interaction.padding(18)
                            .frame(width: panel.width, height: panel.height, alignment: .topLeading)
                            .nativeCanvasNavigationRegion()
                            .background { NativeMokuCapsuleGlass(interactive: false) }
                            .environment(\.colorScheme, .dark)
                            .position(x: panel.midX - destination.offset, y: panel.midY)
                            .transition(.opacity)
                    }
                }
                .mokuInk(value: interaction != nil && !state.settingsOpen)
                .mokuInk(value: interactionIsQuestion)
                .mokuInk(value: presentation?.intervention?.identity)
            }
            .coordinateSpace(name: "native-moku-dock")
            .overlay(alignment: .topLeading) {
                // Local event monitors need an attached origin, not a hit area.
                interactionMonitors(horizontalOffset: destination.offset).frame(width: 0, height: 0)
            }
            .background {
                NativeMokuHorizontalTravelCommand(destination: destination,
                    hitRects: [placement.surface.insetBy(dx: -5, dy: -5)]
                        + (interaction != nil && !state.settingsOpen ? [panel] : []),
                    onSettled: { arrived in
                        settledDestination = arrived
                        guard arrived.frame == requestedFrame,
                              state.composerGeneration == arrived.composer else { return }
                        executionPlacement?.completeTravel(revision: arrived.revision)
                    })
                    .allowsHitTesting(false)
            }
            .onChange(of: holdingColumn ? inputColumn : openColumn, initial: true) { _, column in
                inputColumn = column
            }
            .onPreferenceChange(NativeSettingsPreferredHeightKey.self) { height in
                settingsPreferredHeight = max(900, ceil(height))
            }
            .onPreferenceChange(NativeMokuConversationHeightKey.self) { conversationContentHeight = min($0, maximumConversationHeight) }
            .onPreferenceChange(NativeSettingsHeaderScrollKey.self) { offset in
                settingsHeaderScroll = offset
            }
            .onChange(of: HitLayout(surface: placement.surface, panel: panel, interaction: interaction != nil && !state.settingsOpen), initial: true) { _, layout in
                guard state.dockRouteVisible else {
                    state.dockHitRects = []
                    state.dockMentionHitRect = nil
                    return
                }
                state.capsuleFrame = layout.surface
                state.dockHitRects = [layout.surface.insetBy(dx: -5, dy: -5)]
                if layout.interaction { state.dockHitRects.append(layout.panel) }
            }
            .onChange(of: interaction != nil, initial: true) { _, visible in
                state.setDockInteractionVisible(state.dockRouteVisible && visible, question: interactionIsQuestion)
                if visible && state.dockRouteVisible && !state.settingsOpen { state.setInputOpen(false) }
                else if !visible, threadID != nil, !state.dockCovered { state.setInputOpen(true) }
            }
            .onChange(of: interactionIsQuestion) { _, value in
                state.setDockInteractionVisible(state.dockRouteVisible && interaction != nil, question: value)
            }
        }
        .nativeReadingEscape(perform: !state.inputPinnedOpen && state.inputOpen && state.dockContentVisible && interaction == nil ? {
            escapeInput()
        } : nil)
        .onChange(of: landing, initial: true) { _, active in
            guard state.updateLanding(active) else { return }
            if active {
                if landingInputAvailable && !running && incomingTalk == nil { state.setInputOpen(true) }
            } else if threadID == nil, !state.conversationOpen {
                state.retainDraft(draft)
                state.setInputOpen(false)
            }
        }
        .onChange(of: state.inputOpen, initial: true) { _, open in
            if open { state.retainDraft(draft) }
        }
        .onChange(of: ObjectIdentifier(draft)) { _, _ in
            directoryMentions = NativeMokuDirectoryMentions()
        }
        .onChange(of: state.settingsOpen) { _, open in
            if open { state.retainDraft(draft) }
            else {
                if interaction != nil {
                    state.setDockInteractionVisible(true, question: interactionIsQuestion)
                    state.setInputOpen(false)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSScroller.preferredScrollerStyleDidChangeNotification)) { _ in
            talkScrollbarStyle = NSScroller.preferredScrollerStyle
        }
        .onChange(of: incomingTalk, initial: true) { _, message in state.receiveTalk(message) }
        .onAppear {
            state.dockCharacter = character
            character.onReasoningRetired = {
                guard !reasoningRequested else { return }
                withAnimation(surfaceAnimation) { reasoningSeatReserved = false }
                retainedReasoningGlyphs = []
            }
        }
        .onChange(of: incomingReasoning, initial: true) { _, content in
            if let content {
                retainedReasoningGlyphs = content.text.map { .init(value: String($0), position: 0.5, opacity: 1) }
            }
        }
        .onChange(of: reasoningEligible, initial: true) { _, eligible in
            reasoningRequested = eligible
            reasoningTransition += 1
            let request = reasoningTransition
            if eligible {
                if reasoningSeatReserved && reasoningReady { return }
                if reasoningSeatReserved { reasoningReady = true; return }
                // Establish the space before revealing external ink. Fast reversals
                // redirect the existing SwiftUI geometry rather than snapping home.
                withAnimation(surfaceAnimation, completionCriteria: .removed) {
                    reasoningSeatReserved = true
                } completion: {
                    guard request == reasoningTransition && reasoningRequested else { return }
                    reasoningReady = true
                }
            } else {
                let hadInk = reasoningReady
                reasoningReady = false
                if !hadInk {
                    withAnimation(surfaceAnimation) { reasoningSeatReserved = false }
                }
            }
        }
        .onChange(of: visibleTalk?.id, initial: true) { _, id in
            state.setTalkPresented(id != nil)
        }
        .task(id: state.talkPresentation.deadline) {
            guard let deadline = state.talkPresentation.deadline, let id = state.talkPresentation.message?.id else { return }
            // SwiftUI cancels on replacement, dismissal and unmount. The scene
            // also fences the captured identity in case cancellation races delivery.
            do { try await ContinuousClock().sleep(until: deadline) } catch { return }
            guard !Task.isCancelled else { return }
            state.expireTalk(id: id, deadline: deadline)
        }
        .onChange(of: state.dockRouteVisible) { _, visible in
            guard !visible else { return }
            state.dockHitRects = []
            state.dockMentionHitRect = nil
            hoverTask?.cancel(); hoverTask = nil
        }
        .onChange(of: composerCanFocus) { _, available in
            if !available, !composerCanFocus {
                state.cancelComposerFocusRequest()
                focusGeneration = nil
            }
        }
        .onChange(of: explicitFocusRequest, initial: true) { _, request in
            guard let request else { return }
            if state.inputPinnedOpen { explicitFocusGeneration = request.generation }
            focusGeneration = request.generation
            focusRequest = max(focusRequest, request.key)
        }
        .onChange(of: draft.text) { _, _ in if state.dockRouteVisible && state.inputOpen { state.retainDraft(draft) } }
        .onChange(of: draft.attachments) { _, _ in if state.dockRouteVisible && state.inputOpen { state.retainDraft(draft) } }
        .onChange(of: sidecardComposer?.ready) { _, ready in
            if ready == true { focusRequest = state.nextComposerFocusKey() }
        }
        .onChange(of: draft.submitting) { _, busy in
            if !busy, sidecardComposer?.ready == true { focusRequest = state.nextComposerFocusKey() }
        }
        .onChange(of: draft.directories) { _, _ in if state.dockRouteVisible && state.inputOpen { state.retainDraft(draft) } }
        .onChange(of: state.inputOpen) { _, open in
            if open, state.overviewVisible, let replyKey { state.markReplyRead(replyKey) }
        }
        .onDisappear {
            if state.dockCharacter === character { state.dockCharacter = nil }
            character.cancelOnboardingBlink()
            character.onReasoningRetired = nil
            reasoningRequested = false; reasoningReady = false; reasoningSeatReserved = false
            reasoningTransition += 1; retainedReasoningGlyphs = []
            state.setTalkPresented(false)
            state.dockHitRects = []
            state.dockMentionHitRect = nil
            if state.dockInteractionVisible { state.setDockInteractionVisible(false, question: false) }
            hoverTask?.cancel(); hoverTask = nil
            state.cancelComposerFocusRequest()
            focusGeneration = nil
        }
        .task(id: "\(state.composerGeneration):\(mentionsEnabled)") {
            await directoryMentions.load(enabled: mentionsEnabled, using: loadMentionDirectories)
        }
        // Keep the override local: a preferredColorScheme would also recolor
        // the containing workspace window and its other application surfaces.
        .environment(\.colorScheme, .dark)
    }

    private func interactionMonitors(horizontalOffset: CGFloat) -> some View {
        ZStack {
            NativeMokuOutsideClickMonitor(
                beginClick: { state.beginOutsideClick() },
                isActive: { (state.inputOpen || (!navigationDisabled && visibleTalk != nil)) && state.dockRouteVisible && !state.dockCovered },
                preservesOwnedInteractions: state.inputOpen,
                preservedClick: { state.preserveInputForOwnedClick() },
                outsideWindowClick: visibleTalk != nil ? {
                    state.dismissTalk()
                } : nil,
                isInside: { point in
                    NativeMokuOutsideClick.isInside(point: CGPoint(x: point.x + horizontalOffset, y: point.y),
                        dockRects: state.dockHitRects)
                        || state.dockMentionHitRect?.contains(point) == true
                },
                click: { _ in
                    if state.inputPinnedOpen, agentMentions?.dismiss() == true {
                        state.preserveInputForOwnedClick()
                    }
                    else if state.inputOpen { state.dismissInputForOutsideClick() }
                    else { state.dismissTalk() }
                })
        }
        .allowsHitTesting(false)
    }

    private struct HitLayout: Equatable {
        var surface, panel: CGRect
        var interaction: Bool
    }
    private func capsule(width: CGFloat, room: CGFloat, surface: CGRect, sizesRow: Bool, messageWidth: CGFloat, rowHeight: CGFloat,
                         decorationPadding: CGFloat, settingsSize: CGSize,
                         holdsMark: Bool) -> some View {
        let composerStop = ordinaryOverviewDock && composerVisible
        // The conversation retires both message and editor ink before the eyes
        // cross the row. Keep the native draft mounted through its normal fold.
        let retiringOverviewInk = ordinaryOverviewDock && inputPresent && state.retiringInput == .composer && state.inputInteractionReady
        let followsEditor = (inputPresent && displayedMessage == nil) || composerSeatHeld || continuationPresenting
        // Settings always settles the composer expansion at 1 and retires the
        // row above the face, so the seat it lands on is known without reading
        // any animated geometry back. The face keeps its layout seat and is
        // shifted by the difference, which returns to zero as the shell
        // contracts and leaves the face exactly on Moku's row.
        let settledFace = faceSeatCenter(shell: surface.size, rowHeight: rowHeight,
                                              capsuleWidth: width,
                                              composerFraction: 1, editorBottomInset: editorBottomInset,
                                              followsEditor: false)
        // At extreme zoom the header scrolls inside the shell.
        let faceShift = state.settingsExpanded
            ? CGSize(width: NativeSettingsHeaderLayout.faceCenter.x - settledFace.x,
                     height: NativeSettingsHeaderLayout.faceCenter.y - settledFace.y - settingsHeaderScroll)
            : .zero
        let faceCenter = faceSeatCenter(shell: surface.size, rowHeight: rowHeight,
            capsuleWidth: width, composerFraction: capsuleFraction,
            editorBottomInset: editorBottomInset, followsEditor: followsEditor)
        let characterInput = NativeMokuCharacterInput(expression: eyeExpression, focus: expanded ? 1 : 0,
            running: runningFeedback, reasoning: reasoningEligible ? incomingReasoning : nil,
            presentsReasoning: reasoningEligible && reasoningReady, executionKey: threadID?.string ?? presentation?.executionKey,
            capsuleSize: CGSize(width: surface.width, height: rowHeight), cornerRadius: NativeMokuCapsuleLayout.cornerRadius,
            // Settings covers the Dock but keeps the face on screen in the page's
            // header, so its blink and expression keep their clock.
            motion: scenePhase == .active && state.windowVisible && (!state.dockCovered || state.settingsOpen),
            dark: true, immediateOrbit: threadID != nil)
        return Color.clear
        .frame(width: sizesRow ? nil : surface.width, height: sizesRow ? nil : surface.height)
        .overlay(alignment: .bottom) {
            ZStack {
                if composerMounted {
                    composer(room: room, compact: width < 260)
                        // Reflow native text once at the destination width. Resolve
                        // the shell's movement outside that discrete layout so its
                        // editor cannot jump to the final scene-space position.
                        .frame(width: width).fixedSize(horizontal: false, vertical: true)
                        .transaction(value: width) { $0.animation = nil }
                        .geometryGroup()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { capsuleHeight = max(58, $0) }
                        .animation(nil) { $0.opacity(composerVisible || retiringOverviewInk ? 1 : 0) }
                        .allowsHitTesting(composerVisible)
                        .disabled(!state.inputOpen || state.settingsOpen || !state.inputInteractionReady)
                        .accessibilityHidden(!composerVisible)
                        // A route can replace the draft or unmount the entire row
                        // before it receives the hidden state. An implicit removal
                        // fade would keep the outgoing text in the shrinking shell.
                        .id(ObjectIdentifier(draft))
                        .transition(.identity)
                }
            }
            // Keep the overlay's footprint through the empty-to-mounted change.
            // An intrinsic size starting at zero also animates the text origin.
            .frame(width: width, height: capsuleHeight, alignment: .bottom)
            .geometryGroup()
            // A dispatch row is already expanded when Compose replaces it.
            // Its width cannot drive the usual compact-to-editor ink reveal.
            .animation(reduceMotion ? nil : .mokuInk) {
                $0.modifier(NativeMokuHandoffInk(progress: displayedMessage?.dispatch == nil ? 1 : 0))
            }
            .modifier(ComposerInk(expansion: capsuleFraction, autofocusGeneration: autofocusGeneration) { generation in
                guard autofocusGeneration == generation, state.ownsComposer(draft),
                      explicitFocusRequest == nil, focusGeneration != generation else { return }
                focusGeneration = generation
                focusRequest = state.nextComposerFocusKey()
            })
        }
        .onChange(of: completionVisible) { _, visible in
            if !visible { state.dockMentionHitRect = nil }
        }
        .overlay(alignment: .bottom) {
            ZStack {
                if conversationVisible, let presentation, let owner = presentation.workspace.catalog.moku?.id {
                    let viewport = CGSize(width: width, height: max(0, surface.height - rowHeight))
                    NativeMokuConversation(presentation: presentation, owner: owner, readingSize: viewport)
                        .environment(\.openURL, talkLinkAction)
                        .id(owner)
                        // Keep the reading viewport seated above the editor as the shell moves.
                        .transaction { $0.animation = nil }
                        .clipped()
                        .padding(.bottom, rowHeight)
                        .transition(.identity)
                }
            }
            // Hide any outgoing layout before the folding shell can carry it
            // across the input row, including when a Talk occupies that row.
            .opacity(conversationVisible ? 1 : 0)
            .animation(nil, value: conversationVisible)
        }
        .overlay(alignment: .top) {
            if completionVisible, let agentMentions {
                NativeMokuComposerCompletion(mentions: agentMentions, draft: draft,
                    maxHeight: max(0, room - capsuleHeight - 12),
                    onFrame: { state.dockMentionHitRect = completionVisible ? $0 : nil })
                    .disabled((disabled && !offlineDraftEditing) || draft.clearing || draft.isDisposed)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { completionHeight = $0 }
                    // Resolve the menu's target height once. The shell animates;
                    // the editor and its persistent face share the bottom edge.
                    .transaction { $0.animation = nil }
                    .transition(.asymmetric(insertion: .opacity.animation(reduceMotion ? nil : .mokuInk), removal: .identity))
            }
        }
        .overlay(alignment: .bottomLeading) {
            if rowControlAvailable && !inputPresent {
                Button { state.toggleInput(focusOnOpening: true) } label: {
                    Color.clear
                        .frame(width: displayedMessage == nil ? surface.width : 46, height: rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Leave selectable message prose and the later control overlays
                // their own hit targets; only the eyes open input beside a message.
                .padding(.leading, displayedMessage == nil ? 0 : max(0, faceCenter.x - 23))
                .accessibilityLabel(localize("打开 Chief 输入框", "Open Chief input"))
                .accessibilityIdentifier("moku-open-input")
            }
        }
        .overlay(alignment: .top) {
            if state.settingsOpen {
                settingsContent
                    .frame(width: settingsSize.width, height: settingsSize.height)
                    // Settle the page layout during the capsule morph without
                    // suppressing animations initiated later by its children.
                    .transaction(value: state.settingsExpanded) { $0.animation = nil }
                    .compositingGroup()
                    .opacity(state.settingsExpanded ? 1 : 0)
                    .animation(.easeOut(duration: state.settingsClosing ? 0.12 : 0.22), value: state.settingsExpanded)
                    // Resolve placement with the shell's animation, outside both
                    // the faster ink fade and the page's discrete layout. Without
                    // this boundary the page jumps to the collapsed Dock's origin.
                    .geometryGroup()
                    .disabled(state.settingsClosing)
                    .allowsHitTesting(!state.settingsClosing)
                    .accessibilityHidden(state.settingsClosing)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let message = displayedMessage {
                rowMessage(message, width: messageWidth)
                    .opacity(!state.settingsOpen ? 1 : 0)
                    .allowsHitTesting(!state.settingsOpen)
                    .accessibilityHidden(state.settingsOpen)
                    .frame(height: rowHeight)
                    .padding(.leading, message.dispatch == nil ? NativeMokuTalkTypography.centeredInset : NativeMokuTalkTypography.leading)
                    .transition(message.dispatch == nil ? .opacity : .asymmetric(
                        insertion: .opacity,
                        removal: .modifier(active: NativeMokuHandoffInk(progress: 0),
                                           identity: NativeMokuHandoffInk(progress: 1))
                            .animation(reduceMotion ? nil : .mokuInk)))
            }
        }
        .overlay(alignment: .bottomLeading) {
            // The resident travels with the bottom row. Its local offset must
            // stay independent of the height of the shell opening above it.
            let generation = state.composerGeneration
            let returning = state.readingPanelReturning
            let showsHarness = threadID != nil && !state.settingsOpen && !returning
            NativeMokuDockIdentity(state: state, harness: threadHarness,
                showsHarness: showsHarness, holdsMark: holdsMark,
                entranceReady: state.inputAdmissionReady, generation: generation,
                animation: state.windowVisible && !reduceMotion
                    ? NativeReadingPageTiming.openingAnimation : nil,
                onSettled: { state.completeInputIdentity(generation: generation) }) {
                face(characterInput)
            }
                .onChange(of: returning) { _, returning in
                    if returning, threadID != nil { state.retireInputIdentity(generation: generation) }
                }
                .geometryGroup()
                .offset(x: faceCenter.x + faceShift.width - NativeMokuFaceLayout.seat.width / 2,
                        y: faceCenter.y + faceShift.height - surface.height + NativeMokuFaceLayout.seat.height / 2)
        }
        .overlay(alignment: .bottomTrailing) {
            // Keep the footer layout alive across insertion and retirement.
            // Match the open editor’s trailing action, including multiline and two-row layouts.
            HStackLayout(spacing: 4) {
                let visible = stopControlPresent && stopVisible
                RoundedRectangle(cornerRadius: 1).fill(.foreground).frame(width: 10, height: 10)
                    .animation(reduceMotion ? nil : .mokuInk) { $0.opacity(visible ? 1 : 0) }
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                    .geometryGroup()
                    .frame(width: composerStop ? 32 : 30, height: composerStop ? 32 : 30)
                    .overlay {
                        if stopControlPresent {
                            Button(action: stopCurrentRun) {
                                Color.clear.contentShape(Circle())
                            }.buttonStyle(.plain)
                                .disabled(disabled || (ordinaryOverviewDock && inputPresent &&
                                    (!composerVisible || draft.submitting || draft.clearing || draft.isDisposed)))
                                .accessibilityHidden(ordinaryOverviewDock && inputPresent && !composerVisible)
                                .focused($stopFocused)
                                .accessibilityFocused($stopAccessibilityFocused)
                                .allowsHitTesting(stopVisible && (!inputPresent || composerVisible))
                                .help(threadID == nil ? localize("停止 Chief", "Stop Chief") : localize("停止此 Thread", "Stop this thread"))
                                .accessibilityLabel(threadID == nil ? localize("停止 Chief", "Stop Chief") : localize("停止此 Thread", "Stop this thread"))
                                .accessibilityIdentifier("moku-stop")
                                .nativeCanvasNavigationRegion(in: state.swipeRegions.controls)
                                .transition(.identity)
                        }
                    }
            }
            .padding(.trailing, composerStop ? NativeMokuComposerInput.actionTrailingInset : 7)
            .frame(height: composerStop ? 2 * editorBottomInset : rowHeight)
        }
        .background {
            ZStack {
                NativeMokuCapsuleGlass(regular: conversationVisible)
                    .opacity(state.settingsExpanded ? 0 : 1)
                if state.settingsOpen {
                    NativeSettingsPanelBackground()
                        .opacity(state.settingsExpanded ? 1 : 0)
                }
            }
        }.clipShape(RoundedRectangle(cornerRadius: NativeMokuCapsuleLayout.cornerRadius))
        .overlay(alignment: .bottom) {
            // Orbit ink lives outside the glass; never include it in the capsule clip.
            NativeMokuCharacterSurface(controller: character, input: characterInput, seat: .decorations)
                .frame(width: surface.width + decorationPadding * 2, height: rowHeight + decorationPadding * 2)
                .offset(y: decorationPadding)
                // Also hide the character's retiring ink as soon as detail owns
                // input, including entry from running Moku and rapid replacement.
                .opacity(inputSuppressesRunningFeedback ? 0 : 1)
                .animation(nil, value: inputSuppressesRunningFeedback)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: NativeMokuCapsuleLayout.cornerRadius)).onHover(perform: updateHover)
        .animation(reduceMotion ? nil : .mokuInk) {
            $0.shadow(color: .black.opacity(0.13), radius: hovered ? 17 : 13, y: 6)
        }
        .nativeCanvasNavigationRegion()
        // In detail, only Dock focus may use this close route. A window-sized
        // fallback would race the reader's nested history/Sidecard cancellation.
        .nativeReadingEscape(perform: state.inputPinnedOpen && state.inputOpen && state.dockContentVisible && interaction == nil ? {
            escapeInput()
        } : nil)
        .accessibilityElement(children: .contain).accessibilityLabel(state.settingsOpen ? localize("设置", "Settings") : "Chief")
        .accessibilityHint(state.settingsOpen || !state.inputInteractionReady ? "" :
            state.overviewVisible && rowControlAvailable
                ? localize("点击输入，右键查看聊天记录",
                           "Click to type or right-click for messages")
                : localize("点击打开输入框", "Click to type"))
        .accessibilityIdentifier("moku-capsule")
    }

    private func dispatchHarness(_ dispatch: NativeMokuDispatch) -> AnyHarnessPlugin? {
        try? presentation?.workspace.plugins.harnesses.require(dispatch.harnessID)
    }
    private func escapeInput() {
        guard state.ownsComposer(draft) else { return }
        if state.inputPinnedOpen {
            // Editor key handling arrives after IME/completion, but AppKit can
            // still address an anchor while a native transient owns Escape.
            guard let window = NSApp.currentEvent?.window ?? NSApp.keyWindow,
                  window.attachedSheet == nil, NSApp.modalWindow == nil,
                  !(window.childWindows ?? []).contains(where: { $0.isVisible && $0.canBecomeKey }) else { return }
            if agentMentions?.dismiss() == true { return }
            if let sidecardComposer { sidecardComposer.cancel() }
            else { onThreadClose?() }
        }
        else { _ = state.dismissInputForEscape() }
    }
    private func composer(room: CGFloat, compact: Bool) -> some View {
        let mentions = agentMentions
        // The ink reveal owns only automatic acquisition. An admitted
        // editor must accept clicks/Tab without a delayed update blurring it.
        return NativeMokuComposerInput(draft: draft, cwd: cwd, disabled: disabled,
            awaitingContinuation: sidecardComposer == nil && awaitingContinuation,
            targetsThread: threadID != nil, sidecardComposer: sidecardComposer,
            readOnly: state.inputLeaving, focusEnabled: composerCanFocus && (sidecardComposer?.ready ?? true),
            automaticFocus: false,
            // Keep the Compose key through the input's lifetime so installing
            // the editor in a later layout pass still sees the same request.
            focusRequestKey: max(explicitFocusRequest?.key ?? 0,
                focusGeneration == state.composerGeneration ? focusRequest : 0),
            suppressInitialFocus: !state.composerAutofocus,
            onFocusRequestAcquired: state.composerDidAcquireFocus,
            maxHeight: min(landing ? 156 : 126, room), landing: landing, compact: compact,
            retainedText: retaining ? state.retainedText : nil,
            retainedAttachments: retaining ? state.retainedAttachments : nil,
            retainedDirectories: retaining ? state.retainedDirectories : nil,
            running: running, onCancel: stopCurrentRun,
            overviewAction: overviewComposerAction,
            selectionRequest: mentions?.selectionRequest,
            initialSelection: state.selectionForReopening(text: retaining ? state.retainedText : draft.text),
            onEditorStateChange: { editor in
                guard state.ownsComposer(draft) else { return }
                if state.inputOpen, editor.focused, !editor.composing,
                   editor.text.utf16.elementsEqual(draft.text.utf16) {
                    state.retainSelection(editor.selection, text: editor.text)
                }
                mentions?.update(editor)
            },
            onKeyDown: mentions.map { completion in
                { state.ownsComposer(draft) && completion.handle($0, draft: draft) }
            },
            onEditorSeatChange: state.ownsComposer(draft) && state.inputOpen ? { editorBottomInset = $0 } : nil,
            onEscape: escapeInput, onSend: send)
    }

    private func send() {
        guard state.ownsComposer(draft), !state.settingsOpen, !disabled, state.inputOpen, draft.canSubmit else { return }
        guard sidecardComposer?.ready ?? true else { return }
        // The retiring capsule is a sealed projection, independent of the live
        // draft. Seal the empty snapshot directly on a fold.
        let fold = !state.conversationOpen
        if fold {
            state.retainedText = ""; state.retainedAttachments = []; state.retainedDirectories = []
            state.capsuleSealed = !state.inputPinnedOpen
            state.setInputOpen(false)
        }
        if threadID == nil { state.dismissTalk() }
        let sendingDraft = draft, send = onSend, consumed = onSendConsumed, generation = state.composerGeneration
        // Capture and project the submitted input in this event, before another
        // keystroke can change the payload. The receipt can arrive on a later visit.
        Task.immediate {
            await sendingDraft.submit(send, optimisticallyClear: true, didConsume: consumed)
            if fold, state.composerGeneration == generation, sendingDraft.error != nil {
                state.setInputOpen(true)
            }
        }
    }
    private func updateHover(_ active: Bool) {
        hoverTask?.cancel(); hoverTask = nil
        if active { hovered = true }
        else {
            hoverTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                hovered = false
            }
        }
    }
    private func localize(_ zh: String, _ en: String) -> String { locale.language.languageCode?.identifier == "zh" ? zh : en }
}
