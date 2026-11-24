import AppKit

@main @MainActor enum OverviewChromeFixtureApp {
    static func main() {
        do { try prepareIsolatedNativeReplay() }
        catch { print(error); exit(1) }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 860, height: 600),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate()
        Task {
            do {
                let evidence = URL(filePath: FileManager.default.currentDirectoryPath).appending(path: "evidence")
                try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
                #if HEADER_GLASS
                try await replayHeaderGlass(in: window, evidence: evidence)
                #endif
                #if RAIL_HOVER
                try await replayRailHover(in: window, evidence: evidence)
                #endif
                exit(0)
            } catch { print(error); exit(1) }
        }
        app.run()
    }
}
