import AppKit
import ApplicationServices
import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import ScreenCaptureKit
import SwiftUI
@testable import ChiefUI

// Read or press named public AX elements in this executable's own replay
// parent. Calling into SwiftUI's AX tree from its main actor can reenter layout.
func parentButton(_ id: String, press: Bool) -> [[String: String]] {
    guard ProcessInfo.processInfo.environment["CHIEF_REPLAY_PARENT"] == String(getppid()), AXIsProcessTrusted()
    else { return [["error": "Missing parent or AX permission"]] }
    let app = AXUIElementCreateApplication(getppid())
    AXUIElementSetMessagingTimeout(app, 0.5)
    var windows: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
          var pending = windows as? [AXUIElement] else { return [["error": "No replay window"]] }
    var seen = Set<CFHashCode>()
    var matches = [[String: String]]()
    while let node = pending.popLast(), seen.count < 6000 {
        guard seen.insert(CFHash(node)).inserted else { continue }
        func attribute(_ key: String) -> CFTypeRef? {
            var value: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(node, key as CFString, &value)
            return value
        }
        if attribute(kAXIdentifierAttribute) as? String == id ||
            (attribute(kAXRoleAttribute) as? String == "AXButton" &&
             [attribute(kAXDescriptionAttribute), attribute(kAXTitleAttribute)].contains { $0 as? String == id }) {
            var match = ["id": id, "enabled": String(attribute(kAXEnabledAttribute) as? Bool ?? false)]
            if press { match["press"] = String(AXUIElementPerformAction(node, kAXPressAction as CFString).rawValue) }
            matches.append(match)
        }
        pending += attribute(kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    return matches
}

@MainActor func button(_ id: String, press: Bool = false) async throws -> [[String: String]] {
    let child = Process(), pipe = Pipe()
    child.executableURL = Bundle.main.executableURL
    child.environment = ProcessInfo.processInfo.environment.merging(["CHIEF_REPLAY_PARENT": String(getpid())]) { _, value in value }
    child.arguments = [press ? "--press" : "--read", id]
    child.standardOutput = pipe
    try child.run()
    while child.isRunning { try await pause(5) }
    return try JSONDecoder().decode([[String: String]].self, from: pipe.fileHandleForReading.readDataToEndOfFile())
}

@MainActor private final class Bell: NativeMokuTimerPlaying {
    var starts = 0, stops = 0
    func startLoop() { starts += 1 }
    func stop() { stops += 1 }
}

@MainActor @Observable private final class RouteState {
    let scene = NativeMokuSceneState()
    let draft = NativeComposerDraft(services: .init(stageFiles: { _, _ in [] }, discardAttachments: { _ in }))
    let bell = Bell()
    let timer: NativeMokuTimerController
    var request: PublicInteraction?
    var responses: [HarnessRespondRequest] = []
    var replyKey: JSONText?
    var running = false
    init() {
        timer = NativeMokuTimerController(player: bell)
        scene.setComposerContext(draft, opensInput: false, autofocus: false)
    }
    var intervention: NativeMokuDockIntervention? {
        request.map { .init(threadID: "chief", harnessID: "local", executionID: "sample", threadTitle: "Fixture",
                            request: $0, questions: PublicInteractionQuestionnaire.specs(for: $0),
                            submitActionID: $0.actions.first(where: { $0.intent == .submit })?.id) }
    }
}

private struct RoutePanel: View {
    let model: RouteState
    var body: some View {
        NativeMokuScene(state: model.scene) { Color(white: 0.9) } dock: {
            NativeMokuDock(state: model.scene, draft: model.draft, cwd: "/fixture", mode: model.running ? .running : .idle,
                running: model.running, replyKey: model.replyKey,
                interaction: model.intervention.map { intervention in
                    AnyView(NativeMokuDockInteractionPanel(intervention: intervention, disabled: false) { response in
                        model.responses.append(response)
                    }.id(intervention.identity))
                }, interactionIsQuestion: model.intervention?.isQuestion == true, onSend: { _ in }, onCancel: {})
        } settings: { EmptyView() }
        .modifier(NativeMokuTimerPlacement(timer: model.timer, scene: model.scene))
    }
}

@MainActor func routesVisit(reduced: Bool, offscreen: Bool = false) async throws {
    let model = RouteState(), scene = model.scene, draft = model.draft
    let panel = try Panel(size: .init(width: 820, height: 640), offscreen: offscreen)
    defer { panel.close() }
    panel.mount(RoutePanel(model: model).environment(\._accessibilityReduceMotion, reduced))
    let root = panel.contentView!
    var events = [[String: Any]]()
    func record(_ name: String, _ detail: [String: Any] = [:]) throws {
        let eyes = root.descendants(NativeMokuCharacterCanvas.self).filter { $0.controller === scene.dockCharacter }
            .flatMap { $0.layer?.sublayers?.compactMap { $0 as? CAShapeLayer } ?? [] }
        var row: [String: Any] = ["event": name, "time": CACurrentMediaTime(), "size": NSStringFromRect(scene.capsuleFrame),
            "hosts": root.descendants(MokuHorizontalTravelView.self).count, "draft": draft.text,
            "expression": String(describing: scene.dockCharacter?.input?.expression),
            "question": scene.dockInteractionIsQuestion, "interaction": scene.dockInteractionVisible,
            "eyeTracks": eyes.filter { $0.animation(forKey: "moku.expression") != nil }.count,
            "editorFocused": panel.firstResponder is NSTextView]
        row.merge(detail) { _, new in new }
        events.append(row)
        try save(events, "routes.json")
    }
    try await until("Dock mounted") { scene.dockCharacter?.input?.expression == .idle }
    let filter = offscreen ? nil : try await panel.filter()
    func capture(_ name: String) async throws {
        if let filter {
            try await savePNG(SCScreenshotManager.captureImage(contentFilter: filter, configuration: panel.configuration()), name + ".png")
        } else {
            try panel.saveOffscreenImage(name)
        }
    }
    try await pause(470)
    try await betweenBlinks()
    model.replyKey = "unread"
    try await until("Unread face") { scene.dockCharacter?.input?.expression == .happy }
    try record("unread")
    try await pause(95)
    scene.toggleInput()
    try await until("Reply acknowledged") { scene.readReplies.contains("unread") }
    scene.toggleInput()
    try await until("Read face") { scene.dockCharacter?.input?.expression == .idle }
    try record("read")

    let permission = PublicInteraction(id: "permit", kind: .permission, title: "Allow fixture?",
        actions: [.init(id: "allow", intent: .allow, label: "Allow")], questions: [])
    let question = PublicInteraction(id: "question", kind: .question, title: "Choose",
        actions: [.init(id: "submit", intent: .submit, label: "Submit")],
        questions: [.init(id: "q", prompt: "Choose a value", multiple: false, allowOther: true, secret: false,
                          options: [.init(value: "one", label: "First option")])])
    try await pause(470)
    try await betweenBlinks()
    model.request = permission
    try await until("Permission above compact Dock") { scene.dockInteractionVisible && scene.dockHitRects.count >= 2 }
    let permissionRect = scene.dockHitRects[1]
    try await pause(100)
    try await capture("permission")
    let allow = try await button("moku-interaction-action-allow", press: true)
    try record("permission", ["control": allow, "panel": NSStringFromRect(permissionRect)])
    try check(allow.count == 1 && allow[0]["press"] == "0", "Press permission")
    try await until("Permission response") { model.responses.map(\.actionID) == ["allow"] }
    model.request = question
    try await until("Replacement question") {
        scene.dockInteractionIsQuestion && scene.dockHitRects.count >= 2 && scene.dockHitRects[1].width > permissionRect.width
    }
    let blank = try await button("moku-interaction-action-submit")
    try await capture("question")
    try check(blank.count == 1 && blank[0]["enabled"] == "false", "Empty answer is disabled")
    let option = try await button("First option", press: true)
    try record("question", ["blank": blank, "choice": option, "panel": NSStringFromRect(scene.dockHitRects[1])])
    try check(option.count == 1 && option[0]["press"] == "0", "Select answer")
    let submit = try await button("moku-interaction-action-submit", press: true)
    try await until("Question response") { model.responses.count == 2 }
    try check(model.responses.last?.answers?["q"] == .text("one"), "Selected answer receipt")
    try record("answered", ["submit": submit])
    model.request = nil

    try await until("Released intervention") { !scene.dockInteractionVisible }
    let opener = try await button("moku-open-input", press: true)
    try check(opener.count == 1 && opener[0]["press"] == "0", "Open Chief input")
    // Deliver the first character once, before polling the responder.
    func key(_ text: String) {
        panel.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, characters: text, charactersIgnoringModifiers: text.lowercased(),
            isARepeat: false, keyCode: 6)!)
    }
    key("Z")
    try await until("First key after intervention") { draft.text == "Z" && panel.firstResponder is NSTextView }
    let editor = panel.firstResponder as! NSTextView
    editor.insertText("🌲字", replacementRange: editor.selectedRange())
    editor.setSelectedRange(NSRange(location: 1, length: 2))
    try record("first-key-selection", ["selection": NSStringFromRange(editor.selectedRange())])

    model.timer.receive(nil)
    func timerRow(_ id: String) -> JSONValue {
        .object(["type": .text("tool-operation"), "name": .text("timer"), "executionId": .text("sample"), "id": .text(id),
                 "completedAt": .integer(2), "result": .object(["ok": .bool(true)]), "arguments": .object(["text": .text(id)])])
    }
    let thread = try HarnessThread(id: "chief", harnessID: "local", revision: 1, sessionState: .null, observation: .init(),
        cwd: "/fixture", settings: .object([:]), createdAt: 1, updatedAt: 2, title: "Fixture", tags: [],
        moku: true, transcript: .array([timerRow("first"), timerRow("second")]))
    model.timer.receive(thread)
    for name in ["first", "second"] {
        try await until("Mounted receipt") { !root.descendants(NativeMokuTimerReceiptButton.ReceiptButton.self).isEmpty }
        if name == "first" {
            let receipt = root.descendants(NativeMokuTimerReceiptButton.ReceiptButton.self)[0]
            try check(receipt.convert(receipt.bounds, to: root).maxY <= editor.convert(editor.bounds, to: root).minY,
                      "Timer leaves the active editor visible above its receipt")
            try await capture("timer-with-selection")
        }
        try check(model.timer.current?.text == name && panel.firstResponder === editor, "FIFO retained editor")
        let receipt = try await button("moku-timer-acknowledge", press: true)
        try check(receipt.count == 1 && receipt[0]["press"] == "0", "Timer receipt")
        try await until("Timer advanced") { model.timer.current?.text != name }
        try record("timer-" + name, ["control": receipt, "remaining": model.timer.pending.count])
    }
    try check(model.bell.starts == 1 && model.bell.stops == 1 && editor.selectedRange() == NSRange(location: 1, length: 2),
              "Timer focus/selection or bell lifetime")
    scene.setInputOpen(false)
    try await pause(70)
    scene.toggleInput(focusOnOpening: true)
    try await until("Same editor on reversal") { panel.firstResponder === editor }
    try check(editor.selectedRange() == NSRange(location: 1, length: 2), "Reopening UTF-16 selection")
    editor.setMarkedText("pin", selectedRange: .init(location: 3, length: 0), replacementRange: editor.selectedRange())
    try check(editor.hasMarkedText(), "Native marked text")
    editor.insertText("拼", replacementRange: .init(location: NSNotFound, length: 0))
    try await until("Native commit after reversal") { !editor.hasMarkedText() && draft.text == "Z拼字" }
    try record("reopen-marked-commit")
    scene.overviewVisible = false
    try await pause(85)
    try record("withdrawing", ["hitRects": scene.dockHitRects.count])
    scene.overviewVisible = true
    try await pause(750)
    try check(root.descendants(MokuHorizontalTravelView.self).count == 1 && scene.dockContentVisible, "Reversed host count")
    try record("route-reversed")
    scene.overviewVisible = false
    try await until("Host retired") { root.descendants(MokuHorizontalTravelView.self).isEmpty }
    try record("route-away")
    scene.overviewVisible = true
    try await until("Host returned") { root.descendants(MokuHorizontalTravelView.self).count == 1 && !scene.dockHitRects.isEmpty }
    try check(draft.text == "Z拼字", "Route draft")
    try record("route-return")
}

