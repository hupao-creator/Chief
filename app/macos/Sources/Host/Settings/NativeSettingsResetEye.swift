import AppKit
import SwiftUI

extension EnvironmentValues {
    @Entry public var requestFactoryReset: (@MainActor () -> Void)?
}

/// Hit target for the existing resident eyes. The page owns the target so
/// scrolling the header or leaving Settings retires the same press.
struct NativeSettingsResetEye: NSViewRepresentable {
    @Environment(\.isEnabled) private var enabled
    let label: String
    let request: () -> Void

    func makeNSView(context: Context) -> Eye { Eye() }
    func updateNSView(_ view: Eye, context: Context) {
        view.request = enabled ? request : nil
        if !enabled { view.cancelHold() }
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        view.setAccessibilityLabel(label)
        view.setAccessibilityIdentifier("settings-reset-eye")
    }

    final class Eye: NSView {
        var request: (() -> Void)?
        private var hold: Task<Void, Never>?
        private var tracking: Any?

        override func mouseDown(with event: NSEvent) {
            cancelHold()
            guard request != nil, window?.isKeyWindow == true, !event.modifierFlags.contains(.control) else { return }
            let origin = event.locationInWindow
            // A drag across a neighboring SwiftUI control can leave this
            // AppKit view's responder path. Track the original physical press.
            tracking = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp, .keyDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if event.type == .leftMouseUp || (event.type == .keyDown && event.keyCode == 53) {
                        self.cancelHold()
                    } else if event.type == .leftMouseDragged {
                        if event.window !== self.window || !self.inside(event.locationInWindow) { self.cancelHold() }
                    }
                }
                return event
            }
            hold = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard let self, let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor,
                      inside(origin) else { return }
                cancelHold()
                request?()
            }
        }
        override func mouseDragged(with event: NSEvent) {
            if !inside(event.locationInWindow) { cancelHold() }
        }
        override func mouseUp(with event: NSEvent) { cancelHold() }
        override func mouseCancelled(with event: NSEvent) { cancelHold() }
        override func scrollWheel(with event: NSEvent) {
            cancelHold()
            super.scrollWheel(with: event)
        }
        private func inside(_ point: NSPoint) -> Bool {
            bounds.intersection(visibleRect).contains(convert(point, from: nil))
        }
        @objc fileprivate func cancelHold() {
            hold?.cancel()
            hold = nil
            if let tracking { NSEvent.removeMonitor(tracking); self.tracking = nil }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            cancelHold()
            if let window { NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window) }
            if let newWindow {
                NotificationCenter.default.addObserver(self, selector: #selector(cancelHold),
                    name: NSWindow.didResignKeyNotification, object: newWindow)
            }
            super.viewWillMove(toWindow: newWindow)
        }
    }
}
