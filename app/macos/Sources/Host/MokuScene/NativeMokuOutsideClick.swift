import SwiftUI
import AppKit

/// Boundary for the Dock's outside-click dismissal. Coordinates are local
/// to the Dock's flipped scene, so they match the frames it publishes for the
/// capsule, composer and interaction panel.
enum NativeMokuOutsideClick {
    static func isInside(point: CGPoint, dockRects: [CGRect]) -> Bool {
        guard point.x.isFinite, point.y.isFinite else { return true }
        // The Dock publishes these during layout. Until it has, never turn a
        // missing frame into a dismissal of the user's open composer.
        guard !dockRects.isEmpty else { return true }
        return dockRects.contains { $0.contains(point) }
    }
}

/// Observes clicks without consuming them. A full-window SwiftUI overlay would
/// make thread cards and chrome controls unclickable while the composer is
/// open; the local monitor leaves the original event on its normal path.
/// Talk also observes other windows/apps. The global observer
/// cannot consume events and exists only while that dismissal callback is installed.
struct NativeMokuOutsideClickMonitor: NSViewRepresentable {
    var beginClick: () -> Void
    var isActive: () -> Bool
    var preservesOwnedInteractions = false
    var preservedClick: () -> Void = {}
    var outsideWindowClick: (() -> Void)? = nil
    var isInside: (CGPoint) -> Bool
    var click: (NSEvent) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.update(beginClick: beginClick, isActive: isActive,
                    preservesOwnedInteractions: preservesOwnedInteractions,
                    preservedClick: preservedClick,
                    outsideWindowClick: outsideWindowClick,
                    isInside: isInside, click: click)
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.update(beginClick: beginClick, isActive: isActive,
                    preservesOwnedInteractions: preservesOwnedInteractions,
                    preservedClick: preservedClick,
                    outsideWindowClick: outsideWindowClick,
                    isInside: isInside, click: click)
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    @MainActor final class MonitorView: NSView {
        private var monitor: Any?
        private var globalMonitor: Any?
        private var preservesOwnedInteractions = false
        private var menuObservers: [NSObjectProtocol] = []
        private var popoverObserver: NSObjectProtocol?
        private var auxiliaryDismissalPress: TimeInterval?
        private var trackingMenus = Set<ObjectIdentifier>()
        private var outsideWindowClick: (() -> Void)?
        private var beginClick: () -> Void = {}
        private var isActive: () -> Bool = { false }
        private var isInside: (CGPoint) -> Bool = { _ in true }
        private var click: (NSEvent) -> Void = { _ in }
        private var preservedClick: () -> Void = {}

        // Match the flipped SwiftUI scene rather than AppKit's bottom-left origin.
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func update(beginClick: @escaping () -> Void,
                    isActive: @escaping () -> Bool, preservesOwnedInteractions: Bool,
                    preservedClick: @escaping () -> Void,
                    outsideWindowClick: (() -> Void)?, isInside: @escaping (CGPoint) -> Bool,
                    click: @escaping (NSEvent) -> Void) {
            self.beginClick = beginClick; self.isActive = isActive
            self.isInside = isInside; self.click = click
            self.outsideWindowClick = outsideWindowClick
            self.preservesOwnedInteractions = preservesOwnedInteractions
            self.preservedClick = preservedClick
            syncGlobalMonitor()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
                menuObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    guard let menu = note.object as? NSMenu else { return }
                    let identity = ObjectIdentifier(menu), began = name == NSMenu.didBeginTrackingNotification
                    MainActor.assumeIsolated {
                        if began { self?.trackingMenus.insert(identity) }
                        else {
                            self?.trackingMenus.remove(identity)
                            self?.rememberAuxiliaryDismissalPress()
                        }
                    }
                })
            }
            popoverObserver = NotificationCenter.default.addObserver(forName: NSPopover.willCloseNotification,
                object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.rememberAuxiliaryDismissalPress()
                }
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window,
                          !self.isHiddenOrHasHiddenAncestor else { return }
                    if event.window === window {
                        // A mark only covers this press, including one owned by
                        // composition that AppKit may commit during delivery.
                        self.beginClick()
                        if self.preservesOwnedInteractions, self.isActive(),
                           (window.firstResponder as? NSTextInputClient)?.hasMarkedText() == true {
                            // Check before transient windows: an IME candidate
                            // window can disappear while forwarding this press.
                            self.preservedClick()
                            return
                        }
                    }
                    guard !self.ownsAuxiliaryInteraction(in: window) else {
                        if event.window === window, self.isActive() { self.preservedClick() }
                        return
                    }
                    guard event.window === window else {
                        self.clickOutsideWindow()
                        return
                    }
                    guard !self.preservesOwnedInteractions || self.auxiliaryDismissalPress != event.timestamp else {
                        self.preservedClick()
                        return
                    }
                    guard self.isActive() else { return }
                    let point = self.convert(event.locationInWindow, from: nil)
                    guard !self.isInside(point) else { return }
                    self.click(event)
                }
                return event
            }
            syncGlobalMonitor()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { stop() }
            super.viewWillMove(toWindow: newWindow)
        }

        private func rememberAuxiliaryDismissalPress() {
            guard let event = NSApp.currentEvent, event.window === window,
                  event.type == .leftMouseDown else { return }
            // AppKit may retire a menu/child window before forwarding its press.
            auxiliaryDismissalPress = event.timestamp
        }

        private func ownsAuxiliaryInteraction(in window: NSWindow) -> Bool {
            // Focus can move to a native menu, file chooser or popover while it
            // still belongs to the composer. Let that surface handle its click
            // (including its own outside dismissal) before retiring the input.
            preservesOwnedInteractions && (!trackingMenus.isEmpty || window.attachedSheet != nil
                || NSApp.modalWindow != nil || (window.childWindows ?? []).contains { $0.isVisible && $0.canBecomeKey })
        }

        private func clickOutsideWindow() {
            guard let window, !window.ignoresMouseEvents, window.isVisible, !isHiddenOrHasHiddenAncestor, isActive(),
                  !ownsAuxiliaryInteraction(in: window) else { return }
            outsideWindowClick?()
        }

        private func syncGlobalMonitor() {
            guard window?.ignoresMouseEvents == false, outsideWindowClick != nil else {
                if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
                return
            }
            guard globalMonitor == nil else { return }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.clickOutsideWindow() }
            }
        }

        func stop() {
            if let popoverObserver { NotificationCenter.default.removeObserver(popoverObserver); self.popoverObserver = nil }
            auxiliaryDismissalPress = nil
            for observer in menuObservers { NotificationCenter.default.removeObserver(observer) }
            menuObservers.removeAll(); trackingMenus.removeAll()
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        }
    }
}