/// Exercise the installed Dock hierarchy, including its AppKit hit-test gate,
/// without moving the pointer, taking focus from another app or playing audio.
@MainActor func timersVisit(reduced: Bool) async throws {
    let model = RouteState()
    let scene = model.scene
    let panel = try Panel(size: .init(width: 820, height: 640), offscreen: true)
    defer { panel.close() }
    panel.mount(RoutePanel(model: model).environment(\._accessibilityReduceMotion, reduced))
    let root = panel.contentView!
    let timer = model.timer
    timer.receive(nil)
    let long = (1...8).map { "第\($0)行，请核对发布记录。" }.joined(separator: "\n")
    var operations: [JSONValue] = []
    func deliver(_ texts: [String]) throws {
        for text in texts {
            operations.append(.object(["type": .text("tool-operation"), "name": .text("timer"),
                "executionId": .text("sample"), "id": .text("timer-\(operations.count)"), "completedAt": .integer(2),
                "result": .object(["ok": .bool(true)]), "arguments": .object(["text": .text(text)])]))
        }
        timer.receive(try HarnessThread(id: "chief", harnessID: "local", revision: operations.count, sessionState: .null,
            observation: .init(), cwd: "/fixture", settings: .object([:]), createdAt: 1, updatedAt: 2,
            title: "Fixture", tags: [], moku: true, transcript: .array(operations)))
    }
    typealias Receipt = NativeMokuTimerReceiptButton.ReceiptButton
    func button(inDock: Bool) async throws -> Receipt {
        try await until("One receipt in the expected seat") {
            let buttons = root.descendants(Receipt.self)
            guard buttons.count == 1 else { return false }
            return (buttons[0].enclosingDock != nil) == inDock
        }
        let receipt = root.descendants(Receipt.self)[0]
        let rect = receipt.convert(receipt.bounds, to: root)
        try check(rect.minY >= 0 && rect.maxY < root.bounds.height / 2, "Receipt must occupy bottom of workspace")
        if let dock = receipt.enclosingDock {
            let center = receipt.convert(CGPoint(x: receipt.bounds.midX, y: receipt.bounds.midY), to: dock.superview)
            try await until("Moving Dock settles with a hittable receipt") {
                guard let hit = dock.hitTest(center) else { return false }
                return hit === receipt || hit.isDescendant(of: receipt)
            }
        }
        return receipt
    }
    func confirm(inDock: Bool) async throws {
        let previous = timer.current?.id
        let receipt = try await button(inDock: inDock)
        try check(receipt.accessibilityPerformPress(), "Receipt press")
        try await until("One acknowledgement advances the head") { timer.current?.id != previous }
    }
    func scrollToEnd() async throws {
        var scroller: NSScrollView?
        defer {
            if scroller == nil {
                for scroll in root.descendants(NSScrollView.self) {
                    print("viewport", scroll.contentView.bounds, "document", scroll.documentView?.bounds as Any,
                          "in Dock", scroll.enclosingDock != nil)
                }
            }
        }
        // The queue advances before SwiftUI replaces the old message's scroller.
        // Resolve the mounted viewport again on each observation.
        try await until("Long message starts at top in compact seat (\(timer.pending.count) pending)") {
            scroller = root.descendants(NSScrollView.self).first {
                let clip = $0.contentView.bounds
                return $0.enclosingDock != nil && ($0.documentView?.bounds.height ?? 0) > clip.height + 1
                    && clip.height > 0 && clip.height <= 41 && abs(clip.minY) < 1
            }
            return scroller != nil
        }
        let scroll = scroller!, clip = scroll.contentView, end = scroll.documentView!.bounds.maxY
        clip.scroll(to: CGPoint(x: 0, y: end - clip.bounds.height))
        scroll.reflectScrolledClipView(clip)
        try check(clip.bounds.maxY >= end - 1, "Long message tail is reachable")
    }
    for running in [false, true] {
        model.running = running
        try await until("Resident ready") {
            scene.dockCharacter?.input?.running == running && scene.capsuleFrame.size == NativeMokuCapsuleLayout.idleSize
        }
        try deliver(["Review ready", long, long])
        _ = try await button(inDock: true)
        let ids = timer.pending.map(\.id)
        try check(Set(ids).count == 3, "Distinct FIFO deliveries")
        try await pause(400)
        try check(timer.pending.map(\.id) == ids, "Reminder persisted while waiting")
        if !running { try panel.saveOffscreenImage("compact-reminder") }
        try await confirm(inDock: true)
        for id in ids.dropFirst() {
            try check(timer.current?.id == id && timer.current?.text == long, "Expected FIFO head")
            try await scrollToEnd()
            try await confirm(inDock: true)
        }
        try await until("Underlying Dock restored") {
            root.descendants(Receipt.self).isEmpty && !root.descendants(NativeMokuCharacterCanvas.self).isEmpty
                && scene.capsuleFrame.size == NativeMokuCapsuleLayout.idleSize && scene.dockCharacter?.input?.running == running
        }
    }
    // Withdraw and restore the ordinary Dock while one head remains outstanding.
    try deliver(["Review this before leaving"])
    let pending = timer.current?.id
    _ = try await button(inDock: true)
    scene.overviewVisible = false
    _ = try await button(inDock: false)
    try check(timer.current?.id == pending, "Covered route kept its pending receipt")
    scene.overviewVisible = true
    try await confirm(inDock: true)
    try check(model.bell.starts == 3 && model.bell.stops == 3 && timer.current == nil, "One bell per nonempty queue")
    try save(["result": "passed", "reduceMotion": reduced, "origins": ["idle", "running"],
              "receipts": 7, "ringStarts": model.bell.starts, "ringStops": model.bell.stops], "timers.json")
}

private extension NSView {
    var enclosingDock: MokuHorizontalTravelView? {
        sequence(first: self, next: { $0.superview }).first { $0 is MokuHorizontalTravelView } as? MokuHorizontalTravelView
    }
}
