import AppKit
import ApplicationServices
import Foundation

let preparation: UInt64 = 45_000_000_000
func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

func record(_ fields: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    FileHandle.standardOutput.write(data + Data([10]))
}

func stop(_ message: String, status: Int32 = 1) -> Never {
    record(["kind": "failure", "message": message])
    exit(status)
}

if CommandLine.arguments.dropFirst() == ["--probe"] {
    let trusted = AXIsProcessTrusted()
    record(["kind": "environment", "driver": "AXPress", "clock": "DispatchTime.uptimeNanoseconds",
            "accessibilityTrusted": trusted, "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency])
    exit(trusted ? 0 : 2)
}

guard (6...7).contains(CommandLine.arguments.count), let pid = Int32(CommandLine.arguments[1]), let runtimePID = Int32(CommandLine.arguments[4]),
      let application = NSRunningApplication(processIdentifier: pid),
      let bundle = application.bundleURL?.resolvingSymlinksInPath(),
      bundle == URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true).resolvingSymlinksInPath(),
      application.bundleIdentifier == "com.chief.e2e." + CommandLine.arguments[3],
      AXIsProcessTrusted() else { stop("Isolated Chief application or Accessibility authorization unavailable", status: 2) }

let app = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app, 0.20)

func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
    return value
}

