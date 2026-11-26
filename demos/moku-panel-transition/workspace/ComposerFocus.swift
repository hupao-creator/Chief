import AppKit
import ChiefComposition
import ChiefCore
import ChiefPluginAPI
import SwiftUI
@testable import ChiefUI

@main @MainActor private enum ComposerFocus {
    final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task {
            do { try await replay() }
            catch { print("Focus replay failed:", error); exit(1) }
            app.terminate(nil)
        }
        app.run()
    }

    static func wait(_ label: String, until predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(12)
        while !predicate() {
            guard .now < deadline else { throw PluginContractError(label) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    static func replay() async throws {
        try prepareIsolatedNativeReplay()
        let args = CommandLine.arguments
        guard args.count == 4, let screen = NSScreen.screens.max(by: { $0.frame.maxX < $1.frame.maxX }) else {
            throw PluginContractError("Expected a private profile, two Agent threads and a display")
        }
        let profile = URL(fileURLWithPath: args[1])
        guard profile.lastPathComponent == "profile", profile.deletingLastPathComponent().lastPathComponent.hasPrefix("me2e-")
        else { throw PluginContractError("Expected the isolated e2e profile") }
        let preferences = DesktopPreferences(directory: profile)
        try preferences.setOnboardingCompleted(true)
        let model = NativeWorkspaceModel(client: RuntimeClient(profile: try RuntimeProfile(dataDirectory: profile)),
            preferences: preferences, plugins: try NativePlugins.make())
        let host = NativeWorkspacePresentation(workspace: model)
        // Both windows keep local responder chains without acquiring the user's keyboard.
        let origin = NSPoint(x: screen.frame.maxX + 12, y: screen.frame.minY)
        func makePanel(_ size: NSSize) -> Panel {
            let panel = Panel(contentRect: NSRect(origin: origin, size: size),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.ignoresMouseEvents = true
            panel.setFrameOrigin(origin)
            return panel
        }
        let panel = makePanel(.init(width: 1440, height: 900))
        let other = makePanel(.init(width: 320, height: 80))
        let otherEditor = NSTextView(frame: NSRect(origin: .zero, size: other.frame.size))
        other.contentView = otherEditor
        guard other.makeFirstResponder(otherEditor) else { throw PluginContractError("Missing second window responder") }
        let workspace = NativeWorkspaceView(model: model, presentation: host)
        let view = NSHostingView(rootView: workspace.environment(\.scenePhase, .active))
        panel.contentView = view
        guard [panel, other].allSatisfy({ panel in !NSScreen.screens.contains { $0.frame.intersects(panel.frame) } }) else {
            throw PluginContractError("Replay windows must stay offscreen")
        }
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil); other.orderOut(nil) }
        model.start()
        let scene = host.scene
        try await wait("Workspace did not load") { model.hasInitialContent && scene.overviewVisible }

        func sendKey(_ value: String, code: UInt16, to window: NSWindow) {
            for kind in [NSEvent.EventType.keyDown, .keyUp] {
                let event = NSEvent.keyEvent(with: kind, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    characters: value, charactersIgnoringModifiers: value, isARepeat: false, keyCode: code)!
                window.sendEvent(event)
            }
        }
        func type(_ value: String, code: UInt16) throws {
            guard let editor = panel.firstResponder as? NSTextView, editor.isEditable else {
                throw PluginContractError("No editable responder for the selected draft")
            }
            let before = host.dockDraft.text as NSString
            let expected = before.replacingCharacters(in: editor.selectedRange(), with: value)
            sendKey(value, code: code, to: panel)
            guard host.dockDraft.text == expected && editor.string == expected else {
                throw PluginContractError("Key expected \(expected), draft \(host.dockDraft.text), editor \(editor.string)")
            }
        }
        let first = args[2], second = args[3]
        var saved: [String: String] = [:]
        for thread in [first, second, first] {
            try await wait("Card did not become interactive") {
                host.canvas.visibleFrame(for: thread) != nil && host.canvas.allowsActivation(cardID: thread)
            }
            let card = host.canvas.visibleFrame(for: thread)!
            clickReplayWindow(panel, at: CGPoint(x: card.midX, y: view.bounds.height - card.midY))
            try await wait("Card click did not open the Agent") { host.selected?.threadID == JSONText(thread) }
            try await wait("Visible Agent editor did not acquire its task's input target and responder") {
                scene.inputInteractionReady && scene.inputOpen && host.dockInputAvailable
                    && (panel.firstResponder as? NSTextView)?.isEditable == true
            }
            guard host.agentInputTarget?.threadID == JSONText(thread),
                  host.dockThread?.observation.latestExecution?.status == .running,
                  host.dockDraft.text == saved[thread, default: ""] else {
                throw PluginContractError("Unexpected task, execution status or restored draft")
            }
            try type("a", code: 0)
            let editor = panel.firstResponder as! NSTextView
            if thread == second {
                let draft = host.dockDraft.text
                view.rootView = workspace.environment(\.scenePhase, .inactive)
                panel.orderOut(nil)
                other.orderFrontRegardless()
                guard other.firstResponder === otherEditor else { throw PluginContractError("Agent took the other window's focus") }
                sendKey("b", code: 11, to: other)
                guard otherEditor.string == "b", host.dockDraft.text == draft else {
                    throw PluginContractError("Key crossed window or draft ownership")
                }
                other.orderOut(nil)
                panel.orderFrontRegardless()
                view.rootView = workspace.environment(\.scenePhase, .active)
                try await wait("Returning workspace lost its editor") { panel.firstResponder === editor }
                try type("c", code: 8)
                print("Window-local keys stayed with their own drafts through departure and return")
            }
            // Start outside the composer so a click has to acquire it through native hit testing.
            guard panel.makeFirstResponder(nil), panel.firstResponder !== editor else {
                throw PluginContractError("Could not move focus away from the composer")
            }
            func clickPoint() -> CGPoint {
                editor.convert(CGPoint(x: editor.bounds.midX, y: editor.bounds.midY), to: nil)
            }
            try await wait("Expanded input did not expose its text view to native hit testing") {
                guard let parent = view.superview else { return false }
                return view.hitTest(parent.convert(clickPoint(), from: nil)) === editor
            }
            clickReplayWindow(panel, at: clickPoint())
            guard panel.firstResponder === editor else { throw PluginContractError("Click missed the native editor") }
            // Deliver the next physical input on a separate AppKit event-loop turn.
            try await Task.sleep(for: .milliseconds(20))
            try type("x", code: 7)
            saved[thread] = host.dockDraft.text
            print("Agent", thread, "received autofocus and click input:", host.dockDraft.text)
            try pressReadingPanelClose(in: panel, identifier: "agent-reading-panel-frame")
            try await wait("Did not return to Overview") { host.selected == nil && scene.overviewVisible && !scene.inputOpen }
        }
        scene.toggleInput(focusOnOpening: true)
        try await wait("Compose did not focus the Chief draft") { (panel.firstResponder as? NSTextView)?.isEditable == true }
        guard host.dockDraft === host.draft, host.draft.text.isEmpty else { throw PluginContractError("Overview inherited Agent text") }
        try type("c", code: 8)
        guard !NSApp.isActive, !panel.isKeyWindow, !other.isKeyWindow else { throw PluginContractError("Replay acquired foreground focus") }
        print("Overview received its first key in the Chief draft")
    }
}
