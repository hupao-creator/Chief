import AppKit
import ChiefComposition
import ChiefCore
import ChiefPluginAPI
import SwiftUI
@testable import ChiefUI

/// The real workspace and native Return event run entirely in the replay's profile.
@main @MainActor enum ReportFollowup {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task {
            do { try await capture() }
            catch { print("Report follow-up failed:", error); exit(1) }
            app.terminate(nil)
        }
        app.run()
    }

    static func wait(_ failure: String, until ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(18)
        while !ready() {
            guard ContinuousClock.now < deadline else { throw PluginContractError(failure) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    static func editor(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView, text.isEditable, !text.isHiddenOrHasHiddenAncestor { return text }
        for child in view.subviews {
            if let field = editor(in: child) { return field }
        }
        return nil
    }

    static func capture() async throws {
        try prepareIsolatedNativeReplay()
        let args = CommandLine.arguments
        guard args.count == 6, let screen = NSScreen.screens.max(by: { $0.frame.maxX < $1.frame.maxX }) else {
            throw PluginContractError("Expected an isolated profile, Report, Thread and completed execution")
        }
        let profile = URL(fileURLWithPath: args[1])
        guard profile.lastPathComponent == "profile", profile.deletingLastPathComponent().lastPathComponent.hasPrefix("me2e-") else {
            throw PluginContractError("Expected a private e2e workspace")
        }
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let preferences = DesktopPreferences(directory: profile)
        try preferences.setOnboardingCompleted(true)
        let model = NativeWorkspaceModel(client: RuntimeClient(profile: try RuntimeProfile(dataDirectory: profile)),
            preferences: preferences, plugins: try NativePlugins.make())
        let host = NativeWorkspacePresentation(workspace: model)
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { panel.orderOut(nil) }
        panel.ignoresMouseEvents = true
        // Keep two points on the display so WindowServer continues composing
        // the full-size independent window without bringing it to the foreground.
        panel.setFrameOrigin(CGPoint(x: screen.frame.maxX - 2, y: screen.visibleFrame.minY))
        panel.appearance = NSAppearance(named: .darkAqua)
        let view = NSHostingView(rootView: NativeWorkspaceView(model: model, presentation: host)
            .transformEnvironment(\._accessibilityReduceMotion) { if args[5].hasSuffix("-reduced") { $0 = true } }
            .transformEnvironment(\.accessibilityEnabled) { if args[5].hasPrefix("tag-return") { $0 = true } }
            .environment(\.scenePhase, .active).environment(\.colorScheme, .dark))
        panel.contentView = view
        panel.orderFrontRegardless()
        model.start()
        try await wait("Initial catalog did not mount") { model.hasInitialContent && host.scene.overviewVisible }
        let report = ApplicationThreadRef(threadID: JSONText(args[2]), typeID: "report.document")
        let source = ApplicationExecutionRef(thread: .init(threadID: JSONText(args[3]), typeID: "agent"), executionID: JSONText(args[4]))
        if args[5].hasPrefix("tag-return") || args[5].hasPrefix("identity") {
            if args[5].hasPrefix("tag-return") {
                try await recordTagReturn(window: panel, host: host, report: report, scenario: args[5])
            } else {
                try await recordIdentity(window: panel, host: host, report: report, source: source, scenario: args[5])
            }
            guard foreground == NSWorkspace.shared.frontmostApplication?.processIdentifier else {
                throw PluginContractError("Foreground application changed")
            }
            return
        }
        host.open(report)
        let cards = host.reportSidecards
        try await wait("Report sidecard was not admitted") { cards.active == .relatedExecutions }
        cards.selectExecution(source)
        try await wait("Right-column editor did not settle") {
            host.dockExecution == source && host.dockInputAvailable && host.scene.inputOpen && host.scene.capsuleFrame.midX > 800
        }
        try await Task.sleep(for: .milliseconds(600))
        guard let field = editor(in: view), panel.makeFirstResponder(field),
              let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                  windowNumber: panel.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                  isARepeat: false, keyCode: 36) else { throw PluginContractError("Missing native Report editor") }
        let prompt = "修复完成了吗"
        field.insertText(prompt, replacementRange: field.selectedRange())
        try await wait("Draft did not receive the prompt") { host.dockDraft.text == prompt }
        let movie = try await DockMovieCapture(window: panel, folder: "report-send")
        let start = CACurrentMediaTime()
        var events: [[String: Any]] = []
        func record(_ action: String) {
            let frame = host.scene.capsuleFrame
            events.append(["action": action, "seconds": CACurrentMediaTime() - start,
                "x": frame.midX, "top": frame.minY, "width": frame.width])
        }
        record("finished source")
        try await Task.sleep(for: .milliseconds(550))
        field.keyDown(with: enter)
        record("native Return")
        try await wait("Missing accepted successor") { cards.selectedExecution != nil && cards.selectedExecution != source }
        record("receipt with catalog")
        try await wait("Successor input did not settle") {
            host.dockExecution == cards.selectedExecution && cards.executionReady && host.dockInputAvailable
        }
        record("destination reader and input ready")
        try await wait("Successor did not complete") { host.dockThread?.observation.latestExecution?.status == .completed }
        try await Task.sleep(for: .seconds(1))
        record("result settled")
        try await movie.finish()
        let sameForeground = foreground == NSWorkspace.shared.frontmostApplication?.processIdentifier
        let observations: [String: Any] = ["foregroundUnchanged": sameForeground, "reportStayedOpen": host.selected == report,
            "points": [panel.frame.width, panel.frame.height], "backingScale": panel.backingScaleFactor, "events": events,
            "windowFrame": [panel.frame.minX, panel.frame.minY, panel.frame.width, panel.frame.height]]
        try JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys])
            .write(to: movie.directory.appendingPathComponent("observations.json"))
        guard sameForeground, host.selected == report else { throw PluginContractError("Foreground or Report changed during Send") }
    }
}
