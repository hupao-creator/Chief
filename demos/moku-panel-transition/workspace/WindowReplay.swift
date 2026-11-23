import AppKit
import ApplicationServices
import ScreenCaptureKit

struct ReplayError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

final class RecordingDelegate: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
    let (finished, ending) = AsyncThrowingStream<Void, Error>.makeStream()
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { ending.finish() }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        ending.finish(throwing: error)
    }
}

// Test executable only. AX bounds can coincide across windows; ask the macOS
// Accessibility bridge for the WindowServer ID of the actual focused element.
@_silgen_name("_AXUIElementGetWindow")
private func axWindowID(_ window: AXUIElement, _ result: UnsafeMutablePointer<CGWindowID>) -> AXError

// WindowServer does not populate window-local coordinates for PID delivery.
@_silgen_name("CGEventSetWindowLocation")
private func setWindowLocation(_ event: CGEvent, _ point: CGPoint)

private struct ReplayTarget: Decodable {
    let pid: pid_t
    let windowID: CGWindowID
    let bounds: [String: CGFloat]
    let nonce: String
    let executable: URL
    let profile: URL
    let runtimePID: pid_t
    let epoch: String

    private struct Connection: Decodable {
        let pid: pid_t
        let dataDir: String
        let epoch: String
    }

    func focusedWindow() throws -> AXUIElement {
        let info = try JSONDecoder().decode(Connection.self, from: Data(contentsOf: profile.appendingPathComponent("runtime/connection.json")))
        let bundle = profile.deletingLastPathComponent().appendingPathComponent("ChiefE2E.app")
        func same(_ a: URL?, _ b: URL) -> Bool {
            a?.standardizedFileURL.resolvingSymlinksInPath().path == b.standardizedFileURL.resolvingSymlinksInPath().path
        }
        guard profile.lastPathComponent == "profile", profile.deletingLastPathComponent().lastPathComponent.hasPrefix("me2e-"),
              same(profile.deletingLastPathComponent().deletingLastPathComponent(), URL(fileURLWithPath: "/private/tmp")),
              info.pid == runtimePID, kill(runtimePID, 0) == 0, info.epoch == epoch,
              same(URL(fileURLWithPath: info.dataDir), profile) else { throw ReplayError("Test runtime identity changed") }
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              app.bundleIdentifier == "com.chief.e2e." + nonce, same(app.bundleURL, bundle),
              same(app.executableURL, executable) else { throw ReplayError("Test app executable or bundle changed") }
        guard !app.isHidden, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let window = Self.element(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute),
              Self.attribute(window, kAXIdentifierAttribute) as? String == "workspace",
              Self.attribute(window, kAXMinimizedAttribute) as? Bool != true else {
            throw ReplayError("Test workspace lost focus")
        }
        var focusedID: CGWindowID = 0
        guard axWindowID(window, &focusedID) == .success, focusedID == windowID else {
            throw ReplayError("Focused AX window differs from the recorded WindowServer ID")
        }
        return window
    }

