@testable import ChiefUI
import AppKit
import ScreenCaptureKit

private struct ReplayFailure: Error, CustomStringConvertible { let description: String }

@MainActor enum VoiceDemoReplay {
    static func run(model: Workspace, directory: URL) async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await exercise(model: model, directory: directory)
            try """
                Short press, cancelled drag, 0.5s hold, preparation without an orb, first orb while listening,
                draft and selection, repeated hold, routing and resizing, audio playback without a transcript panel,
                interruption, left-click microphone mute and unmute, menu cancellation and right-click hang-up.

                """.write(to: directory.appending(path: "passed.txt"), atomically: true, encoding: .utf8)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Voice demo replay: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func exercise(model: Workspace, directory: URL) async throws {
        let main = try await wait("main window") { NSApp.windows.first { $0.identifier?.rawValue == "global-voice-demo" } }
        let wideSize = CGSize(width: 1020, height: 620)
        main.setContentSize(wideSize)
        main.collectionBehavior = [.auxiliary, .canJoinAllSpaces]
        main.center()
        try await activate(main)
        let compact = try await wait("mounted centered compact Bar") {
            nativeRect("voice-bar-frame", in: main).flatMap { abs($0.midX - main.frame.midX) < 2 ? $0 : nil }
        }
        let compactPoint = CGPoint(x: compact.midX, y: compact.midY)
        try await expect("idle Bar with no voice control") {
            model.voice.phase == .idle && !model.scene.inputOpen && !orbPresent(in: main)
        }
        try await capture(main, to: directory.appending(path: "overview.png"))
        let previous = NSApp.appearance
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        NSApp.appearance = NSAppearance(named: isDark ? .aqua : .darkAqua)
        try await capture(main, to: directory.appending(path: "overview-alternate.png"))
        NSApp.appearance = previous

        let away = CGPoint(x: compact.midX, y: compact.maxY + 35)
        try mouse(.leftMouseDown, at: compactPoint, in: main)
        try await Task.sleep(for: .milliseconds(85))
        try mouse(.leftMouseDragged, at: away, in: main)
        try await Task.sleep(for: .milliseconds(590))
        try mouse(.leftMouseUp, at: away, in: main)
        try await Task.sleep(for: .milliseconds(140))
        guard model.voice.phase == .idle, !model.scene.inputOpen, !orbPresent(in: main) else {
            throw ReplayFailure(description: "Dragging off the Bar opened voice or text")
        }

        try await record(main, to: directory.appending(path: "voice-glass.mp4")) {
            try await Task.sleep(for: .milliseconds(280))
            try await startWithHold(at: compactPoint, in: main, model: model) {
                // The call and its orb arrive before mouse-up, with no second action.
                try await firstListeningOrb(in: main, model: model)
            }
            try await expect("released compact hold leaves text folded") { model.voice.phase == .listening && !model.scene.inputOpen }
            _ = try await anchored("compact Bar", in: main)
            try await capture(main, to: directory.appending(path: "listening.png"))
            try await click("voice-orb", in: main)
            try await expect("left click mutes the compact orb") { model.voice.phase == .muted && orbPresent(in: main) }
            try await Task.sleep(for: .milliseconds(430))
            try await click("voice-orb", in: main)
            try await expect("second left click resumes listening") { model.voice.phase == .listening && orbPresent(in: main) }
            try await Task.sleep(for: .milliseconds(430))
            try await hangUp(.listening, in: main, model: model)
            guard !model.scene.inputOpen else { throw ReplayFailure(description: "Hanging up the compact Bar opened the editor") }
            // Leave enough recorded frames for the returning glass and its settled surface.
            try await Task.sleep(for: .milliseconds(700))
        }

        try await shortPress(at: compactPoint, in: main)
        let editor = try await wait("short press focused Chief's editor") {
            model.scene.inputOpen && model.voice.phase == .idle ? main.firstResponder as? NSTextView : nil
        }
        editor.insertText("发布说明的草稿", replacementRange: editor.selectedRange())
        let selection = NSRange(location: 2, length: 2)
        editor.setSelectedRange(selection)
        func selectionIntact() -> Bool {
            model.scene.inputOpen && main.firstResponder === editor && editor.selectedRange() == selection
                && model.chiefDraft.text == "发布说明的草稿"
        }
        let eyePoint = try await editorEye(in: main, compactWidth: compact.width)
        try await startWithHold(at: eyePoint, in: main, model: model)
        try await firstListeningOrb(in: main, model: model)
        try await expect("expanded eye hold preserves draft, selection and focus") { model.voice.phase == .listening && selectionIntact() }
        _ = try await anchored("expanded Chief Bar", in: main)
        try mouse(.leftMouseDown, at: eyePoint, in: main)
        try await Task.sleep(for: .milliseconds(670))
        guard model.voice.phase == .listening, selectionIntact() else {
            throw ReplayFailure(description: "Holding the eyes again interrupted the call or changed the draft selection")
        }
        try mouse(.leftMouseUp, at: eyePoint, in: main)
        try await Task.sleep(for: .milliseconds(130))
        guard model.voice.phase == .listening, selectionIntact() else {
            throw ReplayFailure(description: "Releasing a second hold changed the editor or voice session")
        }
        try await capture(main, to: directory.appending(path: "draft.png"))
        let beforeReply = try await playExample(in: main, model: model)
        try await capture(main, to: directory.appending(path: "reply.png"))
        try unchangedVoiceSurface(in: main, textBefore: beforeReply)
        try await voiceCommand("打断回复", model: model)
        try await expect("interrupted audio") { model.voice.phase == .listening && !model.voice.isPlayingReply }
        try await click("voice-orb", in: main)
        try await expect("muted input") { model.voice.phase == .muted && model.voice.microphoneMuted }
        _ = try await anchored("muted editor Bar", in: main)
        guard selectionIntact(), model.agentDraft.text.isEmpty else {
            throw ReplayFailure(description: "The spoken exchange changed an editor draft or selection")
        }
        try await capture(main, to: directory.appending(path: "muted.png"))
        try await click("voice-orb", in: main)
        try await expect("unmuted input while the orb and selection stay in place") {
            model.voice.phase == .listening && !model.voice.microphoneMuted && orbPresent(in: main) && selectionIntact()
        }

        try await click("voice-demo-task", in: main)
        try await expect("global voice in task") { model.taskOpen && model.scene.inputOpen && model.voice.phase == .listening }
        func taskBar(_ name: String, windowWidth: CGFloat) async throws -> CGRect {
            try await anchored(name, in: main) { bar in
                // The 40pt orb sits 16pt past the Bar and finishes 12pt inside the task column.
                abs(main.frame.width - windowWidth) < 2 && bar.midX > main.frame.midX
                    && abs(main.frame.maxX - bar.maxX - (16 + 40 + 12)) < 2
            }
        }
        let wideBar = try await taskBar("wide Claude column", windowWidth: wideSize.width)
        main.setContentSize(CGSize(width: 800, height: 540))
        let narrowBar = try await taskBar("narrow Claude column", windowWidth: 800)
        main.setContentSize(wideSize)
        let restored = try await taskBar("restored Claude column", windowWidth: wideSize.width)
        guard narrowBar.width < wideBar.width, abs(restored.width - wideBar.width) < 2 else {
            throw ReplayFailure(description: "Unexpected Claude Bar widths after resize: \(wideBar.width), \(narrowBar.width), \(restored.width)")
        }
        let taskEditor = try await wait("visible task editor") { main.contentView.flatMap { editable(in: $0) } }
        main.makeFirstResponder(taskEditor)
        taskEditor.insertText("保留第二段。", replacementRange: taskEditor.selectedRange())
        try await expect("independent task draft") { model.agentDraft.text == "保留第二段。" && model.voice.phase == .listening }
        try await capture(main, to: directory.appending(path: "task.png"))
        try await click("moku-send", in: main)
        try await expect("typed message went only to Claude") {
            model.agentMessages == ["保留第二段。"] && model.agentDraft.text.isEmpty && model.chiefMessages.isEmpty
                && model.chiefDraft.text == "发布说明的草稿" && model.voice.phase == .listening
        }
        try await click("voice-demo-back", in: main)
        try await expect("return to Chief") { !model.taskOpen && model.voice.phase == .listening }
        try await activate(main)
        _ = try await anchored("returned compact Bar", in: main) {
            abs($0.width - compact.width) < 2 && abs($0.midX - main.frame.midX) < 2
        }
        try await playExample(in: main, model: model, usingShortcut: true)
        let orb = try await wait("clickable speaking orb after return", seconds: 2) {
            guard model.voice.phase == .speaking, let rect = nativeRect("voice-orb", in: main),
                  hitView(at: CGPoint(x: rect.midX, y: rect.midY), in: main)?.identifier?.rawValue == "voice-orb"
            else { return nil as CGRect? }
            return rect
        }
        let point = CGPoint(x: orb.midX, y: orb.midY)
        let target = hitTarget(at: point, in: main)
        try await click("voice-orb", in: main)
        guard model.voice.microphoneMuted && model.voice.phase == .speaking && model.voice.isPlayingReply else {
            throw ReplayFailure(description: "Speaking orb at \(point) hit \(target), key=\(main.isKeyWindow), active=\(NSApp.isActive), phase=\(model.voice.phase), muted=\(model.voice.microphoneMuted), playing=\(model.voice.isPlayingReply)")
        }
        try await expect("audio finishes with microphone still muted", seconds: 9) {
            model.voice.phase == .muted && model.voice.microphoneMuted && !model.voice.isPlayingReply
        }
        try await voiceCommand("恢复收音", model: model)
        try await expect("ready for another turn") { model.voice.phase == .listening }
        try await playExample(in: main, model: model)
        try await hangUp(.speaking, in: main, model: model)
        guard !model.voice.isPlayingReply else { throw ReplayFailure(description: "Hanging up left the reply playing") }

        let restoredBar = try await wait("returned Chief Bar") { nativeRect("voice-bar-frame", in: main) }
        let restoredPoint = CGPoint(x: restoredBar.midX, y: restoredBar.midY)
        var trace = [draftSnapshot("before short press", at: restoredPoint, in: main, model: model)]
        do {
            try await shortPress(at: restoredPoint, in: main)
            // NSApp.postEvent enqueues the release. Let the window dispatch it before inspecting focus.
            try await Task.sleep(for: .milliseconds(30))
            trace.append(draftSnapshot("after release", at: restoredPoint, in: main, model: model))
            try await expect("restored Chief draft") {
                model.scene.inputOpen && (main.firstResponder as? NSTextView)?.string == "发布说明的草稿"
            }
        } catch {
            trace.append(draftSnapshot("at failure", at: restoredPoint, in: main, model: model))
            do { try await capture(main, to: directory.appending(path: "restored-failure.png")) }
            catch { trace.append("Could not capture restored-failure.png: \(error)") }
            throw ReplayFailure(description: ([String(describing: error)] + trace).joined(separator: "\n"))
        }
        let restoredEye = try await editorEye(in: main, compactWidth: compact.width)
        try await startWithHold(at: restoredEye, in: main, model: model)
        try await cancelPreparation(in: main, model: model)
        try await startWithHold(at: restoredEye, in: main, model: model)
        try await firstListeningOrb(in: main, model: model)
        try await click("voice-orb", in: main)
        try await expect("muting a newly opened call keeps its orb") { model.voice.phase == .muted && orbPresent(in: main) }
        try await hangUp(.muted, in: main, model: model)
    }

