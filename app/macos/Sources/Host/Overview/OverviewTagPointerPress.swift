import AppKit
import SwiftUI

/// One pointer owner chooses click or hold on release. The SwiftUI button
/// underneath remains available to keyboard and accessibility activation.
struct OverviewTagPointerPress: NSViewRepresentable {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.overviewSwipeActions) private var swipeActions
    let onClick: () -> Void
    let onHold: () -> Void

    func makeNSView(context: Context) -> PressView { PressView() }

    func updateNSView(_ view: PressView, context: Context) {
        view.swipeRegions = swipeActions?.regions
        view.enabled = enabled
        view.onClick = onClick
        view.onHold = onHold
        if !enabled { view.cancelPress() }
    }

    static func dismantleNSView(_ view: PressView, coordinator: ()) { view.cancelPress() }

    final class PressView: NSView {
        weak var swipeRegions: NativeOverviewSwipeRegions?
        var enabled = true
        var onClick: () -> Void = {}
        var onHold: () -> Void = {}
        private var down: NSEvent?
        private var monitor: Any?
        private var resignObserver: NSObjectProtocol?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard enabled, !isHiddenOrHasHiddenAncestor,
                  contains(superview.map { convert(point, from: $0) } ?? point) else { return nil }
            return self
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            cancelPress()
            super.viewWillMove(toWindow: newWindow)
        }

        override func mouseDown(with event: NSEvent) {
            guard enabled, let window, !event.modifierFlags.contains(.control) else { return }
            cancelPress()
            down = event
            swipeRegions?.pressedTag = self
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated {
                    if let self, event.window === self.window, event.keyCode == 53 { self.cancelPress() }
                }
                return event
            }
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.cancelPress() }
                }
        }

        override func mouseDragged(with event: NSEvent) {
            if down != nil && !continuesPress(event) { cancelPress() }
        }

        override func mouseCancelled(with event: NSEvent) { cancelPress() }

        override func scrollWheel(with event: NSEvent) {
            if event.momentumPhase.isEmpty { cancelPress() }
            super.scrollWheel(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            guard let started = down else { return }
            let inside = continuesPress(event)
            cancelPress()
            guard inside else { return }
            if event.timestamp - started.timestamp >= 0.5 { onHold() }
            else { onClick() }
        }

        func cancelPress() {
            if swipeRegions?.pressedTag === self { swipeRegions?.pressedTag = nil }
            down = nil
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
        }

        private func continuesPress(_ event: NSEvent) -> Bool {
            guard enabled, let down, !isHiddenOrHasHiddenAncestor else { return false }
            let start = down.locationInWindow
            let point = event.locationInWindow
            return hypot(point.x - start.x, point.y - start.y) <= 10 && contains(convert(point, from: nil))
        }

        private func contains(_ point: NSPoint) -> Bool {
            let radius = min(bounds.width, bounds.height) / 2
            return NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).contains(point)
        }
    }
}
