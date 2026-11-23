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

guard CommandLine.arguments.count == 4, let pid = Int32(CommandLine.arguments[1]),
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

func control(in window: AXUIElement, matching: (String) -> Bool) -> AXUIElement? {
    var queue = [window]
    var index = 0
    let deadline = now() + 150_000_000
    while index < queue.count, index < 500, now() < deadline {
        let node = queue[index]
        index += 1
        if let id = attribute(node, kAXIdentifierAttribute) as? String, matching(id) {
            guard attribute(node, kAXEnabledAttribute) as? Bool == true else { return nil }
            var actions: CFArray?
            if AXUIElementCopyActionNames(node, &actions) == .success,
               (actions as? [String])?.contains(kAXPressAction) == true {
                return node
            }
        }
        queue += attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    return nil
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

func ready(_ id: String, in window: AXUIElement) -> AXUIElement? {
    control(in: window) { $0 == id }
}

func dockReady(in window: AXUIElement) -> Bool {
    guard ready("moku-add-attachment", in: window) != nil,
          let editor = element(app, kAXFocusedUIElementAttribute),
          let editorWindow = element(editor, kAXWindowAttribute), CFEqual(editorWindow, window),
          attribute(editor, kAXRoleAttribute) as? String == kAXTextAreaRole,
          attribute(editor, kAXValueAttribute) as? String == "" else { return false }
    var editable = DarwinBoolean(false)
    return AXUIElementIsAttributeSettable(editor, kAXValueAttribute as CFString, &editable) == .success && editable.boolValue
}

guard let window = waitFor(until: now() + preparation, {
    foreground() ? element(app, kAXFocusedWindowAttribute) : nil
}) else { stop("Isolated Chief never had a foreground window", status: 2) }
record(["kind": "window", "pid": pid, "bundleID": application.bundleIdentifier ?? ""])

let steps = ["discovery", "moku", "tag", "report"]
var failedBudget = false
for (index, step) in steps.enumerated() {
    let confirm = "onboarding-confirm-" + step
    if step == "tag" || step == "report" {
        let scope = step + ".settings"
        let choice = scope + "-mode-independent"
        guard let button = waitFor(until: now() + preparation, { ready(choice, in: window) }) else {
            stop("Configure separately is unavailable on \(step)")
        }
        requireForeground(window)
        guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
            stop("AXPress failed for Configure separately on \(step)")
        }
        // The always-editable Harness selector only mounts for an independent role.
        guard waitFor(until: now() + preparation, {
            control(in: window) { $0.hasPrefix(scope + "-harness-") }
        }) != nil else { stop("The separate \(step) editor never mounted") }
        record(["kind": "role", "id": scope, "selection": "independent"])
    }

    guard let button = waitFor(until: now() + preparation, { ready(confirm, in: window) }) else {
        stop("Confirmation is unavailable on \(step)")
    }
    requireForeground(window)
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