    private static func activate(_ window: NSWindow) async throws {
        guard !window.isKeyWindow || !NSApp.isActive else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        if !window.isKeyWindow || !NSApp.isActive {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = false
            configuration.addsToRecentItems = false
            let ownApp = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
            guard ownApp.processIdentifier == getpid() else { throw ReplayFailure(description: "Unexpected activation target") }
            window.makeKeyAndOrderFront(nil)
        }
        try await expect("visible key window") { window.isVisible && window.isKeyWindow && NSApp.isActive }
    }

    private static func editable(in view: NSView) -> NSTextView? {
        if let editor = view as? NSTextView, editor.isEditable, !editor.isHiddenOrHasHiddenAncestor,
           !editor.visibleRect.isEmpty { return editor }
        for subview in view.subviews {
            if let editor = editable(in: subview) { return editor }
        }
        return nil
    }

    private static func editorEye(in window: NSWindow, compactWidth: CGFloat) async throws -> CGPoint {
        var lastRect: CGRect?
        var lastChange = ContinuousClock.now
        let bar: CGRect = try await wait("expanded editor eye seat") {
            guard let rect = nativeRect("voice-bar-frame", in: window), rect.width > compactWidth + 70 else { return nil }
            let eye = CGPoint(x: rect.minX + 27.5, y: rect.minY + 22)
            guard hitView(at: eye, in: window)?.identifier?.rawValue == "voice-bar-frame" else { return nil }
            if rect != lastRect {
                lastRect = rect
                lastChange = .now
            }
            return lastChange.duration(to: .now) >= .milliseconds(150) ? rect : nil
        }
        // The production editor's 43pt identity seat starts 6pt inside the leading edge.
        return CGPoint(x: bar.minX + 27.5, y: bar.minY + 22)
    }

