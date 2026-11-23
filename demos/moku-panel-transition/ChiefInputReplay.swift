import AppKit
import ChiefCore
import ChiefPluginAPI
import SwiftUI
import ScreenCaptureKit
@testable import ChiefPluginUI
@testable import ChiefUI

private struct ChiefInputReplayFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor func replayChiefInput() async throws {
    let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
    if CommandLine.arguments.contains("--expect-unavailable-sounds") {
        let resources = URL(fileURLWithPath: "/System/iOSSupport/System/Library/PrivateFrameworks/UIKitCore.framework/Resources")
        for file in ["key_press_click.caf", "key_press_delete.caf"] {
            try require((try? Data(contentsOf: resources.appendingPathComponent(file))) == nil, "Expected unavailable " + file)
        }
    }
    let hostDirectory = try JSONDecoder().decode(RuntimeHostDirectory.self, from: Data(
        #"{"reference":{"hostID":"fixture-host","path":"/fixture/Old directory"},"entries":[]}"#.utf8))
    let storage = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let folder = storage.appendingPathComponent("Project 空", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let files = ["one.txt", "two.txt"].map { storage.appendingPathComponent($0) }
    let capacityFiles = files + (3...20).map { storage.appendingPathComponent("file-\($0).txt") }
    let fileIDs = Dictionary(uniqueKeysWithValues: capacityFiles.map { ($0, UUID().uuidString.lowercased()) })
    for file in capacityFiles { try Data(file.lastPathComponent.utf8).write(to: file) }
    let picker = try NativeComposerServices.devicePicker(cwd: JSONText(storage.path))
    try require(picker.canChooseFiles && picker.canChooseDirectories && picker.allowsMultipleSelection,
        "The primary macOS chooser must allow files and folders together")
    var selection: [URL] = []
    var pickerVisits = 0
    var staged: [URL] = []
    let services = NativeComposerServices(chooseItems: { _, _ in
        pickerVisits += 1
        return selection
    }, stageFiles: { selected, _ in
        try selected.map { file in
            guard case .file(let url) = file.source, let id = fileIDs[url] else {
                throw ChiefInputReplayFailure(description: "Unexpected item in file staging: \(file.name)")
            }
            staged.append(url)
            return .init(id: JSONText(id), path: JSONText(url.path), name: JSONText(file.name),
                         mimeType: JSONText(file.mimeType), size: file.size, kind: .file)
        }
    }, hostDirectory: { _, _ in hostDirectory }, discardAttachments: { _ in })
    let mention = JSONValue.object(["kind": .text("mention"), "pathType": .text("directory"),
                                    "name": .text(folder.lastPathComponent), "path": .text(folder.path)])
    let fileParts = files.map { JSONValue.object(["kind": .text("local-file"),
                                                  "file": .object(["id": .text(fileIDs[$0]!)])]) }
    let surface = "Overview Chief Dock"
    let draft = NativeComposerDraft(services: services)
    let scene = NativeMokuSceneState()
    scene.setComposerContext(draft, opensInput: true, autofocus: false)
    let panel = ComposerReplayPanel(contentRect: NSRect(x: 100, y: 100, width: 720, height: 400),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.ignoresMouseEvents = true
    var sent: [JSONValue] = []
    var catalogLoads = 0
    let send: (NativeComposerSubmission) async throws -> Void = {
        sent.append($0.input(knownDirectoryReferencesAsText: true))
    }
    var stops = 0
    func dock(running: Bool) -> some View {
        NativeMokuScene(state: scene) { Color.clear } dock: {
            NativeMokuDock(state: scene, draft: draft, cwd: "/fixture", running: running, loadMentionDirectories: {
                catalogLoads += 1
                return [.init(name: "Fixture", path: "/fixture/Fixture")]
            }, onSend: send, onCancel: { stops += 1 })
        } settings: { EmptyView() }
            .environment(\.scenePhase, .active).environment(\.locale, Locale(identifier: "en"))
    }
    let host = NSHostingView(rootView: dock(running: false))
    panel.contentView = host
    guard let edge = NSScreen.screens.map({ $0.frame.maxX }).max() else {
        throw ChiefInputReplayFailure(description: "Missing screen for offscreen fixture")
    }
    panel.setFrameOrigin(CGPoint(x: edge + 20, y: 120))
    panel.orderBack(nil)
    try require(NSScreen.screens.allSatisfy { !$0.frame.intersects(panel.frame) }, "Typing replay must stay offscreen")
    defer { panel.close() }

    let content = panel.contentView!
    func focusEditor() async throws -> NSTextView {
        let deadline = ContinuousClock.now + .seconds(4)
        while ContinuousClock.now < deadline {
            if let editor = find(content, NSTextView.self, matching: { $0.isEditable }), panel.makeFirstResponder(editor) {
                return editor
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ChiefInputReplayFailure(description: "\(surface) did not mount its native editor")
    }
    func click(_ point: NSPoint) {
        func mouse(_ kind: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: kind, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let up = mouse(.leftMouseUp)
        NSApp.postEvent(up, atStart: true)
        panel.sendEvent(mouse(.leftMouseDown))
        if NSApp.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: false) === up {
            _ = NSApp.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true)
            panel.sendEvent(up)
        }
    }

    func action(_ id: String, label: String, enabled: Bool) async throws -> CGRect {
        let deadline = ContinuousClock.now + .seconds(5)
        var observed = [[String: String]]()
        repeat {
            observed = try await button("moku-send", "moku-stop")
            if observed.count == 1, let control = observed.first, control["id"] == id,
               control["role"] == "AXButton", control["label"] == label, control["enabled"] == String(enabled),
               let frame = control["frame"] {
                let rect = NSRectFromString(frame)
                if rect.size == CGSize(width: 32, height: 32) { return rect }
            }
            try await Task.sleep(for: .milliseconds(30))
        } while ContinuousClock.now < deadline
        throw ChiefInputReplayFailure(description: "Expected one \(label) button enabled=\(enabled), found \(observed)")
    }
    func press(_ id: String) async throws {
        let controls = try await button(id, press: true)
        try require(controls.count == 1 && controls[0]["press"] == "0", "AXPress failed: \(controls)")
    }
    func checkOverviewActions() async throws {
        let editor = try await focusEditor()
        try await Task.sleep(for: .milliseconds(500))
        let seat = try await action("moku-send", label: "Send", enabled: false)
        func checkSeat(_ control: CGRect) throws {
            try require(abs(control.midX - seat.midX) <= 0.5 && abs(control.midY - seat.midY) <= 0.5,
                "Overview action moved from \(seat) to \(control)")
        }
        guard let nativeSend = find(content, NSButton.self, matching: { $0.identifier?.rawValue == "moku-send" }) else {
            throw ChiefInputReplayFailure(description: "Missing native Send hit target")
        }
        let center = nativeSend.convert(NSPoint(x: nativeSend.bounds.midX, y: nativeSend.bounds.midY), to: nil)
        click(center)
        host.rootView = dock(running: true)
        editor.insertText(" \u{FEFF}", replacementRange: editor.selectedRange())
        editor.keyDown(with: key("\r", code: 36, panel: panel))
        let stop = try await action("moku-stop", label: "Stop Chief", enabled: true)
        try checkSeat(stop)
        try require(sent.isEmpty && stops == 0, "Empty Return or disabled Send performed an action")
        try await press("moku-stop")
        try require(stops == 1, "Stop Chief AXPress missed its cancellation")
        click(center)
        let deadline = ContinuousClock.now + .seconds(2)
        while stops == 1 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try require(stops == 2 && sent.isEmpty, "Clicking the shared seat did not stop Chief (count \(stops))")
        editor.keyDown(with: key("\r", code: 36, modifiers: .command, panel: panel))
        try require(editor.string.hasSuffix("\n") && stops == 2 && sent.isEmpty, "Command-Return did not insert a newline")
        editor.selectAll(nil)
        editor.insertText("Follow up", replacementRange: editor.selectedRange())
        try checkSeat(try await action("moku-send", label: "Send", enabled: true))
        click(center)
        try require(sent == [textInput("Follow up")] && stops == 2, "Clicking the shared seat did not send the running follow-up")
        sent.removeAll()
        scene.setInputOpen(true)
        _ = try await focusEditor()
        try await Task.sleep(for: .milliseconds(500))
        try checkSeat(try await action("moku-stop", label: "Stop Chief", enabled: true))
        print("Passed Overview action at \(seat): disabled Send, whitespace Return, Stop AXPress and click, running Send click.")
    }
    let verifyActions = CommandLine.arguments.contains("--verify-actions")
    if verifyActions { try await checkOverviewActions() }
    let editor = try await focusEditor()
    if CommandLine.arguments.contains("--replay-typing-cadence") {
        try await replayTypingCadence(editor, draft: draft, panel: panel)
        try require(!NSApp.isActive && foreground == NSWorkspace.shared.frontmostApplication?.processIdentifier,
                    "Typing replay acquired foreground focus")
        return
    }
    try replayTypingFeedback(editor, draft: draft, panel: panel)
    editor.keyDown(with: key("@", code: 19, modifiers: .shift, unmodified: "2", panel: panel))
    try await Task.sleep(for: .milliseconds(500))
    try require(editor.string == "@" && draft.text == "@" && catalogLoads == 0 && scene.dockMentionHitRect == nil
        && !hasCompletion(content), "\(surface) did not treat typed @ as ordinary text")
    editor.keyDown(with: key("\r", code: 36, panel: panel))
    try require(sent == [textInput("@")], "\(surface) did not send a bare @ on Return")

    scene.setInputOpen(true)
    let reopenedEditor = try await focusEditor()
    reopenedEditor.insertText("@", replacementRange: reopenedEditor.selectedRange())

    // Use a private pasteboard so the replay leaves the clipboard alone.
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    try require(pasteboard.setString("draft@example.com", forType: .string)
        && reopenedEditor.readSelection(from: pasteboard, type: .string), "\(surface) could not paste text")
    reopenedEditor.setSelectedRange(NSRange(location: 1, length: 5))
    reopenedEditor.insertText("team", replacementRange: reopenedEditor.selectedRange())
    try require(draft.text == "@team@example.com" && draft.directories.isEmpty, "\(surface) changed pasted or edited @ text")
    reopenedEditor.keyDown(with: key("\r", code: 36, panel: panel))
    try require(sent == [textInput("@"), textInput("@team@example.com")], "\(surface) did not send literal @ text on Return")
    try require(draft.text.isEmpty, "\(surface) did not consume its submitted draft")

    scene.setInputOpen(true)
    let plainEditor = try await focusEditor()
    plainEditor.insertText("ordinary request", replacementRange: plainEditor.selectedRange())
    plainEditor.keyDown(with: key("\r", code: 36, panel: panel))
    try require(sent == [textInput("@"), textInput("@team@example.com"), textInput("ordinary request")],
        "\(surface) did not send ordinary text")
    scene.setInputOpen(true)
    let pickerEditor = try await focusEditor()
    func pick(_ urls: [URL]) async throws {
        selection = urls
        let previous = pickerVisits
        // The capsule can still be travelling after Return or a chip-strip resize.
        // Deliver the window-local click after its 420ms transition settles.
        try await Task.sleep(for: .milliseconds(500))
        let editor = try await focusEditor()
        let deadline = ContinuousClock.now + .seconds(4)
        guard let seat = editor.enclosingScrollView else { throw ChiefInputReplayFailure(description: "Missing editor seat") }
        let bounds = seat.convert(seat.bounds, to: nil)
        let point = NSPoint(x: bounds.minX - 14, y: bounds.midY)
        click(point)
        while previous == pickerVisits || draft.importing {
            if ContinuousClock.now >= deadline {
                let hit = content.hitTest(content.superview!.convert(point, from: nil))
                throw ChiefInputReplayFailure(description: "Picker did not finish at \(point), editor \(bounds), visits \(pickerVisits)/\(previous), open \(scene.inputOpen), submitting \(draft.submitting), hit \(String(describing: hit))")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        try require(draft.error == nil, draft.error ?? "Picker failed")
    }
    staged = []
    try await pick([folder])
    try await pick([])
    try require(draft.directories.map(\.path) == [JSONText(folder.path)] && draft.attachments.isEmpty
        && draft.canSubmit && staged.isEmpty, "Cancel changed the folder-only draft")
    if verifyActions { _ = try await action("moku-send", label: "Send", enabled: true) }
    pickerEditor.keyDown(with: key("\r", code: 36, panel: panel))
    try require(sent.last == .object(["parts": .array([mention])]), "Folder-only submission lost its path")
    scene.setInputOpen(true)
    if verifyActions {
        _ = try await focusEditor()
        try await pick([files[0]])
        _ = try await action("moku-send", label: "Send", enabled: true)
        try await press("moku-send")
        try require(sent.last == .object(["parts": .array([fileParts[0]])]),
            "A file alone did not send through AXPress")
        // AXPress is served on another event loop. Reopen through the real
        // capsule after the submitted editor has retired.
        let deadline = ContinuousClock.now + .seconds(5)
        while scene.inputLeaving && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try require(!scene.inputOpen && !scene.inputLeaving, "File-only send did not fold the editor")
        try await press("moku-open-input")
        _ = try await action("moku-stop", label: "Stop Chief", enabled: true)
        print("Passed file-only AXPress, folder-only Return and reopening the empty running editor through AXPress.")
        staged = []
    }
    let mixedEditor = try await focusEditor()
    try await pick([files[0], folder, files[1]])
    try await pick([folder])
    try require(staged == files && draft.attachments.count == 2 && draft.directories.count == 1,
        "Mixed selection did not stage both files and reference the folder once")
    mixedEditor.keyDown(with: key("\r", code: 36, panel: panel))
    try require(sent.last == .object(["parts": .array([mention] + fileParts)])
        && draft.attachments.isEmpty && draft.directories.isEmpty, "Mixed submission or draft consumption failed")
    print("Passed \(surface): attachment plus, cancel, folder-only and mixed submissions.")
    print("Passed \(surface): typed @ without completion, pasted and edited @ text, and sent both literal and ordinary text.")

    let full = NativeComposerDraft(services: services)
    selection = capacityFiles
    await full.chooseItems(cwd: JSONText(storage.path))
    selection = [folder]
    await full.chooseItems(cwd: JSONText(storage.path))
    try require(full.error == nil && full.attachments.count == 20 && full.directories.map(\.path) == [JSONText(folder.path)],
        "A full file allowance blocked an independent folder reference")
    for index in 1..<50 {
        try require(full.insertDirectory(.init(name: "Project", path: JSONText("/fixture/\(index)"))), "Could not fill folder allowance")
    }
    await full.removeAttachment(full.attachments[0].id)
    selection = [storage, files[0]]
    await full.chooseItems(cwd: JSONText(storage.path))
    try require(full.error != nil && full.directories.count == 50 && full.attachments.count == 19,
        "Over-limit mixed selection changed the draft")
    let persistence = NativeComposerDraftPersistence(storageDirectory: storage, scope: JSONText(UUID().uuidString))
    let previous = NativeComposerDraft(services: services, persistence: persistence)
    previous.text = "Old @ draft"
    let legacy = NativeComposerDirectory(name: "Old directory", path: "/fixture/Old directory")
    try require(previous.insertDirectory(legacy), "Could not seed a persisted completion reference")
    let reopened = NativeComposerDraft(services: services, persistence: persistence)
    var recovered: JSONValue?
    await reopened.submit({ recovered = $0.input(knownDirectoryReferencesAsText: true) }, optimisticallyClear: true)
    try require(recovered == textInput("Old @ draft\n/fixture/Old directory"), "Persisted mention lost text or emitted a reference")
    try require(reopened.insertDirectory(legacy), "Could not seed the saved path before opening the host picker")
    let directory = try await reopened.hostDirectory()
    try require(reopened.chooseHostDirectory(directory.reference), "Host directory selection failed")
    let picked = NativeComposerDirectory(name: legacy.name, path: legacy.path, hostID: "fixture-host")
    try require(reopened.directories == [picked], "The host picker did not replace the saved catalog reference")
    await reopened.submit({ recovered = $0.input(knownDirectoryReferencesAsText: true) }, optimisticallyClear: true)
    try require(recovered == .object(["parts": .array([.object([
        "kind": .string("mention"), "name": .string(picked.name), "path": .string(picked.path), "pathType": .string("directory"),
    ])])]), "Explicit host directory did not preserve its structured reference")
    selection = [folder]
    await reopened.chooseItems(cwd: JSONText(storage.path))
    let restored = NativeComposerDraft(services: services, persistence: persistence)
    await restored.submit({ recovered = $0.input(knownDirectoryReferencesAsText: true) }, optimisticallyClear: true)
    try require(recovered == .object(["parts": .array([mention])]), "Restored device selection lost its directory mention")
    try require(!NSApp.isActive && foreground == NSWorkspace.shared.frontmostApplication?.processIdentifier,
        "Replay activated itself or the foreground app changed")
    print("Passed persisted Chief draft and explicit host directory serialization.")
}

// Route each keystroke through the window so changing the first responder also changes
// which editor receives feedback. The pauses separate the groups in an audio capture.
@MainActor private func replayTypingCadence(_ editor: NSTextView, draft: NativeComposerDraft, panel: NSPanel) async throws {
    let target = try await SCShareableContent.currentProcess.windows.first { $0.windowID == panel.windowNumber }
    guard let target else { throw ChiefInputReplayFailure(description: "Missing replay window for audio capture") }
    let config = SCStreamConfiguration()
    config.width = 16
    config.height = 16
    config.capturesAudio = true
    config.excludesCurrentProcessAudio = false
    config.channelCount = 1
    config.sampleRate = 48000
    let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: target), configuration: config, delegate: nil)
    let output = TypingWaveform()
    try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.queue)
    try await stream.startCapture()
    func type(_ characters: String = "a", code: UInt16 = 0) {
        panel.sendEvent(key(characters, code: code, panel: panel))
    }
    let silent = CommandLine.arguments.contains("--expect-silent-typing")
        || CommandLine.arguments.contains("--expect-unavailable-sounds")
    var previousCount = 0
    var previousFrames = 0
    func checkOutput(_ label: String, clicks: Int) async throws {
        try await Task.sleep(for: .milliseconds(220))
        let (pulses, frames) = output.queue.sync { (output.onsets.dropFirst(previousCount), output.frames) }
        let start = pulses.first ?? 0
        let offsets = pulses.map { Int((($0 - start) * 1000).rounded()) }
        print("Audio [\(label)]: \(pulses.count) clicks, offsets (ms) \(offsets), \(frames - previousFrames) captured frames")
        try require(frames > previousFrames && pulses.count == (silent ? 0 : clicks), "Unexpected captured audio for " + label)
        previousCount += pulses.count
        previousFrames = frames
    }
    do {
        try await checkOutput("quiet before typing", clicks: 0)
        var expectedText = ""
        for interval in [120, 40, 20] {
            for _ in 0..<12 {
                type()
                try await Task.sleep(for: .milliseconds(interval))
            }
            expectedText += String(repeating: "a", count: 12)
            try require(draft.text == expectedText, "Continuous typing did not reach the Dock")
            try await checkOutput("12 keys at " + String(interval) + " ms", clicks: 12)
        }
        for _ in 0..<6 { type() }
        try await checkOutput("six keys in one event-loop turn", clicks: 6)
        let other = NSTextView(frame: .zero)
        panel.contentView!.addSubview(other)
        try require(panel.makeFirstResponder(other), "Could not move focus out of the Dock")
        type()
        try require(other.string == "a" && draft.text.count == 42, "Typing followed the wrong responder")
        try await checkOutput("other editor", clicks: 0)
        try require(panel.makeFirstResponder(editor), "Could not return focus to the Dock")
        other.removeFromSuperview()
        type("d", code: 2)
        try require(draft.text.hasSuffix("ad"), "The first character after refocus was lost")
        try await checkOutput("first key after refocus", clicks: 1)
        for _ in 0..<12 {
            type("\u{7F}", code: 51)
            try await Task.sleep(for: .milliseconds(20))
        }
        try require(draft.text == String(repeating: "a", count: 31), "Unexpected draft after rapid deletion")
        try await checkOutput("rapid Backspace", clicks: 12)

        panel.sendEvent(key("a", code: 0, repeating: true, panel: panel))
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        panel.sendEvent(key("\u{F728}", code: 117, modifiers: .function, panel: panel))
        try require(draft.text.count == 31, "Repeat and forward Delete changed the wrong text")
        try await checkOutput("auto-repeat and forward Delete", clicks: 2)

        draft.text = ""
        editor.setMarkedText("p", selectedRange: NSRange(location: 1, length: 0), replacementRange: editor.selectedRange())
        type("i", code: 34)
        editor.setMarkedText("pin", selectedRange: NSRange(location: 3, length: 0),
                             replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        editor.insertText("拼", replacementRange: editor.markedRange())
        try require(draft.text == "拼" && !editor.hasMarkedText(), "Unexpected composition commit")
        try await checkOutput("composing key, marked updates and commit", clicks: 1)

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        try require(pasteboard.setString("paste", forType: .string)
            && editor.readSelection(from: pasteboard, type: .string), "Private paste failed")
        panel.sendEvent(key("\u{F703}", code: 124, modifiers: .function, panel: panel))
        panel.sendEvent(key("\r", code: 36, modifiers: .command, panel: panel))
        draft.text = "restored"
        try await checkOutput("paste, navigation, shortcut and restored draft", clicks: 0)
    } catch {
        try? await stream.stopCapture()
        throw error
    }
    try await stream.stopCapture()
    print("Passed mounted Dock typing and audio checks.")
}

@MainActor private func replayTypingFeedback(_ view: NSTextView, draft: NativeComposerDraft, panel: NSPanel) throws {
    guard let editor = view as? ComposerTextView, let play = editor.onTypingKey else {
        throw ChiefInputReplayFailure(description: "The mounted Chief Bar has no keyboard feedback")
    }
    var keys: [NativeComposerTypingKey] = []
    editor.onTypingKey = { keys.append($0); play($0) }
    defer { editor.onTypingKey = play }

    editor.keyDown(with: key("a", code: 0, panel: panel))
    editor.keyDown(with: key("a", code: 0, repeating: true, panel: panel))
    editor.keyDown(with: key("\u{7F}", code: 51, panel: panel))
    try require(draft.text == "a" && keys == [.character, .character, .delete], "Typing, repeat or Backspace feedback")

    // Exercise NSTextInputClient's marked-text lifecycle without changing the user's input source.
    editor.setMarkedText("p", selectedRange: NSRange(location: 1, length: 0), replacementRange: editor.selectedRange())
    editor.keyDown(with: key("i", code: 34, panel: panel))
    let composing = NSRange(location: 1, length: editor.string.utf16.count - 1)
    editor.setMarkedText("pin", selectedRange: NSRange(location: 3, length: 0), replacementRange: composing)
    editor.insertText("拼", replacementRange: editor.markedRange())
    try require(!editor.hasMarkedText() && draft.text == "a拼" && keys == [.character, .character, .delete, .character],
        "Marked text and its commit must share the single composing key-down")

    draft.text = "restore"
    editor.setSelectedRange(NSRange(location: 0, length: 0))
    editor.keyDown(with: key("\u{F728}", code: 117, modifiers: .function, panel: panel))
    try require(draft.text == "estore" && keys == [.character, .character, .delete, .character, .delete],
        "Draft restoration or forward Delete feedback")
    editor.keyDown(with: key("\u{F703}", code: 124, modifiers: .function, panel: panel))
    draft.text = ""
    try require(editor.string.isEmpty && keys.count == 5, "Navigation or programmatic clearing played a sound")
    print("Passed Chief Bar keyboard feedback: ordinary, repeat, both deletes, IME callbacks, navigation and draft updates.")
}

private func textInput(_ text: String) -> JSONValue {
    .object(["parts": .array([.object(["kind": .string("text"), "text": .text(text)])])])
}

private func require(_ condition: Bool, _ failure: String) throws {
    guard condition else { throw ChiefInputReplayFailure(description: failure) }
}

@MainActor private func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [],
                            unmodified: String? = nil, repeating: Bool = false, panel: NSPanel) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
        windowNumber: panel.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: unmodified ?? characters, isARepeat: repeating, keyCode: code)!
}

@MainActor private func find<T: NSView>(_ view: NSView, _ type: T.Type, matching: (T) -> Bool) -> T? {
    if let match = view as? T, matching(match) { return match }
    for child in view.subviews {
        if let match = find(child, type, matching: matching) { return match }
    }
    return nil
}

@MainActor private func hasCompletion(_ element: Any) -> Bool {
    accessibilityElement(element) { $0.accessibilityIdentifier() == "moku-directory-completion" } != nil
}

@MainActor private func accessibilityElement(_ element: Any, matching: (any NSAccessibilityProtocol) -> Bool) -> (any NSAccessibilityProtocol)? {
    guard let node = element as? any NSAccessibilityProtocol else { return nil }
    if matching(node) { return node }
    for child in node.accessibilityChildren() ?? [] {
        if let match = accessibilityElement(child, matching: matching) { return match }
    }
    return nil
}

private final class TypingWaveform: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "ChiefReplay.typing-waveform")
    private var lastSignal = -Double.infinity
    private(set) var onsets: [Double] = []
    private(set) var frames = 0

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let format = buffer.formatDescription?.audioStreamBasicDescription,
              format.mSampleRate == 48_000, format.mChannelsPerFrame == 1,
              format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32 else { return }
        let start = buffer.presentationTimeStamp.seconds
        try? buffer.withAudioBufferList { list, _ in
            guard let channel = list.first, let data = channel.mData else { return }
            let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self),
                                              count: Int(channel.mDataByteSize) / MemoryLayout<Float>.stride)
            frames += samples.count
            for (index, sample) in samples.enumerated() where abs(sample) > 0.0005 {
                let time = start + Double(index) / 48000
                if time - lastSignal > 0.003 { onsets.append(time) }
                lastSignal = time
            }
        }
    }
}
