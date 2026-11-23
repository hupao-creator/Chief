import AppKit
import ChiefPluginUI
import ScreenCaptureKit
import SwiftUI
@testable import ChiefUI

struct ReplayFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw ReplayFailure(message) }
}

let evidence = URL(fileURLWithPath: "evidence", isDirectory: true)

func save(_ value: Any, _ name: String) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted])
        .write(to: evidence.appendingPathComponent(name), options: .atomic)
}

func savePNG(_ image: CGImage, _ name: String) throws {
    guard let bytes = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw ReplayFailure("Cannot encode " + name)
    }
    try bytes.write(to: evidence.appendingPathComponent(name))
}

func pause(_ milliseconds: Int) async throws { try await Task.sleep(for: .milliseconds(milliseconds)) }

@MainActor func until(_ name: String, _ ready: () -> Bool) async throws {
    let end = CACurrentMediaTime() + 4
    while !ready(), CACurrentMediaTime() < end { try await pause(5) }
    try check(ready(), name)
}

@MainActor final class Panel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(size: CGSize, offscreen: Bool = false) throws {
        guard let screen = NSScreen.screens.max(by: { $0.frame.maxX < $1.frame.maxX }) else {
            throw ReplayFailure("Missing graphical session")
        }
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        level = .floating
        hasShadow = false
        setFrameOrigin(.init(x: (offscreen ? screen.frame.maxX + 8 : screen.visibleFrame.maxX - 6), y: screen.visibleFrame.midY - size.height / 2))
        let root = NSView(frame: CGRect(origin: .zero, size: size))
        root.wantsLayer = true
        // Keep window capture delivering complete frames during a stationary
        // control's main-thread hold. The damage strip is outside every ROI.
        let marker = CALayer()
        marker.frame = CGRect(x: 0, y: 6, width: 4, height: 8)
        marker.zPosition = 10
        marker.backgroundColor = NSColor.blue.cgColor
        root.layer?.addSublayer(marker)
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.1
        pulse.toValue = 1
        pulse.duration = 0.35
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        marker.add(pulse, forKey: "capture-clock")
        contentView = root
        orderFrontRegardless()
        if offscreen && NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) {
            orderOut(nil)
            throw ReplayFailure("Replay panel entered the visible desktop")
        }
    }

    func mount<V: View>(_ content: V) {
        let host = NSHostingView(rootView: content.environment(\.scenePhase, .active).environment(\.locale, Locale(identifier: "en")))
        host.sizingOptions = []
        host.frame = contentView!.bounds
        host.autoresizingMask = [.width, .height]
        contentView!.addSubview(host)
    }

    func saveOffscreenImage(_ name: String) throws {
        guard let view = contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw ReplayFailure("Missing offscreen bitmap")
        }
        view.displayIfNeeded()
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let image = bitmap.cgImage else { throw ReplayFailure("Missing offscreen pixels") }
        try savePNG(image, name + ".png")
    }

    func filter() async throws -> SCContentFilter {
        let owned = try await SCShareableContent.currentProcess
        guard let window = owned.windows.first(where: { $0.windowID == windowNumber }) else {
            throw ReplayFailure("WindowServer did not publish the replay panel")
        }
        return SCContentFilter(desktopIndependentWindow: window)
    }

    func configuration() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = Int(frame.width * backingScaleFactor)
        config.height = Int(frame.height * backingScaleFactor)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        config.queueDepth = 6
        return config
    }
}

extension NSView {
    func descendants<T: NSView>(_ type: T.Type) -> [T] {
        ([self as? T].compactMap { $0 }) + subviews.flatMap { $0.descendants(type) }
    }
}

@MainActor final class Driver: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
            do {
                try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
                switch CommandLine.arguments.last {
                case "--eyes": try await eyeVisit()
                case "--tag-unread": try await tagUnreadVisit()
                case "--tool-feedback": try await toolFeedbackVisit()
                case "--routes", "--routes-reduced": try await routesVisit(reduced: CommandLine.arguments.last == "--routes-reduced")
                case "--routes-offscreen": try await routesVisit(reduced: false, offscreen: true)
                case "--timers", "--timers-reduced": try await timersVisit(reduced: CommandLine.arguments.last == "--timers-reduced")
                default: throw ReplayFailure("Unknown visit")
                }
                let after = NSWorkspace.shared.frontmostApplication?.processIdentifier
                try save(["pid": ProcessInfo.processInfo.processIdentifier, "foregroundBefore": foreground ?? -1,
                          "foregroundAfter": after ?? -1, "backingScale": NSScreen.screens.max(by: {
                              $0.frame.maxX < $1.frame.maxX
                          })?.backingScaleFactor ?? 0], "process.json")
                try check(foreground != nil && foreground == after, "Foreground application changed")
                exit(0)
            } catch {
                print(error)
                exit(1)
            }
        }
    }
}

@main @MainActor enum Replay {
    static func main() throws {
        if let action = CommandLine.arguments.dropFirst().first, ["--read", "--press"].contains(action), let id = CommandLine.arguments.last {
            let matches = parentButton(id, press: CommandLine.arguments[1] == "--press")
            FileHandle.standardOutput.write(try JSONEncoder().encode(matches))
            return
        }
        try prepareIsolatedNativeReplay()
        NativeTypography.registerFonts()
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let driver = Driver()
        app.delegate = driver
        withExtendedLifetime(driver) { app.run() }
    }
}