    private static func startWithHold(at point: CGPoint, in window: NSWindow, model: Workspace,
                                      beforeRelease: () async throws -> Void = {}) async throws {
        let editing = model.scene.inputOpen
        idleChildren = childWindows(of: window)
        lastChildReport = nil
        try noCallWindow(attachedTo: window, stage: "idle before hold")
        try await activate(window)
        let start = ContinuousClock.now
        try mouse(.leftMouseDown, at: point, in: window)
        defer { try? mouse(.leftMouseUp, at: point, in: window) }
        try await Task.sleep(for: .milliseconds(320))
        guard model.voice.phase == .idle, model.scene.inputOpen == editing, !orbPresent(in: window) else {
            throw ReplayFailure(description: "Voice or text input changed before a half-second hold")
        }
        do {
            try await expect("connection begins while the mouse is still held", seconds: 2) { model.voice.phase == .connecting }
        } catch {
            throw ReplayFailure(description: "Hold at \(point) hit \(hitTarget(at: point, in: window)), key=\(window.isKeyWindow), phase=\(model.voice.phase), editing=\(editing)")
        }
        let elapsed = start.duration(to: .now)
        guard elapsed >= .milliseconds(500) else { throw ReplayFailure(description: "Voice started after only \(elapsed)") }
        guard model.scene.inputOpen == editing else { throw ReplayFailure(description: "The recognized hold toggled text input") }
        guard !orbPresent(in: window) else { throw ReplayFailure(description: "Preparing exposed the voice orb") }
        try noCallWindow(attachedTo: window, stage: "preparing")
        try await beforeRelease()
    }

