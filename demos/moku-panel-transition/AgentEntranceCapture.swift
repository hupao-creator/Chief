import AppKit
import ChiefPluginUI
import SwiftUI
@testable import ChiefUI

/// Evaluate the production easing on a uniform source grid. Keep each step
/// on screen for multiple refreshes so a busy capture can still observe it.
struct HeldOpeningFrames: CustomAnimation {
    static let sourceFPS = 60.0
    static let secondsPerStep = 0.1
    let base = NativeReadingPageTiming.openingAnimation

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        let step = floor(time / Self.secondsPerStep)
        return base.animate(value: value, time: step / Self.sourceFPS, context: &context)
    }
}

enum CaptureOpeningClock: String {
    case heldFrames = "agent"
    case realtime

    var settleDelay: Duration {
        let duration = NativeReadingPageTiming.duration
        let end = self == .heldFrames
            ? ceil(duration * HeldOpeningFrames.sourceFPS) * HeldOpeningFrames.secondsPerStep : duration
        return .seconds(end + 0.13)
    }
}

/// Record responder and fixture phase in the same window as the composer ink.
@MainActor final class CollapseCapturePanel: ComposerReplayPanel {
    private let focusMarker = CALayer()
    private let phaseMarker = CALayer()

    func installCaptureMarkers() {
        guard let contentView else { return }
        contentView.wantsLayer = true
        focusMarker.frame = CGRect(x: 20, y: 100, width: 24, height: 24)
        focusMarker.zPosition = 1
        contentView.layer?.addSublayer(focusMarker)
        phaseMarker.backgroundColor = NSColor.blue.cgColor
        phaseMarker.zPosition = 1
        contentView.layer?.addSublayer(phaseMarker)
        markPhase(0)
        updateFocusMarker()
    }

    // The blue tile occupies one 12pt lane beside the responder marker. Move
    // it in the action's own transaction so the movie carries its boundaries.
    func markPhase(_ index: Int) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        phaseMarker.frame = CGRect(x: 64 + 12 * index, y: 106, width: 8, height: 12)
        CATransaction.commit()
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let accepted = super.makeFirstResponder(responder)
        updateFocusMarker()
        return accepted
    }

    private func updateFocusMarker() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusMarker.backgroundColor = (firstResponder is NSTextView ? NSColor.green : .red).cgColor
        CATransaction.commit()
    }
}

private struct CollapseCaptureError: Error, CustomStringConvertible {
    let description: String
}

