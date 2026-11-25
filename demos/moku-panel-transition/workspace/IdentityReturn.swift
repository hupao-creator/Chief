import AppKit
import ChiefComposition
import ChiefCore
import ChiefPluginAPI
import SwiftUI
@testable import ChiefPluginUI
@testable import ChiefUI

@main @MainActor private enum IdentityReturn {
    final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task {
            do { try await capture() }
            catch { print("Identity return failed:", error); exit(1) }
            app.terminate(nil)
        }
        app.run()
    }

    static func wait(_ failure: String, until ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while !ready() {
            guard .now < deadline else { throw PluginContractError(failure) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    static func firstView<T: NSView>(in node: NSView, matching: (T) -> Bool) -> T? {
        if let candidate = node as? T, matching(candidate) { return candidate }
        for child in node.subviews {
            if let match = firstView(in: child, matching: matching) { return match }
        }
        return nil
    }

    static func capture() async throws {
        try prepareIsolatedNativeReplay()
        let args = CommandLine.arguments
        guard args.count == 3, let screen = NSScreen.screens.max(by: { $0.frame.maxX < $1.frame.maxX }) else {
            throw PluginContractError("Expected a private profile, an Agent thread and a display")
        }
        let profile = URL(fileURLWithPath: args[1])
        guard profile.lastPathComponent == "profile", profile.deletingLastPathComponent().lastPathComponent.hasPrefix("me2e-") else {
            throw PluginContractError("Expected an isolated e2e profile")
        }
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let preferences = DesktopPreferences(directory: profile)
        try preferences.setOnboardingCompleted(true)
        let model = NativeWorkspaceModel(client: RuntimeClient(profile: try RuntimeProfile(dataDirectory: profile)),
            preferences: preferences, plugins: try NativePlugins.make())
        let host = NativeWorkspacePresentation(workspace: model)
        // The reference's 16pt lift spans 29 movie pixels. Fit its workspace and
        // matte at 1.8 movie pixels per point, with the native layout at 100%.
        let stage = NSView(frame: CGRect(x: 0, y: 0, width: 2276, height: 1362))
        stage.wantsLayer = true
        stage.layer?.backgroundColor = NSColor.black.cgColor
        let view = NSHostingView(rootView: NativeWorkspaceView(model: model, presentation: host)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.scenePhase, .active).environment(\.colorScheme, .dark))
        view.frame = CGRect(x: 56, y: 74, width: 2164, height: 1250)
        stage.addSubview(view)
        let panel = Panel(contentRect: stage.bounds, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        defer { panel.orderOut(nil) }
        panel.ignoresMouseEvents = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = stage
        panel.setFrameOrigin(CGPoint(x: screen.frame.maxX - 2, y: screen.visibleFrame.minY))
        panel.orderFrontRegardless()
        guard panel.backingScaleFactor == 2 else { throw PluginContractError("This capture needs a 2× display") }
        let workspaceFrame = panel.convertToScreen(view.frame)
        guard !NSScreen.screens.contains(where: { $0.frame.intersects(workspaceFrame) }) else {
            throw PluginContractError("The replay workspace must stay offscreen")
        }
        model.start()
        let scene = host.scene
        let agent = ApplicationThreadRef(threadID: JSONText(args[2]), typeID: "agent")
        try await wait("Initial catalog did not mount") { model.hasInitialContent && scene.overviewVisible }
        func waitForEditor() async throws {
            try await wait("Right-column editor did not settle") {
                host.selected == agent && scene.inputOpen && scene.inputInteractionReady
                    && scene.capsuleFrame.midX > view.bounds.width * 0.65 && scene.capsuleFrame.width > 300
            }
            try await Task.sleep(for: .milliseconds(560))
        }
        for reverse in [false, true] {
            host.open(agent)
            try await waitForEditor()
            let draft = host.dockDraft
            let retainedText = "Keep this follow-up draft."
            if reverse { draft.text = retainedText }
            let movie = try await DockMovieCapture(window: panel, folder: reverse ? "reverse" : "close",
                pixels: CGSize(width: 4096, height: 2450), codec: .hevc)
            let start = CACurrentMediaTime()
            var events: [[String: Any]] = []
            func record(_ action: String) {
                let placement = scene.executionDockPlacement
                var event: [String: Any] = ["action": action, "seconds": CACurrentMediaTime() - start,
                    "readerSelected": host.selected == agent, "readerReturning": host.messageMotion.isReturning,
                    "inputReady": scene.inputInteractionReady, "inputOpen": scene.inputOpen,
                    "inputAdmitted": scene.inputAdmissionReady, "barCenter": scene.capsuleFrame.midX,
                    "barWidth": scene.capsuleFrame.width, "columnOwned": placement.threadID == agent.threadID]
                if let frame = placement.frame { event["columnFrame"] = NSStringFromRect(frame) }
                events.append(event)
            }
            func saveObservations(failure: String? = nil) throws {
                var result: [String: Any] = ["events": events, "foregroundUnchanged":
                    foreground == NSWorkspace.shared.frontmostApplication?.processIdentifier,
                    "scenePoints": [view.frame.width, view.frame.height], "backingScale": panel.backingScaleFactor]
                if let failure { result["failure"] = failure }
                try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                    .write(to: movie.directory.appendingPathComponent("observations.json"))
            }
            do {
                try await Task.sleep(for: .milliseconds(450))
                record("press Close thread")
                try pressReadingPanelClose(in: panel, identifier: "agent-reading-panel-frame")
                try await wait("Close did not withdraw input") { host.messageMotion.active && !scene.inputInteractionReady }
                if reverse {
                    try await Task.sleep(for: .milliseconds(240))
                    guard host.selected == agent, host.messageMotion.active else { throw PluginContractError("Missed the in-flight return") }
                    record("reopen Agent during fold")
                    host.open(agent)
                    guard !scene.inputInteractionReady else { throw PluginContractError("Reopening bypassed the return flip") }
                    try await waitForEditor()
                    guard host.dockDraft === draft, draft.text == retainedText else {
                        throw PluginContractError("The reopened task lost its draft")
                    }
                    record("reopened editor")
                    try await Task.sleep(for: .milliseconds(260))
                    record("press Close thread again")
                    try pressReadingPanelClose(in: panel, identifier: "agent-reading-panel-frame")
                }
                try await wait("Overview did not regain the bar") { host.selected == nil && scene.overviewVisible && !scene.inputOpen }
                try await wait("Dock did not release the reading column") {
                    scene.harnessSeat == nil && abs(scene.capsuleFrame.midX - view.bounds.midX) < 1
                }
                guard let travel: MokuHorizontalTravelView = firstView(in: view, matching: { _ in true }) else {
                    throw PluginContractError("Missing Dock carrier")
                }
                // Let the model destination commit before sampling its two native axes.
                try await Task.sleep(for: .milliseconds(80))
                try await wait("Dock did not finish its lift") { travel.presentationCorrection == .zero }
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                record("failed")
                try saveObservations(failure: String(describing: error))
                try await movie.finish()
                throw error
            }
            try await movie.finish()
            let resting = scene.capsuleFrame
            let sameForeground = foreground == NSWorkspace.shared.frontmostApplication?.processIdentifier
            guard sameForeground, resting.width == 168, abs(resting.midX - view.bounds.midX) < 1,
                  host.dockDraft !== draft, host.dockDraft.text.isEmpty else {
                let failure = "Overview handoff: foreground unchanged=\(sameForeground), frame=\(resting), "
                    + "released draft=\(host.dockDraft !== draft), empty draft=\(host.dockDraft.text.isEmpty)"
                record("failed handoff")
                try saveObservations(failure: failure)
                throw PluginContractError(failure)
            }
            try saveObservations()
        }
    }
}
