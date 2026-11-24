import AppKit
import ChiefComposition
@testable import ChiefCore
import ChiefPluginAPI
@testable import ChiefUI
import SwiftUI

private struct ToolFeedbackDock: View {
    let host: NativeWorkspacePresentation

    var body: some View {
        let moku = host.moku
        NativeMokuScene(state: host.scene) { Color(white: 0.9) } dock: {
            NativeMokuDock(state: host.scene, draft: host.dockDraft, cwd: "/fixture",
                mode: moku.dockMode, running: moku.running, replyKey: moku.replyKey,
                interaction: moku.interaction, interactionIsQuestion: moku.interactionIsQuestion,
                presentation: moku, onSend: { _ in }, onCancel: {})
        } settings: { EmptyView() }
    }
}

@MainActor func toolFeedbackVisit(orbitFade: Bool = false, recordGaze: Bool = false) async throws {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let client = RuntimeClient(profile: try RuntimeProfile(dataDirectory: directory))
    // The replay supplies catalog deliveries in place of a live service.
    await client.setStatus(.connected)
    let workspace = NativeWorkspaceModel(client: client, preferences: DesktopPreferences(directory: directory),
        plugins: try NativePlugins.make())
    workspace.start()
    try await until("Replay workspace connected") { workspace.runtimeAvailable }
    let host = NativeWorkspacePresentation(workspace: workspace)
    let panel = try Panel(size: .init(width: 820, height: 640), offscreen: orbitFade)
    defer { panel.close() }
    panel.mount(ToolFeedbackDock(host: host))
    let authority = UUID()
    var revision = 0
    var observed: [String] = []
    var executionID: JSONText = "run"

    func deliver(_ status: PublicExecution.Status, foreground: JSONValue? = nil,
                 interactions: [PublicInteraction] = [], transcript: [JSONValue] = []) throws {
        revision += 1
        let ended = status == .completed || status == .failed || status == .interrupted
        let execution = try PublicExecution(executionID: executionID, status: status, startedAt: 1,
            finishedAt: ended ? 2 : nil, interactions: interactions)
        var turn: [JSONText: JSONValue] = ["executionId": .string(executionID), "createdAt": .integer(1),
            "updatedAt": .integer(2), "status": .text(status == .waitingForUser ? "waiting-input" : status.rawValue),
            "messages": .array([]), "timeline": .array([]), "answer": .text(""), "reasoning": .text(""),
            "plan": .array([]), "activities": .array([]), "interactions": .array([]), "notices": .array([])]
        turn["foreground"] = foreground
        if ended { turn["finishedAt"] = .integer(2) }
        let state: JSONValue = .object(["schema": .text("mokusei.harness.codex.thread.v1"),
            "updatedAt": .integer(2), "turns": .array([.object(turn)]), "backgroundTerminals": .array([])])
        let thread = try HarnessThread(id: "chief", harnessID: "codex", revision: revision, sessionState: state,
            observation: .init(latestExecution: execution), cwd: "/fixture", settings: .object([:]), createdAt: 1,
            updatedAt: 2, title: "Chief", tags: [], moku: true, transcript: .array(transcript))
        let snapshot: JSONValue = .object(["revision": .integer(revision), "settingsRevision": .integer(0),
            "defaultCwd": .text("/fixture"), "settings": .object([:]), "threads": .array([thread.json]),
            "executions": .array([]), "applicationThreads": .array([])])
        try workspace.catalog.install(snapshot)
        host.overview.refresh()
        if revision == 1 { host.moku.receive(.snapshot(snapshot, authority: authority)) }
        else { host.moku.receive(.mutation(.object([:]), state: snapshot, authority: authority)) }
        try check(host.moku.error == nil, host.moku.error ?? "")
    }

    func tool(_ name: String, sequence: Int) throws {
        let call = "call-\(sequence)"
        try deliver(.running, foreground: .object(["kind": .text("tool-call"), "sequence": .integer(sequence),
            "toolName": .text(name), "callId": .text(call)]))
        try check(host.moku.activity?.body == .toolCall(callID: JSONText(call), toolName: JSONText(name)),
                  "Foreground lost the tool name or call ID")
    }

    if recordGaze {
        try deliver(.completed)
        try await until("Mounted idle bar") { host.scene.dockCharacter?.input?.running == false }
        let movie = try await DockMovieCapture(window: panel, folder: "gaze")
        let start = CACurrentMediaTime()
        var events = [[String: Any]]()
        func record(_ action: String) { events.append(["action": action, "seconds": CACurrentMediaTime() - start]) }
        try await pause(400)
        record("start")
        try tool("update_note", sequence: 1)
        try await pause(1600)
        record("replace tool")
        try tool("ask_thread", sequence: 2)
        try await pause(1800)
        record("pause")
        host.scene.setWindowVisible(false)
        try await until("Hidden motion paused") { host.scene.dockCharacter?.hasScheduledFrame == false }
        let held = host.scene.dockCharacter?.clock
        try await pause(750)
        try check(host.scene.dockCharacter?.clock == held, "Hidden time advanced the character")
        record("resume")
        host.scene.setWindowVisible(true)
        try await pause(1700)
        record("retire")
        try deliver(.completed)
        try await pause(240)
        record("reverse fade")
        executionID = "replacement"
        try tool("update_note", sequence: 3)
        try await pause(1700)
        record("open editor")
        host.scene.setInputOpen(true)
        try await pause(850)
        record("close editor")
        host.scene.setInputOpen(false)
        try await pause(280)
        record("reopen editor")
        host.scene.setInputOpen(true)
        try await pause(350)
        record("close editor again")
        host.scene.setInputOpen(false)
        try await pause(1800)
        record("finish")
        try deliver(.completed)
        try await pause(800)
        try await movie.finish()
        try FileManager.default.moveItem(at: movie.directory.appendingPathComponent("window.mp4"),
                                         to: evidence.appendingPathComponent("window.mp4"))
        try save(events, "events.json")
        return
    }

    if orbitFade {
        try deliver(.completed)
        try await until("Compact Dock mounted") { host.scene.dockCharacter?.input?.running == false }
        guard let character = host.scene.dockCharacter else { throw ReplayFailure("Missing Dock character") }
        try await orbitFadeFrames(panel: panel, character: character) { running, key in
            executionID = JSONText(key)
            if running { try tool("update_note", sequence: revision + 1) }
            else { try deliver(.completed) }
            try await until("Updated compact expression") {
                character.input?.running == running && (!running || character.input?.executionKey == host.moku.executionKey)
            }
        }
        return
    }

    try tool("update_note", sequence: 1)
    try await until("First tool shows three dots") {
        guard let character = host.scene.dockCharacter else { return false }
        return character.input?.running == true && character.orbitDots.count == 3 && character.orbitOpacity > 0.5
    }
    observed.append("first-tool")
    let character = host.scene.dockCharacter!
    let firstInput = character.input
    func continuous(_ name: String) async throws {
        let frame = character.frameCount
        try await until("Next mounted frame: " + name) { character.frameCount > frame }
        try check(host.moku.dockMode == .running && host.scene.dockCharacter === character &&
                  character.input == firstInput && !character.isTransitioning, "Running face restarted: " + name)
        observed.append(name)
    }
    try await until("Orbit handoff settled") { !character.isTransitioning }
    try tool("ask_thread", sequence: 2)
    try await continuous("second-tool")
    try deliver(.running, foreground: .object(["kind": .text("reasoning"), "sequence": .integer(3), "text": .text("Next")]))
    try check(host.moku.reasoning != nil, "Reasoning source missing")
    try await continuous("reasoning")
    try deliver(.completed)
    try await until("Completion retires orbit") {
        character.input?.running == false && host.moku.dockMode == .idle && character.orbitDots.isEmpty
    }
    observed.append("completed")

    for terminal in [PublicExecution.Status.failed, .interrupted] {
        executionID = JSONText("run-" + terminal.rawValue)
        try tool("update_note", sequence: 1)
        try await until("Tool running before " + terminal.rawValue) { character.input?.running == true }
        try deliver(terminal)
        try await until(terminal.rawValue + " retires orbit") {
            character.input?.running == false && host.moku.dockMode == .idle && character.orbitDots.isEmpty
        }
        observed.append(terminal.rawValue)
    }

    executionID = "follow-up"
    for request in [
        PublicInteraction(id: "allow", kind: .permission, title: "Allow?", actions: [.init(id: "yes", intent: .allow, label: "Allow")], questions: []),
        PublicInteraction(id: "ask", kind: .question, title: "Choose", actions: [.init(id: "send", intent: .submit, label: "Submit")],
            questions: [.init(id: "q", prompt: "Which?", multiple: false, allowOther: true, secret: false, options: [])])
    ] {
        try tool("update_note", sequence: 1)
        try await until("Tool running before request") { character.input?.running == true }
        try deliver(.waitingForUser, interactions: [request])
        try await until("Intervention takes the seat") {
            host.scene.dockInteractionVisible && host.moku.intervention?.request.id == request.id &&
                character.input?.expression == .curious && character.input?.running == false
        }
        observed.append(request.kind.rawValue)
    }
    let dispatch: JSONValue = .object(["id": .text("create"), "executionId": .string(executionID), "name": .text("create_thread"),
        "type": .text("tool-operation"), "arguments": .object(["target": .object(["codex": .object([:])])])])
    try deliver(.running, transcript: [dispatch])
    try await until("Dedicated dispatch replaces ordinary feedback") {
        host.moku.activeOperation?.kind == .start && host.scene.talkPresentation.presented &&
            host.scene.talkPresentation.message?.dispatch?.phase == .dispatching && character.input?.running == false
    }
    observed.append("dispatch")
    try save(observed, "tool-feedback.json")
}
