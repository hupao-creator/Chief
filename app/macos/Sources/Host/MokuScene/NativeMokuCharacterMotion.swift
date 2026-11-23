import AppKit
import QuartzCore
import SwiftUI

/// Semantic targets and source admission are separate. Covering a live thinking
/// segment retires its painted glyphs without making a hidden reader consume text.
struct NativeMokuCharacterInput: Equatable {
    var expression: MokuExpression
    var focus: Double
    var running: Bool
    var reasoning: MokuReasoningContent?
    var presentsReasoning: Bool
    var executionKey: String?
    var capsuleSize: CGSize
    var cornerRadius: CGFloat
    var motion: Bool
    var dark: Bool
    var immediateOrbit = false

    func changesOnlyCompactExpression(from previous: Self?) -> Bool {
        guard let previous, previous.expression != expression, focus == 0, !running, !presentsReasoning,
              [.idle, .curious, .happy].contains(previous.expression),
              [.idle, .curious, .happy].contains(expression) else { return false }
        var sameExpression = self
        sameExpression.expression = previous.expression
        return previous == sameExpression
    }
}

struct NativeMokuCharacterPose {
    var values: [String: Double]
    subscript(_ key: String) -> Double {
        get { values[key, default: 0] }
        set { values[key] = newValue }
    }
    func map(_ transform: (String) -> Double) -> Self {
        Self(values: Dictionary(uniqueKeysWithValues: values.keys.map { ($0, transform($0)) }))
    }
    func eye(_ side: String) -> MokuEye {
        MokuEye(x: self[side + "x"], y: self[side + "y"], w: max(1, self[side + "w"]),
                h: max(1, self[side + "h"]), radius: max(0, self[side + "r"]),
                rotation: self[side + "a"], opacity: 1)
    }
}

/// The face and decorations share one logical clock. An eye-only transition
/// can run on the resident layers until a new role needs the display link.
@MainActor final class NativeMokuCharacterMotion: NSObject {
    private(set) var input: NativeMokuCharacterInput?
    private(set) var reasoningAnimation = MokuReasoningAnimation()
    private var frameClock = 0.0
    private var expressionPlayback: (start: CFTimeInterval, bounds: CGRect)?
    var clock: Double {
        guard let playback = expressionPlayback else { return frameClock }
        // Time spent settled must not become motion on the next handoff.
        return min(transitionAt + duration, frameClock + max(0, CACurrentMediaTime() - playback.start) * 1000)
    }
    private var framePose = NativeMokuCharacterPose(values: [:])
    var pose: NativeMokuCharacterPose { expressionPlayback == nil ? framePose : sample(at: clock) }
    private(set) var frameCount = 0
    private(set) var retiredGlyphs: [MokuReasoningGlyph] = []
    private var arcSize = CGSize.zero
    private var from = NativeMokuCharacterPose(values: [:])
    private var velocity = NativeMokuCharacterPose(values: [:])
    private var transitionAt = 0.0
    private var duration = 0.0
    private var runningElapsed = 0.0
    private var orbitGeometry: NativeMokuRunningGeometry?
    private var orbitElapsed = 0.0
    private var orbitVisibility = 0.0
    private(set) var orbitDots: [MokuRunningFrame.Dot] = []
    var orbitOpacity: Double { MokuRunningStory.smooth(orbitVisibility) }
    private var lastWall = ProcessInfo.processInfo.systemUptime
    private var replacementAt = -Double.infinity
    private var replacementGlyphs: [MokuReasoningGlyph] = []
    private var link: CADisplayLink?
    private weak var linkView: NativeMokuCharacterCanvas?
    private weak var face: NativeMokuCharacterCanvas?
    private weak var decorations: NativeMokuCharacterCanvas?
    private var wasVisible = false
    private var retirementPending = false
    private var stationaryTarget: NativeMokuCharacterPose?
    private(set) var onboardingBlinkStart: Date?
    private var firstIdleBlink: Date?
    var onReasoningRetired: (() -> Void)?

