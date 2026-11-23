import AppKit
import ChiefCore
import ChiefPluginAPI
import SwiftUI
@testable import ChiefPluginUI
@testable import ChiefUI

private struct ChiefInputReplayFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor func replayChiefInput() async throws {
    let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
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
        styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.ignoresMouseEvents = true
    var sent: [JSONValue] = []
    var catalogLoads = 0
    let send: (NativeComposerSubmission) async throws -> Void = {
        sent.append($0.input(knownDirectoryReferencesAsText: true))
    }
    let dock = NativeMokuScene(state: scene) { Color.clear } dock: {
        NativeMokuDock(state: scene, draft: draft, cwd: "/fixture", loadMentionDirectories: {
            catalogLoads += 1
            return [.init(name: "Fixture", path: "/fixture/Fixture")]
        }, onSend: send, onCancel: {})
    } settings: { EmptyView() }
    panel.contentView = NSHostingView(rootView: dock.environment(\.scenePhase, .active).environment(\.locale, Locale(identifier: "en")))
    panel.orderBack(nil)
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
    let editor = try await focusEditor()
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
        let editor = try await focusEditor()
        // The capsule can still be travelling after Return or a chip-strip resize.
        // Deliver the window-local click after its 420ms transition settles.
        try await Task.sleep(for: .milliseconds(500))
        let deadline = ContinuousClock.now + .seconds(4)
        guard let seat = editor.enclosingScrollView else { throw ChiefInputReplayFailure(description: "Missing editor seat") }
        let bounds = seat.convert(seat.bounds, to: nil)
        let point = NSPoint(x: bounds.minX - 14, y: bounds.midY)
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
        while previous == pickerVisits || draft.importing {
            try require(ContinuousClock.now < deadline, "Picker did not finish in \(surface) at \(point), editor \(bounds), visits \(pickerVisits)/\(previous)")
            try await Task.sleep(for: .milliseconds(10))
        }
        try require(draft.error == nil, draft.error ?? "Picker failed")
    }
    staged = []
    try await pick([folder])
    try await pick([])
    try require(draft.directories.map(\.path) == [JSONText(folder.path)] && draft.attachments.isEmpty
        && draft.canSubmit && staged.isEmpty, "Cancel changed the folder-only draft")
    pickerEditor.keyDown(with: key("\r", code: 36, panel: panel))
    try require(sent.last == .object(["parts": .array([mention])]), "Folder-only submission lost its path")
    scene.setInputOpen(true)
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

private func textInput(_ text: String) -> JSONValue {
    .object(["parts": .array([.object(["kind": .string("text"), "text": .text(text)])])])
}

private func require(_ condition: Bool, _ failure: String) throws {
    guard condition else { throw ChiefInputReplayFailure(description: failure) }
}

@MainActor private func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [],
                            unmodified: String? = nil, panel: NSPanel) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
        windowNumber: panel.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: unmodified ?? characters, isARepeat: false, keyCode: code)!
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
