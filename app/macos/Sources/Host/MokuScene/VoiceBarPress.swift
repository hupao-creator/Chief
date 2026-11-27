import AppKit
import SwiftUI

/// One pointer owner prevents releasing a recognized hold from opening the editor.
/// The native editor, Send button and text selection keep their ordinary mouse events.
struct VoiceBarPress: NSViewRepresentable {
    enum Area: Equatable {
        case bar(reservesStop: Bool)
        case identity(center: CGPoint)
    }
    let area: Area?
    let route: UUID
    let tip: String?
    let start, click: @MainActor () -> Void

    func makeNSView(context: Context) -> PressView {
        let view = PressView()
        view.identifier = .init("voice-bar-frame")
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: PressView, context: Context) {
        if view.route != route || area == nil { view.cancel() }
        view.route = route
        view.area = area
        view.start = start
        view.click = click
        view.toolTip = tip
    }

    static func dismantleNSView(_ view: PressView, coordinator: ()) { view.cancel() }

    final class PressView: NSView {
        var route: UUID?
        var area: Area?
        var start, click: (@MainActor () -> Void)?
        private var down: NSEvent?
        private var hold: Task<Void, Never>?
        private var recognized = false

        override var mouseDownCanMoveWindow: Bool { false }
        override var acceptsFirstResponder: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard !isHiddenOrHasHiddenAncestor, let superview,
                  accepts(convert(point, from: superview)) else { return nil }
            if let event = NSApp.currentEvent, event.modifierFlags.contains(.control)
                || event.type == .rightMouseDown || event.type == .rightMouseUp {
                return nil
            }
            return self
        }

        private func accepts(_ point: CGPoint) -> Bool {
            let radius = min(bounds.height / 2, NativeMokuCapsuleLayout.cornerRadius)
            guard NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).contains(point) else { return false }
            switch area {
            case .bar(let reservesStop): return !reservesStop || point.x < bounds.maxX - 44
            case .identity(let center):
                return abs(point.x - center.x) <= 23 && abs(point.y - center.y) <= 23
            case nil: return false
            }
        }

        override func mouseDown(with event: NSEvent) {
            cancel()
            guard !event.modifierFlags.contains(.control) else { return }
            down = event
            hold = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let self, down != nil, window?.isKeyWindow == true else { return }
                recognized = true
                start?()
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard continues(event) else { cancel(); return }
        }

        override func mouseUp(with event: NSEvent) {
            let accepted = !recognized && continues(event)
            let held = down.map { event.timestamp - $0.timestamp >= 0.5 } == true
            cancel()
            guard accepted else { return }
            if held { start?() } else { click?() }
        }

        private func continues(_ event: NSEvent) -> Bool {
            guard let origin = down?.locationInWindow, window != nil, event.window === window else { return false }
            let point = event.locationInWindow
            return hypot(point.x - origin.x, point.y - origin.y) <= 10 && accepts(convert(point, from: nil))
        }

        override func mouseCancelled(with event: NSEvent) { cancel() }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if let window { NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window) }
            cancel()
            super.viewWillMove(toWindow: newWindow)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                NotificationCenter.default.addObserver(self, selector: #selector(resignedKey(_:)),
                    name: NSWindow.didResignKeyNotification, object: window)
            }
        }

        @objc private func resignedKey(_ notification: Notification) { cancel() }

        func cancel() {
            hold?.cancel()
            hold = nil
            down = nil
            recognized = false
        }
    }
}