    var paintedReasoningGlyphs: [MokuReasoningGlyph] { reasoningAnimation.glyphs + retiredGlyphs + replacementGlyphs }
    var isTransitioning: Bool { clock < transitionAt + duration }
    var hasScheduledFrame: Bool { link?.isPaused == false && visible }
    private var visible: Bool {
        input?.motion == true
            && (face?.motionVisible == true || decorations?.motionVisible == true)
    }

    func attach(_ view: NativeMokuCharacterCanvas) {
        if view.seat == .face { stopExpression(); face = view } else { decorations = view }
        visibilityChanged()
    }
    func detach(_ view: NativeMokuCharacterCanvas) {
        if face === view { stopExpression(); face = nil }
        if decorations === view { decorations = nil }
        visibilityChanged()
    }

    func configure(_ next: NativeMokuCharacterInput) {
        guard input != next else { return }
        let previous = input
        let eyesAlone = expressionPlayback != nil || !isTransitioning
        stopExpression()
        let previousPose = previous == nil ? nil : sample(at: clock)
        let previousVelocity = previousPose.map { before in
            let after = sample(at: clock + 0.01)
            return before.map { (after[$0] - before[$0]) / 0.01 }
        }
        let wasThinking = previous?.presentsReasoning == true
        let isThinking = next.presentsReasoning && next.reasoning != nil
        if wasThinking && !isThinking {
            retiredGlyphs = reasoningAnimation.glyphs
            retirementPending = true
        }
        if isThinking { retirementPending = false }
        if wasThinking && isThinking, let oldReasoning = reasoningAnimation.content,
           let newReasoning = next.reasoning, !oldReasoning.sharesSegment(with: newReasoning) {
            replacementGlyphs = reasoningAnimation.glyphs; replacementAt = clock
        }
        if previous?.executionKey != next.executionKey {
            runningElapsed = 0
            replacementGlyphs = []
            // A new execution cannot restore a retired source from the old one.
            if isThinking { retiredGlyphs = [] }
        }
        if next.running, next.immediateOrbit,
           previous?.running != true || previous?.executionKey != next.executionKey {
            // Direct-send eyes skip the opening three beats of the gaze choreography.
            runningElapsed = MokuRunningStory.beatMS * 1.22
        }
        if next.running, previous?.running != true || previous?.capsuleSize != next.capsuleSize
            || previous?.cornerRadius != next.cornerRadius {
            orbitGeometry = NativeMokuRunningGeometry(size: next.capsuleSize, cornerRadius: next.cornerRadius)
        }
        input = next
        stationaryTarget = nil
        if isThinking { arcSize = next.capsuleSize }
        let track = NativeMokuReasoningArcTrack(body: CGRect(origin: .zero, size: next.capsuleSize))
        reasoningAnimation.configure(next.reasoning, length: track.length,
                                     animated: isThinking)
        let changed = previous.map { old in
            old.expression != next.expression || old.focus != next.focus || old.running != next.running
                || old.presentsReasoning != next.presentsReasoning || old.capsuleSize != next.capsuleSize
                || old.cornerRadius != next.cornerRadius || old.executionKey != next.executionKey
        } ?? true
        if changed {
            from = previousPose ?? target(at: clock)
            velocity = previousVelocity ?? from.map { _ in 0 }
            transitionAt = clock
            duration = previous == nil ? 0
                : (previous?.running != next.running || wasThinking != isThinking ? 550 : 420)
        }
        framePose = sample(at: clock)
        // Compact reminders and interventions change only the two resident
        // eyes. A moving shell, orbit or retiring decoration keeps the shared
        // display clock, including when it interrupts one of these expressions.
        if eyesAlone, orbitVisibility == 0, next.changesOnlyCompactExpression(from: previous), !retirementPending, replacementGlyphs.isEmpty,
           next.motion, let face, face.motionVisible, !face.bounds.isEmpty, let slope = expressionSlope() {
            if let start = face.blinkLayers?.playExpression(in: face.bounds,
                ink: (next.dark ? NSColor.white : NSColor.black).cgColor,
                firstBlink: onboardingBlinkStart ?? firstIdleBlink, duration: duration / 1000, slope: slope, pose: {
                    sample(at: transitionAt + duration * $0)
                }) {
                expressionPlayback = (start, face.bounds)
            }
        }
        decorations?.needsDisplay = true
        visibilityChanged()
    }

