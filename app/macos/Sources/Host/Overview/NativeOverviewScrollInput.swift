import ChiefPluginUI
import SwiftUI
import AppKit

/// AppKit supplies signed content motion and any inertia. Precise gestures
/// contribute only their horizontal component. A single-axis mouse wheel
/// uses its line delta to move along the same horizontal scroll range.
enum NativeOverviewScrollGeometry {
    static func distance(x: Double, y: Double, precise: Bool, pointsPerWindowPoint: Double) -> Double? {
        guard x.isFinite, y.isFinite, pointsPerWindowPoint.isFinite, pointsPerWindowPoint > 0 else { return nil }
        let delta = precise ? x : (x == 0 ? y : x) * 40
        let distance = -delta * pointsPerWindowPoint
        return distance.isFinite ? distance : nil
    }
}

/// Routing only: the camera remains the sole owner of transforms.
struct NativeOverviewScrollSequence {
    enum Owner { case canvas, native, discarded }
    enum Stage { case idle, direct, awaitingMomentum, momentum }
    private(set) var owner: Owner?
    private(set) var stage = Stage.idle
    private var endedAt = 0.0

    mutating func interrupt() {
        if owner == .canvas { owner = .discarded }
    }
    mutating func reset() { owner = nil; stage = .idle }

    /// nil means native dispatch, canvas means apply once, discarded means swallow.
    mutating func route(phase: NSEvent.Phase, momentum: NSEvent.Phase, hasDelta: Bool,
                        candidate: Owner, now: Double) -> Owner? {
        if !momentum.isEmpty {
            guard let owner, stage != .idle else { return nil }
            // An ended direct sequence may be followed by system inertia. Never
            // acquire orphan momentum, even when the pointer is over the canvas.
            if stage == .awaitingMomentum && now - endedAt > 0.25 { reset(); return nil }
            stage = .momentum
            if momentum.contains(.ended) || momentum.contains(.cancelled) { reset() }
            return owner
        }
        if phase.isEmpty {
            reset() // Phase-less wheels are independent events, never latched.
            return hasDelta ? candidate : nil
        }
        if phase.contains(.mayBegin) { return nil }
        if phase.contains(.began) || stage == .awaitingMomentum || stage == .momentum { reset() }
        if owner == nil, hasDelta { owner = candidate; stage = .direct }
        let result = owner
        if phase.contains(.cancelled) { reset() }
        else if phase.contains(.ended), owner != nil { stage = .awaitingMomentum; endedAt = now }
        return result
    }
}