func element(_ owner: AXUIElement, _ key: String) -> AXUIElement? {
    guard let value = attribute(owner, key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

func findControl(in window: AXUIElement, matching: (AXUIElement, String) -> Bool) -> AXUIElement? {
    var queue = [window]
    var index = 0
    let deadline = now() + 150_000_000
    while index < queue.count, index < 500, now() < deadline {
        let node = queue[index]
        index += 1
        if let id = attribute(node, kAXIdentifierAttribute) as? String, matching(node, id) { return node }
        queue += attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    return nil
}

func control(in window: AXUIElement, matching: (String) -> Bool) -> AXUIElement? {
    findControl(in: window) { node, id in
        guard matching(id), attribute(node, kAXEnabledAttribute) as? Bool == true else { return false }
        var actions: CFArray?
        return AXUIElementCopyActionNames(node, &actions) == .success
            && (actions as? [String])?.contains(kAXPressAction) == true
    }
}

func frame(of node: AXUIElement) -> CGRect? {
    guard let position = attribute(node, kAXPositionAttribute), let size = attribute(node, kAXSizeAttribute),
          CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    var extent = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &extent),
          extent.width > 0, extent.height > 0 else { return nil }
    return CGRect(origin: point, size: extent)
}

func hitAtCenter(_ frame: CGRect) -> AXUIElement? {
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(app, Float(frame.midX), Float(frame.midY), &hit) == .success else { return nil }
    return hit
}

// Observe the real popup and its selected title, scoped to this role. The
// inherited popup is disabled; only the independent editor enables it.
func modelField(_ scope: String, in window: AXUIElement, editable: Bool) -> (id: String, value: String)? {
    guard let popup = findControl(in: window, matching: { node, id in
        id.hasPrefix(scope + ".") && id.hasSuffix(".model")
            && attribute(node, kAXRoleAttribute) as? String == kAXPopUpButtonRole
            && attribute(node, kAXEnabledAttribute) as? Bool == editable
    }), let id = attribute(popup, kAXIdentifierAttribute) as? String,
        let value = attribute(popup, kAXValueAttribute) as? String, !value.isEmpty,
        let parent = element(popup, kAXWindowAttribute), CFEqual(parent, window),
        let rect = frame(of: popup), let hit = hitAtCenter(rect), CFEqual(hit, popup) else { return nil }
    return (id, value)
}

func foreground() -> Bool { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }

func waitFor<T>(until deadline: UInt64, _ observe: () -> T?) -> T? {
    while now() < deadline {
        if application.isTerminated { stop("Isolated Chief exited") }
        if let value = observe() { return value }
        Thread.sleep(forTimeInterval: 0.01)
    }
    return nil
}

func requireForeground(_ window: AXUIElement) {
    guard foreground(), let focused = element(app, kAXFocusedWindowAttribute),
          CFEqual(focused, window) else { stop("Isolated Chief lost the foreground window") }
}

func requirePressTarget(_ button: AXUIElement, in window: AXUIElement) {
    requireForeground(window)
    let profile = bundle.deletingLastPathComponent().appendingPathComponent("profile")
    var owner: pid_t = 0
    guard let data = try? Data(contentsOf: profile.appendingPathComponent("runtime/connection.json")),
          let info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          info["pid"] as? pid_t == runtimePID, kill(runtimePID, 0) == 0,
          info["epoch"] as? String == CommandLine.arguments[5], let dir = info["dataDir"] as? String,
          URL(fileURLWithPath: dir).resolvingSymlinksInPath().path == profile.resolvingSymlinksInPath().path,
          AXUIElementGetPid(button, &owner) == .success, owner == pid,
          let parent = element(button, kAXWindowAttribute), CFEqual(parent, window)
    else { stop("Confirmation no longer belongs to the isolated runtime and window") }
}

func ready(_ id: String, in window: AXUIElement) -> AXUIElement? {
    control(in: window) { $0 == id }
}

func dockReady(in window: AXUIElement) -> Bool {
    // Do not traverse the changing onboarding tree on every poll while the
    // editor is unfocused. Both the enabled attachment and editable focus
    // still have to be observed before stopping the confirmation clock.
    guard let editor = element(app, kAXFocusedUIElementAttribute),
          let editorWindow = element(editor, kAXWindowAttribute), CFEqual(editorWindow, window),
          attribute(editor, kAXRoleAttribute) as? String == kAXTextAreaRole,
          attribute(editor, kAXValueAttribute) as? String == "" else { return false }
    var editable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(editor, kAXValueAttribute as CFString, &editable) == .success, editable.boolValue else { return false }
    let observed = now()
    guard ready("moku-add-attachment", in: window) != nil else { return false }
    record(["kind": "dock-readiness", "focusedEditorNS": observed, "attachmentVerifiedNS": now()])
    return true
}

guard let window = waitFor(until: now() + preparation, {
    foreground() ? element(app, kAXFocusedWindowAttribute) : nil
}) else { stop("Isolated Chief never had a foreground window", status: 2) }
record(["kind": "window", "pid": pid, "bundleID": application.bundleIdentifier ?? ""])

let requestedHost = CommandLine.arguments.count == 7 ? CommandLine.arguments[6] : nil
let steps = ["discovery", "moku", "tag", "report"]
var failedBudget = false
for (index, step) in steps.enumerated() {
    let confirm = "onboarding-confirm-" + step
    if let requestedHost, step == "discovery" {
        guard waitFor(until: now() + preparation, {
            findControl(in: window) { _, id in id == "onboarding-ready-" + requestedHost }
        }) != nil else { stop("Requested Harness never became ready: \(requestedHost)", status: 2) }
    }
    if let requestedHost, step == "moku" {
        guard let button = waitFor(until: now() + preparation, { ready("moku-host-" + requestedHost, in: window) }) else {
            stop("Requested Chief host could not be selected")
        }
        requirePressTarget(button, in: window)
        guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else { stop("Chief host press failed") }
        record(["kind": "host", "harness": requestedHost])
    }
    if step == "tag" || step == "report" {
        let scope = step + ".settings"
        let choice = scope + "-mode-independent"
        guard let button = waitFor(until: now() + preparation, { ready(choice, in: window) }) else {
            stop("Configure separately is unavailable on \(step)")
        }
        guard let inherited = waitFor(until: now() + preparation, {
            modelField(scope, in: window, editable: false)
        }) else { stop("The inherited model field is missing on \(step)") }
        requirePressTarget(button, in: window)
        let start = now()
        guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
            stop("AXPress failed for Configure separately on \(step)")
        }
        let dispatched = now()
        let field = waitFor(until: start + 1_000_000_000) {
            foreground() ? modelField(scope, in: window, editable: true) : nil
        }
        let observed = now()
        let expectedField = requestedHost.map { scope + "." + $0 + ".model" } ?? inherited.id
        let passed = field?.id == inherited.id && inherited.id == expectedField && field?.value == inherited.value && observed - start < 1_000_000_000
        record(["kind": "role", "id": scope, "selection": "independent", "startNS": start,
                "dispatchReturnedNS": dispatched, "observedNS": observed, "field": field?.id ?? "",
                "expectedModel": inherited.value, "model": field?.value ?? "", "status": passed ? "passed" : "failed"])
        if !passed {
            failedBudget = true
            if let node = findControl(in: window, matching: { _, id in id == inherited.id }), let rect = frame(of: node) {
                let hit = hitAtCenter(rect)
                record(["kind": "field-diagnostic", "scope": scope, "frame": NSStringFromRect(rect),
                        "value": attribute(node, kAXValueAttribute) as? String ?? "",
                        "enabled": attribute(node, kAXEnabledAttribute) as? Bool ?? false,
                        "hit": hit.flatMap { attribute($0, kAXRoleAttribute) as? String } ?? "",
                        "hitID": hit.flatMap { attribute($0, kAXIdentifierAttribute) as? String } ?? ""])
            }
        }
    }

    guard let button = waitFor(until: now() + preparation, { ready(confirm, in: window) }) else {
        stop("Confirmation is unavailable on \(step)")
    }
    requirePressTarget(button, in: window)
    let destination = index + 1 < steps.count ? steps[index + 1] : "dock"
    // The Dock handoff adds 560ms of authored motion to the confirmation.
    let budget: UInt64 = destination == "dock" ? 1_560_000_000 : 1_000_000_000
    let start = now()
    let press = AXUIElementPerformAction(button, kAXPressAction as CFString)
    let dispatched = now()
    guard press == .success else {
        record(["kind": "confirmation", "step": step, "destination": destination, "startNS": start,
                "observedNS": now(), "status": "input-failed", "axError": press.rawValue])
        stop("AXPress failed for \(step)")
    }
    let observe = {
        foreground() && (destination == "dock" ? dockReady(in: window)
            : ready("onboarding-confirm-" + destination, in: window) != nil) && foreground()
            ? now() : nil
    }
    var end = waitFor(until: start + budget, observe)
    let passed = end.map { $0 - start < budget } ?? false
    record(["kind": "confirmation", "step": step, "destination": destination, "startNS": start, "dispatchReturnedNS": dispatched,
            "observedNS": end ?? now(), "status": passed ? "passed" : "timed-out"])
    if !passed {
        failedBudget = true
        // Keep the failure sticky. Late readiness only allows the later steps
        // to be measured in this same visit, without repeating the input.
        if end == nil { end = waitFor(until: start + preparation, observe) }
        guard let end else { stop("\(destination) never became interactive after confirming \(step)") }
        record(["kind": "late-readiness", "step": step, "observedNS": end])
    }
}
exit(failedBudget ? 1 : 0)
