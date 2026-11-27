import AppKit
import ApplicationServices
import Foundation

// The caller owns a fresh profile and process. Target only its signed bundle
// and main window, including when another copy of Chief is running.
func record(_ fields: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    FileHandle.standardOutput.write(data + Data([10]))
}
func fail(_ message: String) -> Never {
    record(["failure": message])
    exit(1)
}
guard CommandLine.arguments.count == 3, let pid = Int32(CommandLine.arguments[1]),
      let app = NSRunningApplication(processIdentifier: pid),
      app.bundleURL?.resolvingSymlinksInPath().path == URL(fileURLWithPath: CommandLine.arguments[2]).resolvingSymlinksInPath().path
else { fail("Could not identify the requested Chief process.") }
guard AXIsProcessTrusted() else { fail("The mouse driver needs macOS Accessibility access.") }
let ax = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(ax, 2)
func attr(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(node, key as CFString, &result) == .success ? result : nil
}
func wait<T>(seconds: Double = 10, _ block: () -> T?) -> T? {
    let until = ProcessInfo.processInfo.systemUptime + seconds
    repeat {
        if app.isTerminated { fail("The isolated Chief window closed.") }
        if let result = block() { return result }
        Thread.sleep(forTimeInterval: 0.06)
    } while ProcessInfo.processInfo.systemUptime < until
    return nil
}
func find(_ id: String, in window: AXUIElement) -> AXUIElement? {
    var nodes = [window]
    var index = 0
    while index < nodes.count && index < 2500 {
        let node = nodes[index]
        if attr(node, kAXIdentifierAttribute) as? String == id { return node }
        nodes += attr(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
        index += 1
    }
    return nil
}
func frame(_ node: AXUIElement) -> CGRect? {
    guard let origin = attr(node, kAXPositionAttribute), CFGetTypeID(origin) == AXValueGetTypeID(),
          let size = attr(node, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero, extent = CGSize.zero
    guard AXValueGetValue(origin as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &extent),
          extent.width > 0, extent.height > 0 else { return nil }
    return CGRect(origin: point, size: extent)
}
func pointerTarget(_ point: CGPoint) -> AXUIElement? {
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
          let hit else { return nil }
    var owner: pid_t = 0
    guard AXUIElementGetPid(hit, &owner) == .success, owner == pid else { return nil }
    return hit
}
func notice(_ window: AXUIElement) -> String? {
    guard let node = find("operation-notice", in: window) else { return nil }
    var nodes = [node], values = [String]()
    for i in 0..<12 {
        if i >= nodes.count { break }
        for key in [kAXValueAttribute, kAXDescriptionAttribute] {
            if let value = attr(nodes[i], key) as? String, !value.isEmpty { values.append(value) }
        }
        nodes += attr(nodes[i], kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    return values.joined(separator: " ")
}
func mouse(_ type: CGEventType, _ point: CGPoint, right: Bool = false) {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
          pointerTarget(point) != nil,
          let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type, mouseCursorPosition: point,
                              mouseButton: right ? .right : .left) else { fail("The target window lost focus.") }
    event.post(tap: .cghidEventTap)
}
func click(_ point: CGPoint, right: Bool = false) {
    mouse(right ? .rightMouseDown : .leftMouseDown, point, right: right)
    Thread.sleep(forTimeInterval: 0.09)
    mouse(right ? .rightMouseUp : .leftMouseUp, point, right: right)
}
app.activate()
guard let window: AXUIElement = wait(seconds: 45, {
    (attr(ax, kAXWindowsAttribute) as? [AXUIElement])?.first { find("moku-capsule", in: $0) != nil }
}) else { fail("The production Chief Bar did not mount.") }

var previous = CGRect.null
var stableSince = ProcessInfo.processInfo.systemUptime
guard let bar: CGRect = wait(seconds: 45, {
    guard let rect = find("moku-capsule", in: window).flatMap(frame) else { return nil }
    if rect != previous { previous = rect; stableSince = ProcessInfo.processInfo.systemUptime }
    return ProcessInfo.processInfo.systemUptime - stableSince > 0.8 ? rect : nil
}) else { fail("The production Chief Bar did not settle.") }
// A fresh workspace can open directly to the large landing composer.
let point = CGPoint(x: bar.width > 260 ? bar.minX + 30 : bar.midX, y: bar.width > 260 ? bar.maxY - 23 : bar.midY)
guard find("voice-orb", in: window) == nil else { fail("Voice was already active before the hold.") }
mouse(.mouseMoved, point)
mouse(.leftMouseDown, point)
Thread.sleep(forTimeInterval: 0.6)
if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, pointerTarget(point) != nil {
    mouse(.leftMouseUp, point)
} else {
    // A permission dialog can now have focus. Release only to the app that
    // received the down event. The driver never clicks the consent dialog.
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.postToPid(pid)
}
record(["step": "heldBar", "pid": pid, "bar": NSStringFromRect(bar), "point": NSStringFromPoint(point)])
guard let orb = wait(seconds: 75, {
    if let reason = notice(window) { fail("Chief reported: " + reason) }
    return find("voice-orb", in: window)
}) else {
    let foreground = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
    fail("No listening orb after the hold. Foreground application: " + foreground)
}
func value() -> String { find("voice-orb", in: window).flatMap { attr($0, kAXValueAttribute) as? String } ?? "" }
guard let _: Bool = wait({ value().contains("Listening") || value().contains("聆听") ? true : nil }) else {
    fail("The orb did not expose an open microphone.")
}
guard let settled: CGRect = wait({
    guard let bar = find("moku-capsule", in: window).flatMap(frame), let circle = frame(orb),
          abs(circle.midY - bar.midY) < 3, circle.minX > bar.maxX + 8 else { return nil }
    return circle
}) else { fail("The listening orb did not separate beside Chief Bar.") }
record(["step": "listening", "orbWidth": settled.width, "orbHeight": settled.height])
let center = CGPoint(x: settled.midX, y: settled.midY)
click(center)
guard let _: Bool = wait({ value().contains("muted") || value().contains("静音") ? true : nil }) else { fail("Click did not mute the microphone.") }
record(["step": "muted"])
func command(_ key: CGKeyCode) {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
          let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) else {
        fail("The target window cannot receive the keyboard shortcut.")
    }
    for event in [down, up] { event.flags = .maskCommand; event.postToPid(pid) }
}
command(0x2B) // Cmd+, opens Settings over Overview, covering the orb.
guard let _: Bool = wait({
    find("settings-close", in: window) != nil && find("voice-orb", in: window) == nil ? true : nil
}) else { fail("Settings did not cover the muted call.") }
record(["step": "openedSettings"])
command(0x28) // Cmd+K returns to Overview.
guard let navigated: CGRect = wait({
    guard find("settings-close", in: window) == nil, value().contains("muted") || value().contains("静音"),
          let bar = find("moku-capsule", in: window).flatMap(frame),
          let circle = find("voice-orb", in: window).flatMap(frame),
          circle.minX > bar.maxX + 8, abs(circle.midY - bar.midY) < 3 else { return nil }
    return circle
}) else {
    fail("Returning to Overview lost the muted call.")
}
record(["step": "overviewWhileMuted"])
let activeCenter = CGPoint(x: navigated.midX, y: navigated.midY)
click(activeCenter)
guard let _: Bool = wait({ value().contains("Listening") || value().contains("聆听") ? true : nil }) else { fail("Second click did not restore the microphone.") }
record(["step": "unmuted"])
click(activeCenter, right: true)
guard let _: Bool = wait({ find("voice-orb", in: window) == nil ? true : nil }) else { fail("The orb survived secondary click.") }
record(["step": "ended"])