@MainActor func captureAgentEntrance(window: CollapseCapturePanel, scene: NativeMokuSceneState, overviewDraft: NativeComposerDraft,
                                enterAgent: (String, NativeComposerDraft, CaptureOpeningClock) -> Void, closeAgent: () -> Void,
                                setCentered: (Bool) -> Void, publishTalk: (String) -> Void) async throws {
    let agentDraft = NativeComposerDraft(services: .init(stageFiles: { _, _ in [] }, discardAttachments: { _ in }))
    let text = "草稿 🦉 stays in Overview.\nThe second line stays too."
    let selection = NSRange(location: 3, length: 2)
    let talk = NativeMokuTalkMessage(id: "Moku reply stays readable after closing input.", text: "Moku reply stays readable after closing input.")
    let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
    func pause(_ milliseconds: Int) async throws { try await Task.sleep(for: .milliseconds(milliseconds)) }
    func editors(in view: NSView) -> [NSTextView] {
        (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap { editors(in: $0) }
    }
    func require(_ condition: Bool, _ failure: String) throws {
        guard condition else { throw CollapseCaptureError(description: failure) }
    }

    guard let content = window.contentView else { throw CollapseCaptureError(description: "Replay content unavailable") }
    let movie = try await DockMovieCapture(window: window, folder: "agent-entrance")
    let start = ContinuousClock.now
    var events: [[String: Any]] = []
    var nextPhase = 0
    func event(_ name: String, beginsPhase: Bool = false) {
        let elapsed = start.duration(to: .now).components
        var row: [String: Any] = [
            "event": name, "seconds": Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
            "shellWidth": scene.capsuleFrame.width, "shellHeight": scene.capsuleFrame.height,
            "inputOpen": scene.inputOpen, "inputLeaving": scene.inputLeaving,
            "editorText": editors(in: content).map(\.string), "editorSelection": editors(in: content).map {
                NSStringFromRange($0.selectedRange())
            }, "talkPresented": scene.talkPresentation.presented
        ]
        if beginsPhase {
            row["phase"] = nextPhase
            window.markPhase(nextPhase)
            nextPhase += 1
        }
        events.append(row)
    }

    // Exercise frames already submitted to WindowServer while the reader's
    // main thread cannot perform another layout. The movie has its own clock.
    func holdMainThread(_ phase: String) {
        event(phase, beginsPhase: true)
        CATransaction.flush()
        Thread.sleep(forTimeInterval: 0.12)
        event(phase + "-released", beginsPhase: true)
    }

    func waitForAgentInput() async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !scene.inputOpen && .now < deadline { try await pause(10) }
        try require(scene.inputOpen, "Column travel or Harness admission did not finish")
    }

    func travelView(_ view: NSView) -> MokuHorizontalTravelView? {
        if let travel = view as? MokuHorizontalTravelView { return travel }
        return view.subviews.lazy.compactMap(travelView).first
    }
    guard let travel = travelView(content) else { throw CollapseCaptureError(description: "Missing Dock carrier") }
    func waitForReturn() async throws {
        let deadline = ContinuousClock.now + .seconds(4)
        while !scene.overviewVisible, .now < deadline { try await pause(10) }
        // Allow AppKit to commit the new destination before sampling its layer.
        try await pause(60)
        while travel.presentationCorrection != .zero, .now < deadline { try await pause(10) }
        try require(scene.overviewVisible && travel.presentationCorrection == .zero, "Dock did not reach Overview")
    }

    func captureAgentVisits(_ clock: CaptureOpeningClock) async throws {
        let phase = clock.rawValue
        for (index, title) in ["短标题", "修复发送后的输入竞态与草稿丢失，检查很长的目标执行标题"].enumerated() {
            event("\(phase)-enter-\(index)", beginsPhase: true)
            enterAgent(title, agentDraft, clock)
            try await waitForAgentInput()
            event("\(phase)-expanding-\(index)", beginsPhase: true)
            try await Task.sleep(for: clock.settleDelay)
            guard let column = scene.executionDockPlacement.frame else {
                throw CollapseCaptureError(description: "Agent column is missing")
            }
            try require(column.midX > content.bounds.midX && editors(in: content).count == 1,
                        "Agent did not open in the right column")
            event("\(phase)-open-\(index)", beginsPhase: true)
            try await pause(100) // Record a distinct settled phase before issuing Close.
            closeAgent()
            event("\(phase)-close-\(index)", beginsPhase: true)
            // Capture both the retained reading panel's return and the Dock's
            // subsequent trip to idle before driving another visit.
            try await waitForReturn()
            try require(scene.overviewVisible && !scene.inputOpen && !scene.inputLeaving, "Agent return did not settle")
            try require(scene.capsuleFrame.size == NativeMokuCapsuleLayout.idleSize, "Incorrect idle shell size")
            event(clock == .heldFrames ? "overview-closed-\(index)" : "realtime-idle-\(index)")
        }
    }

    var failure: String?
    do {
        event("idle", beginsPhase: true)
        try await pause(350)
        scene.toggleInput(focusOnOpening: true)
        try await pause(80)
        try require(scene.dismissInputForOutsideClick(), "Shortcut entrance did not close")
        try await pause(80)
        scene.toggleInput(focusOnOpening: true)
        event("shortcut-reopen")
        // Send the first key through the non-key panel's responder chain
        // during the ordinary ink transition, before waiting for settled ink.
        let focusDeadline = ContinuousClock.now + .milliseconds(180)
        while !(window.firstResponder is NSTextView), ContinuousClock.now < focusDeadline {
            try await pause(5)
        }
        guard let firstKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0) else {
            throw CollapseCaptureError(description: "First key event unavailable")
        }
        window.sendEvent(firstKey)
        try require(overviewDraft.text == "a", "The first key after Compose reopening missed the Overview editor")
        event("shortcut-first-key")
        overviewDraft.text = ""
        try require(window.makeFirstResponder(nil), "Could not move focus out of the editor")
        try await pause(650)
        try require(!(window.firstResponder is NSTextView), "The ink reveal retook focus after it moved")
        event("shortcut-focus-released")
        try require(scene.dismissInputForOutsideClick(), "Shortcut replay did not return to Overview")
        try await pause(650)

        try await captureAgentVisits(.heldFrames)

        event("interrupted-open", beginsPhase: true)
        scene.toggleInput()
        try await pause(80)
        try require(scene.dismissInputForOutsideClick(), "Interrupted entrance did not close")
        event("interrupted-close", beginsPhase: true)
        try await pause(80)
        try require(!(window.firstResponder is NSTextView), "Interrupted entrance kept editor focus")
        scene.toggleInput()
        event("interrupted-reopen", beginsPhase: true)
        try await pause(650)
        event("interrupted-settled")
        guard let editor = editors(in: content).first(where: { $0.isEditable }),
              window.firstResponder === editor else {
            throw CollapseCaptureError(description: "Overview editor unavailable")
        }
        // Exercise NSTextInputClient across a SwiftUI update before closing.
        // The system input-source picker and candidate window are outside this replay.
        let currentSelection = NSRange(location: NSNotFound, length: 0)
        event("overview-edit", beginsPhase: true)
        editor.setMarkedText("cao", selectedRange: NSRange(location: 3, length: 0), replacementRange: currentSelection)
        try await pause(100)
        try require(editor.hasMarkedText() && editor.string == "cao" && scene.inputOpen,
                    "A composer update interrupted native marked text")
        event("marked-text")
        editor.insertText("草稿", replacementRange: currentSelection)
        editor.insertText(" 🦉 stays in Overview.\nThe second line stays too.", replacementRange: currentSelection)
        try require(!editor.hasMarkedText() && editor.string == text && overviewDraft.text == text,
                    "Committing marked text or subsequent typing lost the draft")
        editor.setSelectedRange(selection)
        event("draft-open")
        try require(scene.dismissInputForOutsideClick(), "Outside dismissal was rejected")
        event("draft-close", beginsPhase: true)
        try await pause(85)
        event("draft-leaving")
        try require(scene.inputLeaving && editors(in: content).contains(where: { $0 === editor }) && !editor.isEditable,
                    "Closing did not retain a noneditable editor")
        scene.toggleInput()
        event("draft-reopen", beginsPhase: true)
        try await pause(650)
        event("draft-reopened")
        try require(scene.inputOpen && !scene.inputLeaving && editors(in: content).contains(where: { $0 === editor })
                    && window.firstResponder === editor && editor.isEditable && editor.string == text && editor.selectedRange() == selection,
                    "Rapid reopening lost the editor, draft or UTF-16 selection")

        publishTalk(talk.text)
        try await pause(120)
        try require(scene.talkPresentation.message == talk && !scene.talkPresentation.presented, "Talk did not queue behind the open draft")
        try require(scene.dismissInputForOutsideClick(), "Second outside dismissal was rejected")
        event("close-to-talk", beginsPhase: true)
        let talkDeadline = ContinuousClock.now + .milliseconds(650)
        while !scene.talkPresentation.presented, .now < talkDeadline { try await pause(8) }
        try require(scene.talkPresentation.presented, "Queued Talk did not reach the offscreen panel")
        // This click belongs to another window in this process. A mouse-transparent
        // recording panel must keep its Talk while the user works elsewhere.
        let other = NSPanel(contentRect: .init(x: -20000, y: -20000, width: 32, height: 32),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: other.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else {
                throw CollapseCaptureError(description: "Could not create a window-local outside press")
            }
            NSApp.postEvent(event, atStart: false)
        }
        try await ContinuousClock().sleep(until: talkDeadline)
        withExtendedLifetime(other) {}
        event("talk-visible")
        try require(!scene.inputOpen && !scene.inputLeaving && overviewDraft.text == text
                    && scene.talkPresentation.presented && scene.talkPresentation.message == talk,
                    "Closing lost the draft or failed to present queued Talk")
        // Check automatic acquisition for both titles on the unscaled clock too.
        try await captureAgentVisits(.realtime)
        setCentered(true)
        for i in 0..<2 {
            event("center-enter-\(i)", beginsPhase: true)
            enterAgent("中央输入框", agentDraft, .realtime)
            try await waitForAgentInput()
            event("center-expanding-\(i)", beginsPhase: true)
            if i == 1 {
                try await pause(125)
                holdMainThread("center-busy-opening")
            }
            try await pause(630)
            try require(scene.inputOpen && editors(in: content).count == 1, "Centered editor did not mount")
            event("center-open-\(i)", beginsPhase: true)
            try await pause(100)
            closeAgent()
            event("center-close-\(i)", beginsPhase: true)
            if i == 1 {
                try await pause(125)
                holdMainThread("center-busy-folding")
                await scene.waitForReturningEyes()
                try await pause(100)
                holdMainThread("center-busy-panel-return")
            }
            try await waitForReturn()
            try require(scene.overviewVisible && !scene.inputOpen && !scene.inputLeaving, "Centered return did not settle")
        }
        setCentered(false)
        for axis in ["horizontal", "vertical"] {
            event("interrupt-\(axis)-visit", beginsPhase: true)
            enterAgent("重新展开", agentDraft, .realtime)
            try await waitForAgentInput()
            try await pause(550)
            closeAgent()
            event("interrupt-\(axis)-close", beginsPhase: true)
            let deadline = ContinuousClock.now + .seconds(4)
            func midReturn() -> Bool {
                let point = travel.presentationCorrection
                return scene.overviewVisible && (axis == "horizontal"
                    ? point.x > 30 && point.x < 180 : point.y > 3 && point.y < 12)
            }
            while !midReturn(), .now < deadline { try await pause(5) }
            try require(midReturn(), "Missing in-flight \(axis) return")
            event("interrupt-\(axis)-reopen", beginsPhase: true)
            enterAgent("重新展开", agentDraft, .realtime)
            try await waitForAgentInput()
            try await pause(650)
            let mounted = editors(in: content)
            try require(mounted.count == 1 && mounted[0].isEditable && window.firstResponder === mounted[0]
                        && mounted[0].convert(mounted[0].bounds, to: content).midX > content.bounds.midX
                        && travel.presentationCorrection == .zero, "Interrupted return displaced the reopened input")
            closeAgent()
            try await waitForReturn()
        }
        // A pinned Compose command is an explicit request even during entrance.
        event("explicit-enter", beginsPhase: true)
        enterAgent("显式聚焦", agentDraft, .realtime)
        try await waitForAgentInput()
        try require(!(window.firstResponder is NSTextView), "Editor already focused before Compose")
        scene.toggleInput()
        event("explicit-compose", beginsPhase: true)
        try await pause(550)
        try require(window.firstResponder is NSTextView, "Explicit Compose did not acquire the editor")
        event("explicit-settled", beginsPhase: true)
        try await pause(100) // Let the terminal marker reach the recording before sealing it.
    } catch {
        failure = String(describing: error)
    }
    try await movie.finish()
    let foregroundUnchanged = foreground == NSWorkspace.shared.frontmostApplication?.processIdentifier
    if failure == nil && !foregroundUnchanged { failure = "Foreground application changed during capture" }
    try JSONSerialization.data(withJSONObject: ["events": events, "foregroundUnchanged": foregroundUnchanged,
        "geometrySourceFPS": HeldOpeningFrames.sourceFPS, "geometrySecondsPerStep": HeldOpeningFrames.secondsPerStep,
        "failure": failure as Any? ?? NSNull()], options: [.prettyPrinted, .sortedKeys])
        .write(to: movie.directory.appendingPathComponent("observations.json"), options: .atomic)
    if let failure { throw CollapseCaptureError(description: failure) }
}