    private static func firstListeningOrb(in window: NSWindow, model: Workspace) async throws {
        let _: Bool = try await wait("first orb on an open call", seconds: 2, interval: .milliseconds(8)) {
            if orbPresent(in: window) {
                guard model.voice.phase == .listening else {
                    throw ReplayFailure(description: "First orb appeared during \(model.voice.phase)")
                }
                try noCallWindow(attachedTo: window, stage: "listening")
                return true
            }
            guard model.voice.phase == .connecting || model.voice.phase == .listening else {
                throw ReplayFailure(description: "Call entered \(model.voice.phase) before an orb appeared")
            }
            return nil
        }
    }

    private static func cancelPreparation(in window: NSWindow, model: Workspace) async throws {
        guard model.voice.phase == .connecting, !orbPresent(in: window) else {
            throw ReplayFailure(description: "Expected preparation before ⇧⌘V: " + menuReport(model))
        }
        try voiceShortcut("V", code: 9, in: window, model: model)
        let _: Bool = try await wait("cancelled preparation", seconds: 1, interval: .milliseconds(8)) {
            guard !orbPresent(in: window), model.voice.phase == .connecting || model.voice.phase == .idle else {
                throw ReplayFailure(description: "Cancelling preparation exposed the voice orb or opened the call: " + menuReport(model))
            }
            return model.voice.phase == .idle ? true : nil
        }
        // Keep observing past the scheduled connection completion, including transient controls.
        let deadline = ContinuousClock.now + .milliseconds(500)
        while ContinuousClock.now < deadline {
            guard model.voice.phase == .idle, !orbPresent(in: window) else {
                throw ReplayFailure(description: "A cancelled preparation restored the call or its orb")
            }
            try await Task.sleep(for: .milliseconds(8))
        }
    }

    private struct ChildSurface: CustomStringConvertible {
        let number: Int
        let identifier, title, kind, owner, content: String
        let level: Int
        let frame: CGRect
        let ignoresMouse: Bool
        let text: Set<String>

