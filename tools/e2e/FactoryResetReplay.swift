import AppKit
import ChiefCore
import ChiefUI
import SwiftUI

private struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@main @MainActor
struct FactoryResetReplay {
    static func main() throws {
        try prepareIsolatedNativeReplay()
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let profile = workspace.appendingPathComponent("profile").path
        // The driver can confirm only its own explicit, temporary profile.
        guard CommandLine.arguments.dropFirst().prefix(4).elementsEqual([
            "--data-dir", profile, "--runtime", workspace.appendingPathComponent("chief-runtime").path
        ]) else { throw Failure("Missing isolated profile or Runtime") }
        ReplayApp.main()
    }
}

@MainActor private struct ReplayApp: App {
    @State private var session = WorkspaceSession()
    var body: some Scene {
        Window("Factory Reset Replay", id: "workspace") {
            WorkspaceWindow(session: session).frame(minWidth: 900, minHeight: 720)
                .task { await run() }
        }
    }

    private func record(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    private func wait(_ message: String, timeout: Duration = .seconds(35), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() {
            if let error = session.error { throw Failure(error) }
            if ContinuousClock.now >= deadline { throw Failure(message) }
            try await Task.sleep(for: .milliseconds(60))
        }
    }

    private func find(_ parent: NSView?, _ matches: (NSView) -> Bool) -> NSView? {
        guard let parent else { return nil }
        if matches(parent) { return parent }
        for child in parent.subviews {
            if let view = find(child, matches) { return view }
        }
        return nil
    }

    private func run() async {
        let marker = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("confirmed")
        do {
            try await wait("workspace did not connect") { session.model?.runtimeAvailable == true }
            guard let model = session.model, let presentation = session.presentation else { throw Failure("Missing workspace") }
            if FileManager.default.fileExists(atPath: marker.path) {
                try await wait("setup did not mount after restart") {
                    let snapshot = presentation.interactionSnapshot()
                    return snapshot["page"]?.stringValue == "onboarding" && snapshot["mounted"]?.boolValue == true
                        && snapshot["onboarding"]?["admitted"]?.boolValue == true
                }
                let state = try await model.invoke("state:load")
                let before = try JSONValue(data: Data(contentsOf: marker))
                guard state["settings"] == before["defaults"], state["threads"]?.arrayValue?.contains(where: {
                    $0["id"] == before["oldChief"]
                }) == false, !model.preferences.onboardingCompleted else { throw Failure("Old profile state survived restart") }
                try Data("passed".utf8).write(to: marker.deletingLastPathComponent().appendingPathComponent("passed"))
                record("Restart mounted setup with original default settings and fresh history")
                session.quit()
                return
            }
            let initial = try await model.invoke("state:load")
            guard var settings = initial["settings"]?.objectValue, var moku = settings["moku"]?.objectValue,
                  let revision = initial["settingsRevision"], let oldChief = initial["threads"]?.arrayValue?.first?["id"] else {
                throw Failure("Missing initial profile state")
            }
            moku["routingPreset"] = .text(moku["routingPreset"]?.stringValue == "economy" ? "performance" : "economy")
            settings["moku"] = .object(moku)
            let saved = try await model.invoke("app:update-settings", args: [.object(["settings": .object(settings), "expectedSettingsRevision": revision])])
            guard saved["status"]?.stringValue == "saved" else { throw Failure("Fixture settings were not saved") }
            try await wait("Overview Settings action unavailable") { presentation.interactionActions.contains("settings.open") }
            guard let main = NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible && $0.canBecomeKey }) else {
                throw Failure("Missing visible workspace window")
            }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            main.makeKeyAndOrderFront(nil)
            try presentation.performInteraction(.openSettings)
            let eye: () -> NSView? = {
                find(main.contentView) { $0.accessibilityIdentifier() == "settings-reset-eye" }
            }
            try await wait("Settings eye did not mount") { eye() != nil && presentation.interactionSnapshot()["transitioning"]?.boolValue == false }
            guard let view = eye(), let window = view.window else { throw Failure("Missing window") }
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(400))
            try await wait("Isolated test window could not become key") { window.isKeyWindow }
            let center = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
            guard let contentView = window.contentView,
                  let hit = contentView.hitTest(contentView.superview?.convert(center, from: nil) ?? center),
                  hit === view || hit.isDescendant(of: view) else {
                let hit = window.contentView.flatMap { $0.hitTest($0.superview?.convert(center, from: nil) ?? center) }
                throw Failure("Eye at \(center), \(view.bounds) is covered by \(String(describing: hit))")
            }
            func mouse(_ type: NSEvent.EventType, _ point: NSPoint) async throws {
                guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { throw Failure("Missing event") }
                NSApp.postEvent(event, atStart: false)
                try await Task.sleep(for: .milliseconds(35))
            }
            try await mouse(.leftMouseDown, center)
            try await Task.sleep(for: .milliseconds(2700))
            try await mouse(.leftMouseUp, center)
            try await Task.sleep(for: .milliseconds(550))
            guard window.attachedSheet == nil else { throw Failure("Early release opened confirmation") }
            let outside = view.convert(NSPoint(x: view.bounds.maxX + 25, y: view.bounds.midY), to: nil)
            try await mouse(.leftMouseDown, center)
            try await mouse(.leftMouseDragged, outside)
            try await Task.sleep(for: .milliseconds(3200))
            try await mouse(.leftMouseUp, outside)
            guard window.attachedSheet == nil else { throw Failure("Cancelled drag opened confirmation") }
            let buttons = [session.locale.text("取消", "Cancel"), session.locale.text("抹掉并重新启动", "Erase and Restart")]
            for (index, title) in buttons.enumerated() {
                try await mouse(.leftMouseDown, center)
                try await Task.sleep(for: .milliseconds(2600))
                guard window.attachedSheet == nil else { throw Failure("Confirmation appeared early") }
                try await wait("Holding the eye did not open confirmation", timeout: .seconds(2)) { window.attachedSheet != nil }
                guard let sheet = window.attachedSheet, let button = find(sheet.contentView, {
                    ($0 as? NSButton)?.title == title
                }) as? NSButton else { throw Failure("Confirmation button missing") }
                if index == 0 {
                    // Dismiss while still held. Continued pressure must never reopen the entry.
                    button.performClick(nil)
                    try await Task.sleep(for: .milliseconds(3400))
                    try await mouse(.leftMouseUp, center)
                    let state = try await model.invoke("state:load")
                    guard window.attachedSheet == nil, state["settings"] == .object(settings),
                          model.preferences.onboardingCompleted else { throw Failure("Cancel changed data or repeated the hold") }
                    record("Early release, drag cancellation and confirmation cancellation passed")
                } else {
                    try await mouse(.leftMouseUp, center)
                    try JSONValue.object(["defaults": initial["settings"]!, "oldChief": oldChief]).encodedData().write(to: marker)
                    button.performClick(nil)
                    try await wait("Confirmed reset did not restart") { false }
                }
            }
        } catch {
            FileHandle.standardError.write(Data(("Replay failed: " + error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
