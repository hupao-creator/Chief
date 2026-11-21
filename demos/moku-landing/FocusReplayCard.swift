import AppKit
import ApplicationServices

// A system accessibility client must run outside the app that serves its requests.
private func focusCard(in executable: URL, workspace: URL) throws {
    let target = workspace.appending(path: "keyboard-target")
    let deadline = Date().addingTimeInterval(60)
    while !FileManager.default.fileExists(atPath: target.path), Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    let identifier = try String(contentsOf: target, encoding: .utf8)
    let receipt = workspace.deletingLastPathComponent().appending(path: "runtime-isolation.json")
    let bootstrap = try JSONSerialization.jsonObject(with: Data(contentsOf: receipt)) as? [String: Any]
    guard let pid = bootstrap?["pid"] as? Int32,
          NSRunningApplication(processIdentifier: pid)?.executableURL?.resolvingSymlinksInPath() == executable,
          AXIsProcessTrusted() else {
        throw FocusError("The accessibility client needs an authorized shell and the isolated replay app")
    }
    func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
    var pending = [AXUIElementCreateApplication(pid)]
    var visited = Set<AXUIElement>()
    while let element = pending.popLast() {
        guard visited.insert(element).inserted else { continue }
        if attribute(element, kAXIdentifierAttribute) as? String == identifier {
            let result = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            guard result == .success else { throw FocusError("AX focus failed with status \(result.rawValue)") }
            return
        }
        pending.append(contentsOf: attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [])
    }
    throw FocusError("The isolated window does not expose \(identifier)")
}

private struct FocusError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

guard CommandLine.arguments.count == 3 else {
    print("Usage: FocusReplayCard <replay workspace> <replay executable>")
    exit(2)
}
let workspace = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let executable = URL(fileURLWithPath: CommandLine.arguments[2]).resolvingSymlinksInPath()
do {
    try focusCard(in: executable, workspace: workspace)
    try "focused".write(to: workspace.appending(path: "keyboard-focus"), atomically: true, encoding: .utf8)
} catch {
    print(error)
    try "failed".write(to: workspace.appending(path: "keyboard-focus"), atomically: true, encoding: .utf8)
    exit(1)
}