/// Transparent geometry/lifecycle anchor, never a hit target or first responder.
/// A local monitor also sees events above SwiftUI's semantic card subviews.
struct NativeOverviewScrollInput: NSViewRepresentable {
    @Environment(\.reminderScrollRegions) private var reminderScrollRegions
    @Environment(\.overviewNoteAction) private var noteAction
    var regions: NativeCanvasInputRegions
    var size: CGSize
    var toolbarBottom: Double
    var identity: String
    var enabled: () -> Bool
    var scroll: (Double) -> Void

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MonitorView, context: Context) -> CGSize? { size }

    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) {
        let geometry = Configuration(size: size, toolbarBottom: toolbarBottom, identity: identity)
        if view.configuration != geometry { view.cancelSequence(); view.configuration = geometry }
        view.noteAction = noteAction
        view.reminderScrollRegions = reminderScrollRegions
        view.regions = regions
        view.enabled = enabled; view.scroll = scroll
        if !enabled() { view.cancelSequence() }
    }
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    struct Configuration: Equatable {
        var size: CGSize
        var toolbarBottom: Double
        var identity: String
    }

    @MainActor final class MonitorView: NSView {
        var configuration = Configuration(size: .zero, toolbarBottom: 0, identity: "")
        weak var reminderScrollRegions: NativeCanvasInputRegions?
        weak var regions: NativeCanvasInputRegions?
        var enabled: () -> Bool = { false }
        var scroll: (Double) -> Void = { _ in }
        var sequence = NativeOverviewScrollSequence()
        var noteAction: NativeOverviewNoteAction?
        private var noteSwipe = NativeMokuSwipeSequence()
        private var monitor: Any?
        private var observers: [NSObjectProtocol] = []
        private var requiresNewSequence = false
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        // Convert a pair of window points rather than dividing by camera scale,
        // backingScaleFactor or an assumed SwiftUI/AppKit zoom convention.
        var canvasPerWindowPoint: CGFloat? {
            guard bounds.width > 0, bounds.height > 0, configuration.size.width > 0,
                  configuration.size.height > 0 else { return nil }
            let a = convert(CGPoint.zero, from: nil), b = convert(CGPoint(x: 1, y: 1), from: nil)
            return abs(b.x - a.x) * configuration.size.width / bounds.width
        }
        func canvasPoint(_ point: CGPoint) -> CGPoint {
            let local = convert(point, from: nil)
            return CGPoint(x: (local.x - bounds.minX) * configuration.size.width / bounds.width,
                           y: (local.y - bounds.minY) * configuration.size.height / bounds.height)
        }
        func windowPoint(_ point: CGPoint) -> CGPoint {
            convert(CGPoint(x: bounds.minX + point.x * bounds.width / configuration.size.width,
                            y: bounds.minY + point.y * bounds.height / configuration.size.height), to: nil)
        }
        func canStart(at point: CGPoint) -> Bool {
            guard enabled(), let window, window.isVisible,
                  !isHiddenOrHasHiddenAncestor, bounds.width > 0, bounds.height > 0,
                  point.x.isFinite, point.y.isFinite,
                  CGRect(origin: .zero, size: configuration.size).contains(point),
                  point.y >= configuration.toolbarBottom,
                  NSEvent.pressedMouseButtons == 0 else { return false }
            let location = windowPoint(point)
            guard bounds.intersection(visibleRect).contains(convert(location, from: nil)),
                  reminderScrollRegions?.contains(location, in: window) != true,
                  regions?.contains(location, in: window) != true else { return false }
            // Public AppKit fallback for native editors/embedded scrolling views.
            guard let content = window.contentView else { return false }
            let hitPoint = content.superview?.convert(location, from: nil) ?? location
            var target = content.hitTest(hitPoint)
            while let current = target {
                if current is NSScrollView || current is NSTextView { return false }
                target = current.superview
            }
            return true
        }

        /// Called by the local monitor; exposed internally for window-level replays.
        func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window else { return event }
            if event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown {
                interruptGestures(); return event
            }
            guard event.type == .scrollWheel else { return event }
            // Note and camera share this monitor so a child viewport or the
            // canvas cannot consume a qualifying swipe before Note sees it.
            if let noteAction, let content = window.contentView,
               noteSwipe.route(event, eligible: window.isVisible
                && reminderScrollRegions?.contains(event.locationInWindow, in: window) != true
                && content.bounds.contains(content.convert(event.locationInWindow, from: nil))
                && event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
                && NSEvent.pressedMouseButtons == 0 && noteAction.available(), open: noteAction.open) {
                sequence.reset()
                return nil
            }
            guard enabled(), window.isVisible, !isHiddenOrHasHiddenAncestor else {
                cancelSequence(); return event
            }
            let modified = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            guard !modified, let factor = canvasPerWindowPoint,
                  let distance = NativeOverviewScrollGeometry.distance(x: event.scrollingDeltaX, y: event.scrollingDeltaY,
                    precise: event.hasPreciseScrollingDeltas, pointsPerWindowPoint: factor) else { cancelSequence(); return event }
            let hasDelta = event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0
            let directStart = event.phase.contains(.began) || (event.phase.isEmpty && event.momentumPhase.isEmpty)
            if directStart { requiresNewSequence = false }
            if event.phase.contains(.mayBegin) {
                sequence.reset(); requiresNewSequence = false
                return event
            }
            if requiresNewSequence {
                guard sequence.owner == .discarded else { return event }
                let owner = sequence.route(phase: event.phase, momentum: event.momentumPhase, hasDelta: hasDelta,
                    candidate: .discarded, now: event.timestamp)
                return owner == .discarded ? nil : event
            }
            let candidate: NativeOverviewScrollSequence.Owner = canStart(at: canvasPoint(event.locationInWindow))
                ? .canvas : .native
            if NSEvent.pressedMouseButtons != 0 { sequence.interrupt() }
            let owner = sequence.route(phase: event.phase, momentum: event.momentumPhase, hasDelta: hasDelta,
                candidate: candidate, now: event.timestamp)
            switch owner {
            case .canvas:
                if distance != 0 { scroll(distance) }
                return nil
            case .discarded: return nil
            default: return event
            }
        }
        func cancelSequence() {
            sequence.interrupt(); requiresNewSequence = true
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            // Allow a first changed event (some devices omit began) on mounting.
            requiresNewSequence = false
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self else { return false }
                    return self.handle(event) == nil
                }
                return consumed ? nil : event
            }
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        if name == NSWindow.willCloseNotification { self?.stop() }
                        else { self?.interruptGestures() }
                    }
                })
            }
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                object: NSApp, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.interruptGestures() }
                })
        }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow !== window { stop() }
            super.viewWillMove(toWindow: newWindow)
        }
        private func interruptGestures() {
            noteSwipe = NativeMokuSwipeSequence()
            cancelSequence()
        }
        func stop() {
            interruptGestures()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
        }
    }
}