    /// A common cubic can carry both eyes when their incoming velocity lies
    /// along the new path. A three-way interruption can turn each component
    /// differently and continues on the shared display clock.
    private func expressionSlope() -> Double? {
        let destination = target(at: transitionAt + duration)
        let keys = destination.values.keys.filter { $0.hasPrefix("l") || $0.hasPrefix("r") }
        guard let key = keys.max(by: { abs(destination[$0] - from[$0]) < abs(destination[$1] - from[$1]) }),
              abs(destination[key] - from[key]) > 0.000001 else { return nil }
        let slope = duration * velocity[key] / (destination[key] - from[key])
        return keys.allSatisfy { abs(duration * velocity[$0] - slope * (destination[$0] - from[$0])) < 0.000001 }
            ? slope : nil
    }

    private func stopExpression() {
        guard expressionPlayback != nil else { return }
        frameClock = clock
        expressionPlayback = nil
        framePose = sample(at: frameClock)
        face?.blinkLayers?.stopExpression()
    }

    private var canPlayOnboardingBlink: Bool {
        NSApp.isActive && input?.motion == true && face?.motionVisible == true
    }

    func scheduleOnboardingBlink(at start: Date) {
        guard firstIdleBlink == nil, canPlayOnboardingBlink else { return }
        stopExpression()
        onboardingBlinkStart = start
        firstIdleBlink = start.addingTimeInterval(NativeMokuCapsuleBlinkTiming.interval)
        visibilityChanged()
    }

    func cancelOnboardingBlink() {
        guard onboardingBlinkStart != nil else { return }
        onboardingBlinkStart = nil
        visibilityChanged()
    }

