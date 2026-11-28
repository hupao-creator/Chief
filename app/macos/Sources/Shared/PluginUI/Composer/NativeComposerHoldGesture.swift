import AppKit

/// Stay possible until release so a later drag can still give the original
/// mouse-down back to AppKit's text selection tracker.
final class NativeComposerHoldGesture: NSGestureRecognizer {
    private var origin: NSEvent?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        origin = event
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        if !isStationary(event) { state = .failed }
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard let origin, isStationary(event), event.timestamp - origin.timestamp >= 0.5 else {
            state = .failed
            return
        }
        state = .recognized
    }

    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        state = .failed
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        if !event.modifierFlags.intersection([.control, .shift, .option, .command]).isEmpty {
            state = .failed
        }
    }

    override func mouseCancelled(with event: NSEvent) {
        super.mouseCancelled(with: event)
        state = .failed
    }

    override func reset() {
        super.reset()
        origin = nil
    }

    private func isStationary(_ event: NSEvent) -> Bool {
        guard let origin, let view, let window = view.window, window.isKeyWindow,
              event.window === window else { return false }
        let point = event.locationInWindow
        return hypot(point.x - origin.locationInWindow.x, point.y - origin.locationInWindow.y) <= 3
            && view.visibleRect.contains(view.convert(point, from: nil))
    }
}
