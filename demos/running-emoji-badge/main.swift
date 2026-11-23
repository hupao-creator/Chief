import AppKit
import ChiefPluginUI
import SwiftUI

@MainActor private final class Delegate: NSObject, NSApplicationDelegate {
    private let state = ComparisonState()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = NSHostingView(rootView: Comparison(state: state))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Agent Thread · 运行态徽章"
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        NSApp.activate()
        if CommandLine.arguments.contains("--capture") {
            Task {
                do {
                    try await recordComparison(window: window, state: state)
                    NSApp.terminate(nil)
                } catch {
                    FileHandle.standardError.write(Data("录制失败：\(error)\n".utf8))
                    exit(1)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main private struct BadgeDemo {
    @MainActor static func main() throws {
        // Only the recorder writes files. Interactive launches also work after moving the app.
        if CommandLine.arguments.contains("--capture") { try prepareIsolatedNativeReplay() }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        NativeTypography.registerFonts()
        let menu = NSMenu()
        let item = NSMenuItem()
        item.submenu = NSMenu()
        item.submenu?.addItem(withTitle: "退出徽章预览", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(item)
        app.mainMenu = menu
        let delegate = Delegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