    func visibilityChanged() {
        let now = Date.now
        // Latch loss of the original face here. Its AppKit hide and unhide can both
        // arrive before SwiftUI next configures the Dock.
        if let start = onboardingBlinkStart,
           !canPlayOnboardingBlink || now >= start.addingTimeInterval(NativeMokuCapsuleBlinkTiming.duration) {
            onboardingBlinkStart = nil
        }
        let active = visible
        if let playback = expressionPlayback, !active || face?.motionVisible != true || face?.bounds != playback.bounds {
            stopExpression()
        }
        if expressionPlayback == nil, let input, let face {
            face.blinkLayers?.update(left: pose.eye("l"), right: pose.eye("r"), bounds: face.bounds,
                                    ink: (input.dark ? NSColor.white : NSColor.black).cgColor,
                                    active: active && face.motionVisible, first: onboardingBlinkStart ?? firstIdleBlink)
        }
        if active != wasVisible { lastWall = ProcessInfo.processInfo.systemUptime; wasVisible = active }
        guard active, let anchor = face ?? decorations else {
            link?.isPaused = true
            if input?.presentsReasoning != true, retirementPending {
                retiredGlyphs = []; finishRetirement()
            }
            if face == nil && decorations == nil {
                link?.invalidate(); link = nil; linkView = nil
                retiredGlyphs = []; replacementGlyphs = []
            }
            decorations?.needsDisplay = true
            return
        }
        if linkView !== anchor {
            link?.invalidate()
            link = anchor.displayLink(target: self, selector: #selector(displayFrame(_:)))
            link?.isPaused = true
            linkView = anchor
            link?.add(to: .main, forMode: .common)
        }
        let moving = input?.running == true || orbitVisibility > 0 || (expressionPlayback == nil && isTransitioning)
            || (input?.presentsReasoning == true && reasoningAnimation.needsFrames)
            || retirementPending || (!replacementGlyphs.isEmpty && clock - replacementAt < 220)
        // Sleeping between role changes must not advance the next transition.
        if moving && link?.isPaused != false { lastWall = ProcessInfo.processInfo.systemUptime }
        link?.isPaused = !moving
    }

    @objc private func displayFrame(_ displayLink: CADisplayLink) {
        guard visible else { visibilityChanged(); return }
        guard expressionPlayback == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = max(0, min(64, (now - lastWall) * 1000)); lastWall = now
        advanceFrame(milliseconds: dt)
    }

    func advanceFrame(milliseconds dt: Double) {
        frameClock += dt
        if let orbitGeometry {
            // A reversal retraces the fade from its presented opacity. The
            // decoration clock belongs to visible ink, even after execution ends.
            orbitVisibility = MokuRunningStory.clamp(orbitVisibility + (input?.running == true ? dt : -dt) / 550)
            if input?.running == true || orbitVisibility > 0 {
                orbitElapsed += dt
                orbitDots = orbitGeometry.dots(milliseconds: orbitElapsed)
            } else {
                orbitElapsed = 0
                orbitDots = []
                self.orbitGeometry = nil
            }
        }
        if input?.running == true { runningElapsed += dt }
        if input?.presentsReasoning == true { reasoningAnimation.advance(milliseconds: dt) }
        framePose = sample(at: clock)
        if !isTransitioning && input?.presentsReasoning != true {
            retiredGlyphs = []; finishRetirement()
        }
        if clock - replacementAt >= 220 { replacementGlyphs = [] }
        frameCount += 1
        decorations?.needsDisplay = true
        // Submit the final open-eye / retired-ink frame before sleeping.
        visibilityChanged()
    }

    private func finishRetirement() {
        guard retirementPending else { return }
        retirementPending = false
        // Configuration can run inside NSViewRepresentable.updateNSView. Let
        // SwiftUI finish that update before releasing the reserved arc seat.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.input?.presentsReasoning != true else { return }
            self.onReasoningRetired?()
        }
    }

    private func sample(at time: Double) -> NativeMokuCharacterPose {
        let target = target(at: time)
        guard duration > 0, time < transitionAt + duration else { return target }
        let p = max(0, min(1, (time - transitionAt) / duration))
        let blend = p * p * (3 - 2 * p)
        let tangent = p * p * p - 2 * p * p + p
        return target.map { from[$0] + (target[$0] - from[$0]) * blend + velocity[$0] * duration * tangent }
    }

    private func target(at time: Double) -> NativeMokuCharacterPose {
        guard let input else { return .init(values: [:]) }
        let running = input.running
        if !running, let stationaryTarget { return stationaryTarget }
        let thinking = input.presentsReasoning && input.reasoning != nil
        let gaze = running ? MokuRunningStory.sample(time: (runningElapsed + time - clock) / MokuRunningStory.beatMS).eyes
            : MokuRunningFrame.Eyes()
        let eyes = NativeMokuCapsuleEyes.resolved(expression: running ? .idle : input.expression, focus: running ? 0 : input.focus)
        var result = NativeMokuCharacterPose(values: ["arcAlpha": thinking ? 1 : 0,
                                                       "arcGather": thinking ? 0 : 1, "arcReveal": thinking ? 1 : 0])
        for (side, eye) in [("l", eyes.left), ("r", eyes.right)] {
            result[side + "x"] = eye.x + gaze.x * 0.12 / 0.22
            result[side + "y"] = eye.y * gaze.scaleY + gaze.y * 0.12 / 0.22
            result[side + "w"] = eye.w; result[side + "h"] = eye.h * gaze.scaleY
            result[side + "r"] = eye.radius; result[side + "a"] = eye.rotation
        }
        if !running { stationaryTarget = result }
        return result
    }

