import AppKit
import ApplicationServices

// Read or press named public AX elements in this executable's own replay
// parent. Calling into SwiftUI's AX tree from its main actor can reenter layout.
func parentButtons(_ ids: [String], press: Bool) -> [[String: String]] {
    guard ProcessInfo.processInfo.environment["CHIEF_REPLAY_PARENT"] == String(getppid()), AXIsProcessTrusted()
    else { return [["error": "Missing parent or AX permission"]] }
    let app = AXUIElementCreateApplication(getppid())
    AXUIElementSetMessagingTimeout(app, 0.5)
    var windows: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
          var pending = windows as? [AXUIElement] else { return [["error": "No replay window"]] }
    var seen = Set<CFHashCode>()
    var matches = [[String: String]]()
    while let node = pending.popLast(), seen.count < 6000 {
        guard seen.insert(CFHash(node)).inserted else { continue }
        func attribute(_ key: String) -> CFTypeRef? {
            var value: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(node, key as CFString, &value)
            return value
        }
        let identifier = attribute(kAXIdentifierAttribute) as? String
        let role = attribute(kAXRoleAttribute) as? String
        let labels = [kAXDescriptionAttribute, kAXTitleAttribute].compactMap { attribute($0) as? String }.filter { !$0.isEmpty }
        if let id = ids.first(where: { $0 == identifier || (role == "AXButton" && labels.contains($0)) }) {
            var match = ["id": id, "enabled": String(attribute(kAXEnabledAttribute) as? Bool ?? false),
                         "role": role ?? "", "label": labels.first ?? ""]
            if let position = attribute(kAXPositionAttribute), let size = attribute(kAXSizeAttribute),
               CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
                var origin = CGPoint.zero, extent = CGSize.zero
                if AXValueGetValue(position as! AXValue, .cgPoint, &origin),
                   AXValueGetValue(size as! AXValue, .cgSize, &extent) {
                    match["frame"] = NSStringFromRect(CGRect(origin: origin, size: extent))
                }
            }
            if press { match["press"] = String(AXUIElementPerformAction(node, kAXPressAction as CFString).rawValue) }
            matches.append(match)
        }
        pending += attribute(kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    return matches
}

@MainActor func button(_ ids: String..., press: Bool = false) async throws -> [[String: String]] {
    let child = Process(), pipe = Pipe()
    child.executableURL = Bundle.main.executableURL
    child.environment = ProcessInfo.processInfo.environment.merging(["CHIEF_REPLAY_PARENT": String(getpid())]) { _, value in value }
    child.arguments = [press ? "--press" : "--read"] + ids
    child.standardOutput = pipe
    try child.run()
    while child.isRunning { try await Task.sleep(for: .milliseconds(5)) }
    return try JSONDecoder().decode([[String: String]].self, from: pipe.fileHandleForReading.readDataToEndOfFile())
}

func serveReplayButtonQuery() throws -> Bool {
    guard let action = CommandLine.arguments.dropFirst().first, ["--read", "--press"].contains(action) else { return false }
    let ids = Array(CommandLine.arguments.dropFirst(2))
    guard !ids.isEmpty, action == "--read" || ids.count == 1 else { return false }
    FileHandle.standardOutput.write(try JSONEncoder().encode(parentButtons(ids, press: action == "--press")))
    return true
}
