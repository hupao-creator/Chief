import AppKit
import SwiftUI

struct NativeOverviewTagSpaceKeys: NSViewRepresentable {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.layoutDirection) private var layoutDirection
    let step: (_ forward: Bool) -> Bool

    func makeNSView(context: Context) -> KeyView { KeyView() }

    func updateNSView(_ view: KeyView, context: Context) {
        view.handle = enabled ? { right in step(right == (layoutDirection == .leftToRight)) } : nil
    }

    static func dismantleNSView(_ view: KeyView, coordinator: ()) { view.removeMonitor() }

    final class KeyView: NSView {
        var handle: ((_ right: Bool) -> Bool)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { removeMonitor(); return }
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    guard let self, let handle = self.handle, let window = self.window, event.window === window,
                          window.isKeyWindow, !self.isHiddenOrHasHiddenAncestor,
                          window.attachedSheet == nil, NSApp.modalWindow == nil,
                          event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command, .shift],
                          (window.firstResponder as? NSTextView)?.isEditable != true,
                          (window.firstResponder as? NSTextInputClient)?.hasMarkedText() != true else { return false }

                    // Shift commonly produces braces. Use the current input source's
                    // Command layer without Shift to recognize its bracket keys.
                    let typed = event.characters
                    let bracket = typed == "[" || typed == "]" ? typed : event.characters(byApplyingModifiers: .command)
                    switch bracket {
                    case "[": return handle(false)
                    case "]": return handle(true)
                    default: return false
                    }
                }
                return handled ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        }
    }
}