    func paintDecorations(in context: CGContext, bounds: CGRect) {
        guard let input else { return }
        let pose = self.pose
        context.saveGState(); defer { context.restoreGState() }
        context.saveGState()
        context.setAlpha(orbitOpacity)
        for dot in orbitDots {
            context.setFillColor(dot.color.cgColor)
            context.fillEllipse(in: CGRect(x: bounds.midX + dot.x - 2.5,
                y: bounds.midY + dot.y - 2.5, width: 5, height: 5))
        }
        context.restoreGState()
        let size = input.presentsReasoning ? input.capsuleSize : arcSize
        let track = NativeMokuReasoningArcTrack(body: CGRect(x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2, width: size.width, height: size.height))
        let replacement = max(0, min(1, (clock - replacementAt) / 220))
        let current = input.presentsReasoning ? reasoningAnimation.glyphs : retiredGlyphs
        NativeMokuReasoningArcPainter.paint(glyphs: current, track: track, in: context, dark: input.dark,
            opacity: pose["arcAlpha"] * (replacementGlyphs.isEmpty ? 1 : replacement),
            gather: pose["arcGather"], reveal: pose["arcReveal"])
        if !replacementGlyphs.isEmpty {
            NativeMokuReasoningArcPainter.paint(glyphs: replacementGlyphs, track: track, in: context, dark: input.dark,
                opacity: pose["arcAlpha"] * (1 - replacement), gather: pose["arcGather"], reveal: pose["arcReveal"])
        }
    }
}

enum NativeMokuCharacterSeat { case face, decorations }

struct NativeMokuCharacterSurface: NSViewRepresentable {
    let controller: NativeMokuCharacterMotion
    let input: NativeMokuCharacterInput
    let seat: NativeMokuCharacterSeat
    func makeNSView(context: Context) -> NativeMokuCharacterCanvas {
        NativeMokuCharacterCanvas(controller: controller, seat: seat)
    }
    func updateNSView(_ view: NativeMokuCharacterCanvas, context: Context) { controller.configure(input) }
    static func dismantleNSView(_ view: NativeMokuCharacterCanvas, coordinator: ()) { view.detach() }
}

/// Passive drawing seats share one controller. AppKit owns display pacing and
/// stops its link when the view leaves the display; no fixed-rate sampler exists.
@MainActor final class NativeMokuCharacterCanvas: NSView {
    let controller: NativeMokuCharacterMotion
    let seat: NativeMokuCharacterSeat
    fileprivate let blinkLayers: NativeMokuBlinkLayers?
    private var observers: [NSObjectProtocol] = []
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    var motionVisible: Bool {
        !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty && window?.isMiniaturized == false
            && window?.occlusionState.contains(.visible) == true
    }
    init(controller: NativeMokuCharacterMotion, seat: NativeMokuCharacterSeat) {
        self.controller = controller; self.seat = seat
        blinkLayers = seat == .face ? NativeMokuBlinkLayers() : nil
        super.init(frame: .zero)
        wantsLayer = true; clipsToBounds = false; layer?.masksToBounds = false
        if let layer { blinkLayers?.install(in: layer) }
        setAccessibilityElement(false)
        controller.attach(self)
    }
    required init?(coder: NSCoder) { nil }
    isolated deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func detach() { blinkLayers?.stop(); controller.detach(self) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        if let window {
            if seat == .face {
                observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                    object: NSApp, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.controller.cancelOnboardingBlink() }
                })
            }
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.controller.visibilityChanged() }
                })
            }
        }
        controller.visibilityChanged()
    }
    override func viewDidHide() { super.viewDidHide(); controller.visibilityChanged() }
    override func viewDidUnhide() { super.viewDidUnhide(); controller.visibilityChanged() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); controller.visibilityChanged(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if seat == .decorations { controller.paintDecorations(in: context, bounds: bounds) }
    }
}