    static func attribute(_ item: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(item, key as CFString, &value) == .success ? value : nil
    }
    static func element(_ item: AXUIElement, _ key: String) -> AXUIElement? {
        guard let value = attribute(item, key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    func hit(_ point: CGPoint) throws -> AXUIElement {
        let window = try focusedWindow()
        var hit: AXUIElement?
        var owner: pid_t = 0
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              let hit, AXUIElementGetPid(hit, &owner) == .success, owner == pid,
              CFEqual(hit, window) || Self.element(hit, kAXWindowAttribute).map({ CFEqual($0, window) }) == true else {
            throw ReplayError("Pointer target is outside the focused replay workspace")
        }
        return hit
    }
}

@main enum WindowReplay {
    @MainActor static func main() async {
        do { try await perform() }
        catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
    @MainActor static func perform() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 2 else { throw ReplayError("Missing replay target or operation") }
        let target = try JSONDecoder().decode(ReplayTarget.self, from: Data(contentsOf: URL(fileURLWithPath: args[0])))
        _ = try target.focusedWindow()
        if args[1] == "record", args.count == 3 {
            try await record(target.pid, windowID: target.windowID, directory: URL(fileURLWithPath: args[2], isDirectory: true))
            return
        }
        let source = CGEventSource(stateID: .privateState)
        func send(_ event: CGEvent) throws {
            _ = try target.focusedWindow()
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(target.windowID))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(target.windowID))
            event.postToPid(target.pid)
        }
        func key(_ code: CGKeyCode, flags: CGEventFlags) throws {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else {
                    throw ReplayError("Key event unavailable")
                }
                event.flags = flags
                try send(event)
                usleep(10000)
            }
        }
        switch args[1] {
        case "prepare":
            guard let x = target.bounds["x"], let y = target.bounds["y"],
                  let w = target.bounds["width"], let h = target.bounds["height"] else { throw ReplayError("Missing fixture bounds") }
            var size = CGSize(width: w, height: h)
            var origin = CGPoint(x: x, y: y)
            for _ in 0..<30 {
                let window = try target.focusedWindow()
                var actualOrigin = CGPoint.zero
                var actualSize = CGSize.zero
                guard let pos = ReplayTarget.attribute(window, kAXPositionAttribute), CFGetTypeID(pos) == AXValueGetTypeID(),
                      let dims = ReplayTarget.attribute(window, kAXSizeAttribute), CFGetTypeID(dims) == AXValueGetTypeID(),
                      AXValueGetValue(pos as! AXValue, .cgPoint, &actualOrigin), AXValueGetValue(dims as! AXValue, .cgSize, &actualSize)
                else { throw ReplayError("Workspace has no AX geometry") }
                if actualOrigin == origin && actualSize == size { return }
                if actualOrigin != origin {
                    guard AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin)!) == .success else { throw ReplayError("Fixture positioning failed") }
                } else {
                    guard AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!) == .success else { throw ReplayError("Fixture resize failed") }
                }
                try await Task.sleep(for: .milliseconds(75))
            }
            throw ReplayError("Workspace did not reach fixture bounds")
        case "probe": return
        case "withdraw":
            let window = try target.focusedWindow()
            guard AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success else {
                throw ReplayError("Could not minimize the isolated workspace")
            }
        case "compose", "reverse":
            try key(11, flags: [.maskCommand, .maskShift])
            if args[1] == "reverse" {
                try await Task.sleep(for: .milliseconds(120))
                try key(11, flags: [.maskCommand, .maskShift])
            }
        case "escape": try key(53, flags: [])
        case "click", "hover", "press", "focus":
            let controlAction = args[1] == "press" || args[1] == "focus"
            guard args.count == (controlAction ? 5 : 4), let x = Double(args[2]), let y = Double(args[3]) else {
                throw ReplayError("Expected screen coordinates")
            }
            let point = CGPoint(x: x, y: y)
            if controlAction {
                _ = try target.hit(point)
                let window = try target.focusedWindow()
                let label = args[4]
                var queue = [window]
                var found: [AXUIElement] = []
                var i = 0
                while i < queue.count && queue.count < 1500 {
                    let item = queue[i]
                    i += 1
                    if [kAXIdentifierAttribute, kAXDescriptionAttribute].contains(where: {
                        ReplayTarget.attribute(item, $0) as? String == label
                    }) { found.append(item) }
                    queue += ReplayTarget.attribute(item, kAXChildrenAttribute) as? [AXUIElement] ?? []
                }
                guard i == queue.count, found.count == 1, let button = found.first,
                      ReplayTarget.element(button, kAXWindowAttribute).map({ CFEqual($0, window) }) == true,
                      ReplayTarget.attribute(button, kAXEnabledAttribute) as? Bool == true
                else { throw ReplayError("Expected one enabled control inside the replay window: " + label) }
                _ = try target.focusedWindow()
                if args[1] == "focus" {
                    guard AXUIElementSetAttributeValue(button, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else {
                        throw ReplayError("Isolated control could not take AX focus")
                    }
                } else {
                    guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else { throw ReplayError("Targeted AXPress failed") }
                }
                return
            }
            guard let left = target.bounds["x"], let top = target.bounds["y"], let height = target.bounds["height"]
            else { throw ReplayError("Missing prepared window bounds") }
            let local = CGPoint(x: point.x - left, y: height - (point.y - top))
            let events: [NSEvent.EventType] = args[1] == "hover" ? [.mouseMoved] : [.mouseMoved, .leftMouseDown, .leftMouseUp]
            for kind in events {
                _ = try target.hit(point)
                guard let event = NSEvent.mouseEvent(with: kind, location: local, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: Int(target.windowID), context: nil,
                    eventNumber: 1, clickCount: 1, pressure: kind == .leftMouseDown ? 1 : 0)?.cgEvent
                else { throw ReplayError("Targeted window event unavailable") }
                event.location = point
                setWindowLocation(event, CGPoint(x: point.x - left, y: point.y - top))
                event.setIntegerValueField(.mouseEventClickState, value: 1)
                try send(event)
                try await Task.sleep(for: .milliseconds(20))
            }
        default: throw ReplayError("Unknown action")
        }
    }

    static func record(_ pid: pid_t, windowID: CGWindowID, directory: URL) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.owningApplication?.processID == pid
            && $0.windowID == windowID && $0.windowLayer == 0 && $0.frame.width == 1885 && $0.frame.height == 1125 }) else {
            throw ReplayError("Missing 1885 × 1125pt test window")
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * CGFloat(filter.pointPixelScale))
        config.height = Int(window.frame.height * CGFloat(filter.pointPixelScale))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let target = SCRecordingOutputConfiguration()
        target.outputURL = directory.appendingPathComponent("window.mp4")
        let delegate = RecordingDelegate()
        let recording = SCRecordingOutput(configuration: target, delegate: delegate)
        try stream.addRecordingOutput(recording)
        try await stream.startCapture()
        try JSONSerialization.data(withJSONObject: ["pid": pid, "window": window.windowID,
            "width": config.width, "height": config.height]).write(to: directory.appendingPathComponent("ready.json"), options: .atomic)
        let stop = directory.appendingPathComponent("stop").path
        for _ in 0..<1200 {
            if FileManager.default.fileExists(atPath: stop) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try stream.removeRecordingOutput(recording)
        for try await _ in delegate.finished {}
        try await stream.stopCapture()
        guard FileManager.default.fileExists(atPath: stop) else { throw ReplayError("Recording exceeded 60 seconds") }
    }
}
