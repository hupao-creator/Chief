import AppKit
import ChiefComposition
import ChiefCore
import ChiefPluginAPI
import SwiftUI
@testable import ChiefUI

private struct UnreadChrome: View {
    let model: NativeOverviewWorkspaceModel
    var body: some View {
        VStack {
            NativeOverviewChrome(filters: model.filters, onTagChange: model.selectTag,
                                 interactions: model.chromeInteractions)
            Spacer()
        }
        .background(Color.white)
    }
}

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
        return try HarnessThread(id: JSONText(name), harnessID: "codex", revision: 1, sessionState: .null,
            observation: .init(latestExecution: execution), cwd: "/fixture", settings: .object([:]),
            createdAt: 1, updatedAt: 2, title: JSONText(name), tags: ["Work"],
            tagEmojis: ["Work": "🔎"], directoryTag: "Project", directoryScope: "/fixture").json
    }
    let snapshot: JSONValue = .object(["revision": .integer(1), "settingsRevision": .integer(0),
        "defaultCwd": .text("/fixture"), "settings": .object([:]), "threads": .array(threads),
        "executions": .array([]), "applicationThreads": .array([])])
    try workspace.catalog.install(snapshot)
    model.refresh()
    let panel = try Panel(size: .init(width: 920, height: 320), offscreen: true)
    defer { panel.close() }
    panel.mount(UnreadChrome(model: model))
    guard let parent = model.filters.first(where: { $0.scope == "/fixture" }) else {
        throw ReplayFailure("Expected fixture directory: " + (model.error ?? "absent"))
    }
    try await until("Directory chip mounted") { model.chromeInteractions.mountedDirectoryIDs.contains(parent.id) }
    try model.chromeInteractions.perform(directory: parent.id, operation: "open")
    try await until("Child menu mounted") { model.chromeInteractions.mountedMenuIDs.contains(parent.id) }
    var observed = [[String: Any]]()
    func verify(_ step: String, expected: Int) async throws {
        guard let parent = model.filters.first(where: { $0.scope == "/fixture" }),
              let child = parent.children.first(where: { $0.tag == "Work" }) else { throw ReplayFailure("Missing tags") }
        try check(parent.unreadCount == expected && child.unreadCount == expected, "Unexpected counts at " + step)
        try await pause(600)
        try panel.saveOffscreenImage(step)
        observed.append(["step":step, "directory":parent.unreadCount, "child":child.unreadCount])
    }
    try await verify("unread-two", expected: 2)
    for (step, id, expected) in [("read-first", "first", 1), ("reread-first", "first", 1), ("read-last", "second", 0)] {
        try model.markRead(.init(threadID: JSONText(id), typeID: "agent"), version: JSONText(id))
        try await verify(step, expected: expected)
    }
    try save(observed, "tag-unread.json")
}