        var description: String {
            "#\(number) \(kind), id=\(identifier), title=\(title.debugDescription), owner=\(owner), level=\(level), frame=\(frame), ignoresMouse=\(ignoresMouse), content=\(content), AX text=\(text.sorted())"
        }
    }

    private static var idleChildren: [Int: ChildSurface] = [:]
    private static var lastChildReport: String?

    private static func childWindows(of main: NSWindow) -> [Int: ChildSurface] {
        var result: [Int: ChildSurface] = [:]
        for child in main.childWindows ?? [] where child.isVisible {
            let content = child.contentView.map { view in
                let children = view.subviews.map { String(describing: type(of: $0)) }.joined(separator: ", ")
                return "\(type(of: view)) [\(children)]"
            } ?? "none"
            result[child.windowNumber] = ChildSurface(number: child.windowNumber, identifier: child.identifier?.rawValue ?? "",
                title: child.title, kind: String(describing: type(of: child)),
                owner: Bundle(for: type(of: child)).bundleIdentifier ?? "", content: content,
                level: child.level.rawValue, frame: child.frame, ignoresMouse: child.ignoresMouseEvents, text: visibleText(in: child))
        }
        return result
    }

    private static func noCallWindow(attachedTo window: NSWindow, stage: String) throws {
        let current = childWindows(of: window)
        let summary = current.values.sorted { $0.number < $1.number }.map(\.description).joined(separator: " | ")
        let report = "Attached windows (\(stage)): [\(summary)]"
        if lastChildReport != report {
            FileHandle.standardOutput.write(Data((report + "\n").utf8))
            lastChildReport = report
        }
        for child in current.values {
            let before = idleChildren[child.number]
            // Match the same attached window from this idle main window, checking that it has not acquired
            // any new text. A newly attached window is evidence for inspection even if its AX tree is empty.
            guard child.identifier != "voice-status-window", let before, child.kind == before.kind, child.owner == before.owner,
                  child.title == before.title, child.text.isSubset(of: before.text) else {
                let idle = idleChildren.values.map(\.description).sorted()
                throw ReplayFailure(description: "Voice changed the attached windows during \(stage). Idle: \(idle); current: \(summary)")
            }
        }
    }

    private static func unchangedVoiceSurface(in window: NSWindow, textBefore: Set<String>) throws {
        try noCallWindow(attachedTo: window, stage: "spoken exchange")
        let newText = visibleText(in: window).subtracting(textBefore)
        guard newText.isEmpty else { throw ReplayFailure(description: "Spoken exchange added visible text: \(newText.sorted())") }
    }

    @discardableResult private static func playExample(in window: NSWindow, model: Workspace,
                                                       usingShortcut: Bool = false) async throws -> Set<String> {
        // Keep typed draft and workspace text as the baseline throughout the spoken exchange.
        let textBefore = visibleText(in: window)
        guard !textBefore.isEmpty else { throw ReplayFailure(description: "Accessibility did not expose workspace text") }
        if usingShortcut { try voiceShortcut("P", code: 35, in: window, model: model) }
        else { try await voiceCommand("模拟说一句", model: model) }
        var observed = Set<String>()
        do {
            let _: Bool = try await wait("sample reply is producing audio") {
                observed.insert("\(model.voice.phase), pending=\(model.voice.awaitingReply), playing=\(model.voice.isPlayingReply)")
                try unchangedVoiceSurface(in: window, textBefore: textBefore)
                return model.voice.phase == .speaking && model.voice.isPlayingReply ? true : nil
            }
        } catch {
            throw ReplayFailure(description: "\(error), shortcut=\(usingShortcut), observed=\(observed.sorted()): " + menuReport(model))
        }
        return textBefore
    }

    private static var voiceMenu: NSMenu? {
        NSApp.mainMenu?.items.first { $0.title == "语音演示" || $0.submenu?.title == "语音演示" }?.submenu
    }

    private static func menuReport(_ model: Workspace) -> String {
        let roots = NSApp.mainMenu?.items.map { "\($0.title)/\($0.submenu?.title ?? "")" } ?? []
        let commands = voiceMenu?.items.filter { !$0.isSeparatorItem }.map {
            "\($0.title) [\($0.isEnabled ? "enabled" : "disabled"), key=\($0.keyEquivalent), target=\(String(describing: $0.target)), action=\(String(describing: $0.action))]"
        } ?? []
        return "phase=\(model.voice.phase), menu bar=\(roots), voice items=\(commands)"
    }

