import AppKit
import ApplicationServices
import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import ScreenCaptureKit
import SwiftUI
@testable import ChiefUI

@MainActor @Observable private final class RouteState {
    let scene = NativeMokuSceneState()
    let draft = NativeComposerDraft(services: .init(stageFiles: { _, _ in [] }, discardAttachments: { _ in }))
    let settings = NativeSettingsModel(settings: .object([:]), revision: 0,
        save: { value, revision in .saved(settings: value, revision: revision + 1) },
        loadInstallations: { .object([:]) }, installHarness: { _ in })
    var request: PublicInteraction?
    var responses: [HarnessRespondRequest] = []
    var replyKey: JSONText?
    init() {
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
            NativeMokuDock(state: model.scene, draft: model.draft, cwd: "/fixture", mode: .idle,
                replyKey: model.replyKey,
                interaction: model.intervention.map { intervention in
                    AnyView(NativeMokuDockInteractionPanel(intervention: intervention, disabled: false) { response in
                        model.responses.append(response)
                    }.id(intervention.identity))
                }, interactionIsQuestion: model.intervention?.isQuestion == true, onSend: { _ in }, onCancel: {})
        } settings: {
            if model.scene.settingsOpen {
                NativeSettingsPage(model: model.settings, locale: .english, harnesses: [],
                    harnessSettings: { _ in AnyView(EmptyView()) }, onClose: { _ in model.scene.closeSettings() })
            }
        }
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
    let blank = try await button("moku-interaction-action-submit", press: true)
    try await capture("question")
    try check(blank.count == 1 && blank[0]["role"] == "AXButton" && blank[0]["enabled"] == "false", "Empty answer is disabled")
    try check(model.responses.map(\.actionID) == ["allow"], "Empty answer produced a response")
    let option = try await button("First option", press: true)
    try record("question", ["blank": blank, "choice": option, "panel": NSStringFromRect(scene.dockHitRects[1])])
    try check(option.count == 1 && option[0]["press"] == "0", "Select answer")
    let submit = try await button("moku-interaction-action-submit", press: true)
    try check(submit.count == 1 && submit[0]["enabled"] == "true" && submit[0]["press"] == "0", "Submit selected answer")
    try await until("Question response") { model.responses.count == 2 }
    try check(model.responses.last?.interactionID == "question" && model.responses.last?.actionID == "submit"
              && model.responses.last?.answers == ["q": .text("one")], "Selected answer receipt")
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

    scene.receiveTalk(.init(id: "bar-talk", text: "Ready for review"))
    try await until("Talk presented") { scene.talkPresentation.presented }
    let deadline = scene.talkPresentation.deadline
    scene.openSettings()
    try await pause(150)
    scene.closeSettings()
    try await pause(65)
    scene.openSettings()
    try await until("Settings settled after reversal") { scene.settingsExpanded && !scene.settingsTransitioning }
    try check(try await button("settings-close").count == 1, "Settings close control after reversal")
    try await capture("settings-after-reversal")
    _ = try await button("settings-close", press: true)
    try await until("Settings closed") { !scene.settingsOpen }
    try check(draft.text == "Z拼字" && (scene.talkPresentation.deadline == deadline || scene.talkPresentation.message == nil),
              "Cover changed draft or extended Talk")
    try record("talk-settings-return")

}
