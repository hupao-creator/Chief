import AppKit
import ChiefPluginAPI
@testable import ChiefPluginUI

@MainActor func pressReadingPanelClose(in window: NSWindow, identifier: String) throws {
    func anchor(_ view: NSView) -> NSView? {
        if view.identifier?.rawValue == identifier { return view }
        return view.subviews.lazy.compactMap(anchor).first
    }
    guard let root = window.contentView, let panel = anchor(root) else { throw PluginContractError("Missing panel frame \(identifier)") }
    let bounds = panel.convert(panel.bounds, to: nil)
    let inset = NativeReadingPanelCloseButton.edgeInset + NativeReadingPanelCloseButton.diameter / 2
    let point = NSPoint(x: bounds.minX + inset, y: bounds.maxY - inset)
    clickReplayWindow(window, at: point)
}

@MainActor func clickReplayWindow(_ window: NSWindow, at point: NSPoint) {
    func mouse(_ type: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }
    let up = mouse(.leftMouseUp)
    NSApp.postEvent(up, atStart: true)
    window.sendEvent(mouse(.leftMouseDown))
    if NSApp.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: false) === up {
        _ = NSApp.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true)
        window.sendEvent(up)
    }
}