    private static func voiceShortcut(_ key: String, code: UInt16, in window: NSWindow, model: Workspace) throws {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code),
              NSApp.mainMenu?.performKeyEquivalent(with: event) == true else {
            throw ReplayFailure(description: "Main menu did not handle ⇧⌘\(key): " + menuReport(model))
        }
    }

    private static func voiceCommand(_ title: String, model: Workspace) async throws {
        do {
            let (menu, index): (NSMenu, Int) = try await wait("enabled voice command " + title, seconds: 2) {
                guard let menu = voiceMenu else { return nil }
                menu.update()
                guard let index = menu.items.firstIndex(where: { $0.title == title && $0.isEnabled }) else { return nil }
                return (menu, index)
            }
            menu.performActionForItem(at: index)
        } catch {
            throw ReplayFailure(description: "\(error): " + menuReport(model))
        }
    }

    private static func shortPress(at point: CGPoint, in window: NSWindow) async throws {
        try mouse(.leftMouseDown, at: point, in: window)
        try await Task.sleep(for: .milliseconds(85))
        try mouse(.leftMouseUp, at: point, in: window)
    }

    private static func hitView(at point: CGPoint, in window: NSWindow) -> NSView? {
        let local = window.convertPoint(fromScreen: point)
        return window.contentView.flatMap { $0.hitTest($0.superview?.convert(local, from: nil) ?? local) }
    }

    private static func hitTarget(at point: CGPoint, in window: NSWindow) -> String {
        hitView(at: point, in: window).map { "\(type(of: $0)) (\($0.identifier?.rawValue ?? "no identifier"))" } ?? "no view"
    }

    private static func draftSnapshot(_ stage: String, at point: CGPoint, in window: NSWindow, model: Workspace) -> String {
        func editorState(_ editor: NSTextView) -> String {
            "\(type(of: editor))@\(ObjectIdentifier(editor)): text=\(editor.string.debugDescription), selection=\(editor.selectedRange()), editable=\(editor.isEditable), hidden=\(editor.isHiddenOrHasHiddenAncestor), visibleRect=\(editor.visibleRect)"
        }
        var textViews: [String] = []
        func visit(_ view: NSView) {
            if let editor = view as? NSTextView { textViews.append(editorState(editor)) }
            view.subviews.forEach(visit)
        }
        if let content = window.contentView { visit(content) }
        let responder = window.firstResponder.map { responder in
            (responder as? NSTextView).map(editorState) ?? "\(type(of: responder))@\(ObjectIdentifier(responder))"
        } ?? "nil"
        return """
            \(stage): bar=\(String(describing: nativeRect("voice-bar-frame", in: window))), point=\(point), hit=\(hitTarget(at: point, in: window))
              key=\(window.isKeyWindow), keyWindow=\(NSApp.keyWindow?.identifier?.rawValue ?? "none"), appActive=\(NSApp.isActive), voice=\(model.voice.phase), taskOpen=\(model.taskOpen), inputOpen=\(model.scene.inputOpen), inputInteractionReady=\(model.scene.inputInteractionReady)
              Chief draft=\(model.chiefDraft.text.debugDescription), Claude draft=\(model.agentDraft.text.debugDescription), firstResponder=\(responder), NSTextViews=\(textViews)
            """
    }

    private static func hangUp(_ phase: VoicePhase, in window: NSWindow, model: Workspace) async throws {
        let rect = try await wait("clickable orb while \(phase)") {
            model.voice.phase == phase ? nativeRect("voice-orb", in: window) : nil
        }
        let point = CGPoint(x: rect.midX, y: rect.midY)
        let target = hitTarget(at: point, in: window)
        try mouse(.rightMouseDown, at: point, in: window)
        try mouse(.rightMouseUp, at: point, in: window)
        do {
            try await expect("orb ends the call") { model.voice.phase == .idle && !orbPresent(in: window) }
        } catch {
            throw ReplayFailure(description: "Right click at \(point) in orb \(rect) hit \(target). Before: \(phase), after: \(model.voice.phase), control present: \(orbPresent(in: window))")
        }
    }

    private static func anchored(_ name: String, in window: NSWindow, when atDestination: (CGRect) -> Bool = { _ in true }) async throws -> CGRect {
        var lastRect: CGRect?
        var settledSince = ContinuousClock.now
        do {
            return try await wait("orb follows " + name) {
                guard let bar = nativeRect("voice-bar-frame", in: window), atDestination(bar),
                      let orb = nativeRect("voice-orb", in: window),
                      abs(orb.midY - bar.midY) < 2, abs(orb.midX - bar.maxX - 36) < 2,
                      window.frame.contains(CGPoint(x: orb.midX + 20, y: orb.midY)),
                      // AppKit publishes destination frames before the layer finishes
                      // its horizontal trip and reading-seat descent.
                      hitView(at: CGPoint(x: orb.midX, y: orb.midY), in: window)?.identifier?.rawValue == "voice-orb" else {
                    lastRect = nil
                    return nil
                }
                if lastRect != bar {
                    lastRect = bar
                    settledSince = .now
                }
                return settledSince.duration(to: .now) >= .milliseconds(125) ? bar : nil
            }
        } catch {
            throw ReplayFailure(description: "\(name) did not align the orb 36pt beyond the Bar on its midline. Bar \(String(describing: nativeRect("voice-bar-frame", in: window))), orb \(String(describing: nativeRect("voice-orb", in: window)))")
        }
    }

    private static func expect(_ name: String, seconds: Int = 5, _ predicate: () -> Bool) async throws {
        let _: Bool = try await wait(name, seconds: seconds) { predicate() ? true : nil }
    }

    private static func wait<T>(_ name: String, seconds: Int = 5, interval: Duration = .milliseconds(25),
                                _ read: () throws -> T?) async throws -> T {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if let value = try read() { return value }
            try await Task.sleep(for: interval)
        }
        throw ReplayFailure(description: "Timed out waiting for " + name)
    }

    private static func nativeRect(_ id: String, in window: NSWindow) -> CGRect? {
        func visit(_ view: NSView) -> CGRect? {
            guard !view.isHiddenOrHasHiddenAncestor else { return nil }
            if view.identifier?.rawValue == id, !view.visibleRect.isEmpty {
                return window.convertToScreen(view.convert(view.bounds, to: nil))
            }
            for child in view.subviews {
                if let result = visit(child) { return result }
            }
            return nil
        }
        return window.contentView.flatMap(visit)
    }

    private static func attribute(_ node: NSObject, _ key: String) -> Any? {
        node.responds(to: NSSelectorFromString(key)) ? node.value(forKey: key) : nil
    }

    private static func visibleText(in window: NSWindow) -> Set<String> {
        let roles: Set<String> = [NSAccessibility.Role.staticText.rawValue,
                                  NSAccessibility.Role.textField.rawValue, NSAccessibility.Role.textArea.rawValue]
        var text = Set<String>()
        var visited = Set<ObjectIdentifier>()
        func visit(_ node: NSObject) {
            guard visited.insert(ObjectIdentifier(node)).inserted else { return }
            if let role = attribute(node, "accessibilityRole") as? String, roles.contains(role),
               let frame = attribute(node, "accessibilityFrame") as? NSValue, frame.rectValue.intersects(window.frame) {
                for key in ["accessibilityValue", "accessibilityLabel", "accessibilityTitle"] {
                    let value = attribute(node, key)
                    if let string = (value as? String) ?? (value as? NSAttributedString)?.string, !string.isEmpty {
                        text.insert(string)
                    }
                }
            }
            for child in attribute(node, "accessibilityChildren") as? [NSObject] ?? [] { visit(child) }
        }
        visit(window)
        if let content = window.contentView { visit(content) }
        return text
    }

    private static func accessibilityRect(_ id: String, in window: NSWindow) -> CGRect? {
        func visit(_ node: NSObject) -> CGRect? {
            if attribute(node, "accessibilityIdentifier") as? String == id,
               let value = attribute(node, "accessibilityFrame") as? NSValue, !value.rectValue.isEmpty {
                return value.rectValue
            }
            for child in attribute(node, "accessibilityChildren") as? [NSObject] ?? [] {
                if let result = visit(child) { return result }
            }
            return nil
        }
        return visit(window) ?? window.contentView.flatMap(visit)
    }

    private static func orbPresent(in window: NSWindow) -> Bool {
        nativeRect("voice-orb", in: window) != nil || accessibilityRect("voice-orb", in: window) != nil
    }

    private static func click(_ id: String, in window: NSWindow) async throws {
        let rect = try await wait("control " + id) { nativeRect(id, in: window) ?? accessibilityRect(id, in: window) }
        let point = CGPoint(x: rect.midX, y: rect.midY)
        try mouse(.leftMouseDown, at: point, in: window)
        try mouse(.leftMouseUp, at: point, in: window)
        try await Task.sleep(for: .milliseconds(90))
    }

    private static var mouseSequence = 0
    private static func mouse(_ type: NSEvent.EventType, at screenPoint: CGPoint, in window: NSWindow) throws {
        if type == .leftMouseDown || type == .rightMouseDown { mouseSequence += 1 }
        guard let event = NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: screenPoint), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: mouseSequence, clickCount: 1, pressure: type == .leftMouseUp || type == .rightMouseUp ? 0 : 1) else {
            throw ReplayFailure(description: "Could not create mouse event \(type)")
        }
        NSApp.postEvent(event, atStart: false)
    }

    private static func captureSetup(_ window: NSWindow) async throws -> (SCContentFilter, SCStreamConfiguration) {
        let own = try await SCShareableContent.currentProcess
        guard let target = own.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw ReplayFailure(description: "WindowServer did not publish the demo window")
        }
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width.rounded()) * 2
        config.height = Int(window.frame.height.rounded()) * 2
        config.includeChildWindows = false
        config.ignoreGlobalClipSingleWindow = true
        config.ignoreShadowsSingleWindow = true
        config.showsCursor = false
        config.capturesAudio = false
        config.captureMicrophone = false
        return (SCContentFilter(desktopIndependentWindow: target), config)
    }

    private static func capture(_ window: NSWindow, to url: URL) async throws {
        try await Task.sleep(for: .milliseconds(500))
        let (filter, config) = try await captureSetup(window)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ReplayFailure(description: "PNG encoding failed")
        }
        try data.write(to: url)
    }

    private static func record(_ window: NSWindow, to url: URL, perform: () async throws -> Void) async throws {
        let (filter, config) = try await captureSetup(window)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let settings = SCRecordingOutputConfiguration()
        settings.outputURL = url
        settings.outputFileType = .mp4
        settings.videoCodecType = .h264
        let (started, start) = AsyncThrowingStream<Void, Error>.makeStream()
        let (finished, finish) = AsyncThrowingStream<Void, Error>.makeStream()
        let observer = RecordingObserver(started: start, finished: finish)
        defer { withExtendedLifetime(observer) {} }
        let output = SCRecordingOutput(configuration: settings, delegate: observer)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()
        let outcome: Result<Void, Error>
        do {
            for try await _ in started {}
            try await perform()
            outcome = .success(())
        } catch {
            outcome = .failure(error)
        }
        // stopCapture returns before the writer finishes the MP4. Keep a failed interaction's
        // frames available to the caller, which exits the process as soon as this method throws.
        do {
            try await stream.stopCapture()
            for try await _ in finished {}
        } catch {
            if case .failure(let interactionError) = outcome {
                FileHandle.standardError.write(Data("Voice movie finalization: \(error)\n".utf8))
                throw interactionError
            }
            throw error
        }
        try outcome.get()
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else {
            throw ReplayFailure(description: "Voice glass recording is empty")
        }
    }
}

private final class RecordingObserver: NSObject, SCRecordingOutputDelegate, Sendable {
    let started: AsyncThrowingStream<Void, Error>.Continuation
    let finished: AsyncThrowingStream<Void, Error>.Continuation

    init(started: AsyncThrowingStream<Void, Error>.Continuation, finished: AsyncThrowingStream<Void, Error>.Continuation) {
        self.started = started
        self.finished = finished
    }

    func recordingOutputDidStartRecording(_ output: SCRecordingOutput) { started.finish() }
    func recordingOutputDidFinishRecording(_ output: SCRecordingOutput) { finished.finish() }
    func recordingOutput(_ output: SCRecordingOutput, didFailWithError error: Error) {
        started.finish(throwing: error)
        finished.finish(throwing: error)
    }
}
