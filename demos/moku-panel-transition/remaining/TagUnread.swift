import AppKit
import ChiefComposition
import ChiefCore
import ChiefPluginAPI
import SwiftUI
@testable import ChiefUI

@MainActor func tagUnreadVisit() async throws {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let workspace = NativeWorkspaceModel(client: RuntimeClient(profile: try RuntimeProfile(dataDirectory: directory)),
        preferences: DesktopPreferences(directory: directory), plugins: try NativePlugins.make())
    let presentation = NativeWorkspacePresentation(workspace: workspace)
    defer { withExtendedLifetime(presentation) {} }
    let model = presentation.overview
    let threads = try ["first", "second", "active"].map { name -> JSONValue in
        let complete = name != "active"
        let execution = try PublicExecution(executionID: JSONText(name), status: complete ? .completed : .running,
            startedAt: 1, finishedAt: complete ? 2 : nil)
        let tags: [JSONText] = name == "second" ? [] : ["Work"]
        return try HarnessThread(id: JSONText(name), harnessID: "codex", revision: 1, sessionState: .null,
            observation: .init(latestExecution: execution), cwd: "/fixture", settings: .object([:]),
            createdAt: 1, updatedAt: 2, title: JSONText(name), tags: tags,
            tagEmojis: tags.isEmpty ? [:] : ["Work": "🔎"], directoryTag: "Project", directoryScope: "/fixture").json
    }
    let snapshot: JSONValue = .object(["revision": .integer(1), "settingsRevision": .integer(0),
        "defaultCwd": .text("/fixture"), "settings": .object([:]), "threads": .array(threads),
        "executions": .array([]), "applicationThreads": .array([])])
    try workspace.catalog.install(snapshot)
    model.refresh()
    let panel = try Panel(size: .init(width: 920, height: 600), offscreen: true)
    defer { panel.close() }
    panel.mount(NativeOverviewWorkspaceView(model: model, callbacks: .init(
        openThread: { _, _ in }, openApplication: { _, _ in }, onSettings: {})))
    guard let parent = model.visibleFilters.first(where: { $0.scope == "/fixture" }),
          let work = parent.children.first(where: { $0.tag == "Work" }) else {
        throw ReplayFailure("Expected fixture directory: " + (model.error ?? "absent"))
    }
    let controls = model.chromeInteractions
    try await until("Directory chip mounted") { controls.mountedIDs(in: .directory).contains(parent.id) }
    try controls.activate(.directory, id: parent.id)
    try await until("Semantic chip mounted") { controls.mountedIDs(in: .semantic).contains(work.id) }
    try controls.activate(.semantic, id: work.id)
    try await until("Work selected") { model.selectedFilter?.id == work.id }
    var observed = [[String: Any]]()
    func verify(_ step: String, directoryUnread: Int, tagUnread: Int) async throws {
        guard let parent = model.visibleFilters.first(where: { $0.scope == "/fixture" }),
              let child = parent.children.first(where: { $0.tag == "Work" }) else { throw ReplayFailure("Missing tags") }
        try check(parent.unreadCount == directoryUnread && child.unreadCount == tagUnread, "Unexpected counts at " + step)
        try check(model.selectedFilter?.id == child.id && controls.mountedIDs(in: .semantic).contains(child.id),
                  "Selected tag left its rail at " + step)
        try await pause(600)
        try panel.saveOffscreenImage(step)
        observed.append(["step": step, "directory": parent.unreadCount, "child": child.unreadCount])
    }
    try await verify("unread-two", directoryUnread: 2, tagUnread: 1)
    for (step, id, expected) in [("read-first", "first", 1), ("reread-first", "first", 1), ("read-last", "second", 0)] {
        try model.markRead(.init(threadID: JSONText(id), typeID: "agent"), version: JSONText(id))
        try await verify(step, directoryUnread: expected, tagUnread: 0)
    }
    try save(observed, "tag-unread.json")
}
