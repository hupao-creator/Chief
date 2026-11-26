import AppKit
import ChiefComposition
import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI
import Testing
@testable import ChiefUI

private enum Agent: String, Codable, CaseIterable {
    case codex, claude, pi, opencode
    var field: String {
        switch self {
        case .codex, .claude: "effort"
        case .pi: "thinkingLevel"
        case .opencode: "variant"
        }
    }
}

private struct SettingsTrace: Codable {
    enum Start: String, Codable, CaseIterable { case fresh, retained, alphaThinking }
    struct Edit: Codable {
        let agent: Agent
        let choice: String
        let model: String?
    }
    let seed: UInt64
    let start: Start
    let discovery: [Agent]
    let late: Bool
    var failedProbe: Agent?
    var receiptFirst: Bool?
    var competingSave: Bool?
    var catalogFailure: Bool?
    var edits: [Edit]

    var delayed: Agent? { late ? discovery.last(where: { $0 != edits.first?.agent && $0 != .codex }) : nil }

    init(seed: UInt64) {
        self.seed = seed
        var rng = SplitMix64(seed: seed)
        start = Start.allCases.randomElement(using: &rng)!
        discovery = Agent.allCases.shuffled(using: &rng)
        late = Bool.random(using: &rng)
        failedProbe = Bool.random(using: &rng) ? Agent.allCases.randomElement(using: &rng) : nil
        let visits = Agent.allCases.shuffled(using: &rng) + (0..<rng.integer(0...4)).map { _ in Agent.allCases.randomElement(using: &rng)! }
        edits = visits.map { agent in
            Edit(agent: agent, choice: Bool.random(using: &rng) ? "medium" : "high",
                 model: [nil, "chat", "review"].randomElement(using: &rng)!)
        }
        receiptFirst = late && Bool.random(using: &rng)
        competingSave = Bool.random(using: &rng)
        catalogFailure = Bool.random(using: &rng)
        if receiptFirst == true, let delayed { edits.removeAll { $0.agent == delayed } }
    }
}

@MainActor private final class SettingsVisit {
    let model: NativeSettingsModel
    let navigation = NativeSettingsNavigation()
    let sessions: [Agent: HarnessSettingsSession]
    var window: NSWindow?
    var closeError: String?

    init(_ profile: HarnessSettingsProfile) throws {
        let model = try profile.makeModel()
        self.model = model
        let plugins = try NativePlugins.make().harnesses.modules
        var sessions: [Agent: HarnessSettingsSession] = [:]
        for plugin in plugins {
            if let agent = Agent(rawValue: plugin.descriptor.id.string) { sessions[agent] = profile.session(plugin, model: model) }
        }
        self.sessions = sessions
        let page = NativeSettingsPage(model: model, navigation: navigation, locale: .english, harnesses: plugins,
            harnessSettings: { request in
                do {
                    guard let agent = Agent(rawValue: request.harnessID.string), let session = sessions[agent] else {
                        throw PropertyFailure("missing Harness session")
                    }
                    let binding = request.value
                    return try session.harnessSettings(section: request.section, executionSnapshot: request.executionSnapshot,
                        settingsFormPage: true, value: binding.wrappedValue, host: nil,
                        change: { binding.wrappedValue = $0 })
                } catch {
                    return AnyView(NativeSettingsNotice(message: error.localizedDescription, kind: .error))
                }
            }, onClose: { _ in })
        model.draft.onClosedSaveError = { [weak self] message in
            self?.closeError = message
            return { [weak self] in self?.closeError = nil }
        }
        window = SwiftUIReplay.window(page, width: 780, height: 900)
    }

    func dismiss() {
        window?.close()
        window = nil
    }
    func unmount() {
        dismiss()
        for session in sessions.values { session.invalidate() }
        model.discardForReload()
    }

    var controls: [JSONValue] {
        navigation.interactions.snapshot(context: navigation.interactionContext(section: "moku"))
    }
    var errors: [String] {
        controls.filter { $0["severity"] == .text("error") }.compactMap { $0["value"]?.stringValue }
    }
    func control(_ id: String) -> JSONValue? {
        controls.first { $0["id"] == .text(id) && $0["pending"] == .bool(false) }
    }
    func perform(_ id: String, _ operation: String, _ value: JSONValue) async throws {
        try await wait(id) { self.control(id)?["enabled"] == .bool(true) }
        let handle = control(id)!["handle"]!.stringValue!
        try navigation.interactions.perform(id: id, handle: handle, operation: operation, value: value,
                                            context: navigation.interactionContext(section: "moku"))
    }
    func wait(_ step: String, _ predicate: () -> Bool) async throws {
        do { try await SwiftUIReplay.wait(predicate) }
        catch {
            // Notice registration IDs are visit-local UUIDs. Exclude them so a
            // shrink attempt can recognize the same failing step.
            let fields = controls.filter { $0["kind"] != .text("notice") }.compactMap { $0["id"]?.stringValue }
            throw PropertyFailure("\(step): errors=\(errors.sorted()) draft=\(model.draft.error ?? "none") controls=\(fields)")
        }
    }
}

extension SettingsTrace {
    @MainActor fileprivate func check(binary: URL, directory: URL) async throws {
        guard discovery.count == Agent.allCases.count, Set(discovery) == Set(Agent.allCases) else {
            throw PropertyFailure("expected a discovery permutation of the four Harnesses")
        }
        let root = directory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = HarnessSettingsProfile(executable: binary, directory: root)
        try prepare(profile)
        let visit = try SettingsVisit(profile)
        defer { visit.unmount() }
        try await checkDiscovery(visit, profile: profile)

        func load(_ agent: Agent, stream: Bool = true) async throws {
            try await visit.sessions[agent]!.reload(false)
            if stream { visit.model.receive(snapshot: try profile.invoke("state:load"), runtimeAvailable: true) }
        }
        // Schedule one cold import after the first draft edit. The save can
        // learn its revision from the stream or from the CAS receipt.
        for agent in discovery where agent != delayed { try await load(agent) }
        var baseline = try profile.invoke("state:load")
        var expectedFields: [Agent: String] = [:]
        var expectedModels: [Agent: String] = [:]
        for (index, edit) in edits.enumerated() {
            try await visit.perform("moku.host." + edit.agent.rawValue, "activate", .null)
            let field = "moku." + edit.agent.rawValue + "." + edit.agent.field
            let prior = expectedFields[edit.agent] ?? (edit.agent == .opencode ? "default" : "low")
            try await visit.wait("displayed " + field) { visit.control(field)?["value"] == .text(prior) }
            if index == 0, catalogFailure == true {
                try await checkCatalogRetry(edit.agent, field: field, visit: visit, profile: profile)
            }
            if let model = edit.model {
                let id = "moku." + edit.agent.rawValue + ".model"
                let label = (edit.agent == .pi || edit.agent == .opencode ? "local · " : "") + model.capitalized
                func option() -> JSONValue? {
                    visit.control(id)?["options"]?.arrayValue?.first { $0["label"] == .text(label) && $0["enabled"] == .bool(true) }?["id"]
                }
                try await visit.wait("model option " + label) { option() != nil }
                let choice = option()!
                try await visit.perform(id, "select", choice)
                try await visit.wait("displayed model " + label) { visit.control(id)?["value"] == choice }
                expectedModels[edit.agent] = model
            }
            try await visit.perform(field, "select", .text(edit.choice))
            try await visit.wait("selected " + field) { visit.control(field)?["value"] == .text(edit.choice) }
            guard visit.errors.isEmpty, visit.model.operationError == nil, !visit.controls.contains(where: { $0["invalid"] == .bool(true) }) else {
                throw PropertyFailure("legal choice reported an error: \(visit.errors)")
            }
            expectedFields[edit.agent] = edit.choice
            let staged = try profile.invoke("state:load")
            guard staged["settings"] == baseline["settings"], staged["settingsRevision"] == baseline["settingsRevision"] else {
                throw PropertyFailure("staged editor wrote before close")
            }
            if index == 0, let delayed {
                try await load(delayed, stream: receiptFirst != true)
                let refreshed = try profile.invoke("state:load")
                let slot = ["moku", "executionHarnesses", delayed.rawValue]
                guard let settings = refreshed["settings"], settingsAt(settings, path: slot)?["threadSettings"]?["model"] == .text("chat"),
                      settingsReplacing(settings, path: slot, value: nil) == baseline["settings"],
                      refreshed["settingsRevision"] == .integer(baseline["settingsRevision"]!.intValue! + 1) else {
                    throw PropertyFailure("cold import changed another slot or flushed the draft")
                }
                baseline = refreshed
            }
        }
        if edits.isEmpty, let delayed {
            try await load(delayed)
            baseline = try profile.invoke("state:load")
        }
        var wanted = baseline["settings"]!
        for (agent, choice) in expectedFields {
            let path = ["moku", "executionHarnesses", agent.rawValue, "threadSettings"]
            wanted = settingsReplacing(wanted, path: path + [agent.field], value: .text(choice))
            if let model = expectedModels[agent] { wanted = settingsReplacing(wanted, path: path + ["model"], value: .text(model)) }
            if agent == .codex { wanted = settingsReplacing(wanted, path: path + ["thinking"], value: nil) }
        }
        if let last = edits.last {
            wanted = settingsReplacing(wanted, path: ["moku", "hostHarnessPreference"], value: .text(last.agent.rawValue))
        }
        let expectedRevision = try await closeAndCheckSave(visit, profile: profile, baseline: baseline, wanted: wanted)
        visit.unmount()
        let reopened = try SettingsVisit(profile)
        defer { reopened.unmount() }
        await reopened.model.refreshInstallations()
        if let last = edits.last {
            try await reopened.sessions[last.agent]!.reload(false)
            let field = "moku." + last.agent.rawValue + "." + last.agent.field
            try await reopened.wait("reopened " + field) { reopened.control(field)?["value"] == .text(last.choice) }
        }
        guard reopened.errors.isEmpty, reopened.model.draft.value == wanted,
              try profile.invoke("state:load")["settingsRevision"] == .integer(expectedRevision) else {
            throw PropertyFailure("reopen changed settings or reported a false error")
        }
    }

    @MainActor private func prepare(_ profile: HarnessSettingsProfile) throws {
        if start == .alphaThinking {
            let initial = try profile.invoke("fixture:alpha-profile")
            guard initial["settingsRevision"] == .integer(7),
                  initial["settings"]?["moku"]?["executionHarnesses"]?["codex"]?["threadSettings"]?["thinking"]?["effort"] == .text("low") else {
                throw PropertyFailure("Alpha settings changed on first load")
            }
        } else {
            let blank = try profile.invoke("state:load")
            guard blank["settingsRevision"] == .integer(0),
                  blank["settings"]?["moku"]?["executionHarnesses"] == .object([:]) else {
                throw PropertyFailure("fresh profile already configured")
            }
            if start == .retained {
                let fields: JSONValue = .object(["model": .text("chat"), "effort": .text("low"),
                    "permissionMode": .text("ask-for-approval"), "summary": .text("concise"), "serviceTier": .text("default")])
                let pin: JSONValue = .object(["useDefaultThreadSettings": .bool(false), "threadSettings": fields])
                var existing = settingsReplacing(blank["settings"]!, path: ["moku", "executionHarnesses", "codex"], value: pin)
                existing = settingsReplacing(existing, path: ["moku", "hostHarnessPreference"], value: .text("codex"))
                guard case .saved = try profile.save(existing, revision: 0) else { throw PropertyFailure("seed profile conflict") }
            }
        }
    }

    @MainActor private func checkDiscovery(_ visit: SettingsVisit, profile: HarnessSettingsProfile) async throws {
        try await visit.wait("initial discovery") {
            visit.controls.contains { $0["value"] == .text("Loading Agent configuration…") }
        }
        guard visit.errors.isEmpty else { throw PropertyFailure("premature discovery error") }
        profile.failedProbe = failedProbe?.rawValue
        let held = discovery.last!
        profile.heldProbe = held.rawValue
        defer { profile.finishProbe() }
        visit.model.startDiscovery(harnessIDs: discovery.map(\.rawValue))
        try await visit.wait("partial roster") {
            visit.model.installations[held.rawValue]?.status == .checking &&
            self.discovery.filter { $0 != held }.allSatisfy {
                let status = visit.model.installations[$0.rawValue]?.status
                return status == .installed || status == .error
            } && visit.controls.contains { $0["id"]?.stringValue?.hasPrefix("moku.host.") == true }
        }
        guard visit.errors.allSatisfy({ failedProbe != nil && failedProbe != held && $0.contains("fixture detection failed") }) else {
            throw PropertyFailure("unfinished probe blamed saved selection: \(visit.errors)")
        }
        profile.finishProbe()
        try await visit.wait("completed roster") { !visit.model.probing }
        if failedProbe != nil {
            try await visit.wait("failed probe notice") { visit.errors.contains { $0.contains("fixture detection failed") } }
            guard visit.errors.allSatisfy({ $0.contains("fixture detection failed") }) else {
                throw PropertyFailure("failed probe blamed saved selection: \(visit.errors)")
            }
            profile.failedProbe = nil
            await visit.model.refreshInstallations()
        }
    }

    @MainActor private func checkCatalogRetry(_ agent: Agent, field: String, visit: SettingsVisit, profile: HarnessSettingsProfile) async throws {
        profile.failedCatalog = agent.rawValue
        do {
            try await visit.sessions[agent]!.reload(true)
            throw PropertyFailure("failed catalog reported success")
        } catch is RuntimeError {
            try await visit.wait("catalog failure notice") { visit.errors.contains { $0.contains("fixture catalog unavailable") } }
        }
        profile.failedCatalog = nil
        try await visit.sessions[agent]!.reload(true)
        try await visit.wait("catalog retry") { visit.errors.isEmpty && visit.control(field)?["enabled"] == .bool(true) }
    }

    @MainActor private func closeAndCheckSave(_ visit: SettingsVisit, profile: HarnessSettingsProfile,
                                               baseline: JSONValue, wanted: JSONValue) async throws -> Int {
        let baselineRevision = baseline["settingsRevision"]!.intValue!
        var remote: JSONValue?
        if competingSave == true, let last = edits.last {
            let path = ["moku", "executionHarnesses", last.agent.rawValue, "threadSettings"]
            var competing = settingsReplacing(baseline["settings"]!, path: path + [last.agent.field],
                                              value: .text(last.choice == "high" ? "medium" : "high"))
            if last.agent == .codex { competing = settingsReplacing(competing, path: path + ["thinking"], value: nil) }
            guard case let .saved(settings, _) = try profile.save(competing, revision: baselineRevision) else {
                throw PropertyFailure("competing fixture save failed")
            }
            remote = settings
        }
        guard visit.navigation.requestClose(model: visit.model, onClose: { _ in visit.dismiss() }) else { throw PropertyFailure("close rejected complete edit") }
        if let remote {
            do {
                try await visit.model.draft.flush()
                throw PropertyFailure("overlapping save lost its conflict")
            } catch is RuntimeError {
                try await visit.wait("global conflict notice") { visit.model.draft.conflicted && visit.closeError != nil }
                guard try profile.invoke("state:load")["settings"] == remote else { throw PropertyFailure("overwrote concurrent edit") }
            }
            visit.model.draft.retry()
        }
        do { try await visit.model.draft.flush() }
        catch { throw PropertyFailure("close save failed: " + error.localizedDescription) }
        let saved = try profile.invoke("state:load")
        let expectedRevision = baselineRevision + (remote == nil ? (wanted == baseline["settings"] ? 0 : 1) : 2)
        guard saved["settings"] == wanted, saved["settingsRevision"] == .integer(expectedRevision),
              visit.model.draft.saved == wanted, visit.model.draft.error == nil, visit.closeError == nil else {
            throw PropertyFailure("saved profile or revision differs from selected values: \(saved["settings"]!)")
        }
        return expectedRevision
    }

}

@Suite(.serialized) struct NativeHarnessSettingsProperties {
    @Test @MainActor func mountedProfileRoundTrips() async throws {
        guard !NSScreen.screens.isEmpty else {
            print("PBT CAPABILITY: WindowServer/display required")
            throw PropertyFailure("WindowServer/display required")
        }
        let budget = try PropertyBudget(defaultCases: 8)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = try HarnessSettingsProfile.buildPeer(in: directory)
        let replay = try propertyReplay(SettingsTrace.self)
        let corpus = HarnessSettingsProfile.repository.appendingPathComponent("tools/verification/pbt/settingspeer/testdata")
        let inputs = try replay.map { [$0] } ?? FileManager.default.contentsOfDirectory(at: corpus, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }.map {
                try JSONDecoder().decode(SettingsTrace.self, from: Data(contentsOf: $0))
            } + (0..<budget.cases).map { SettingsTrace(seed: budget.seed &+ UInt64($0)) }
        for trace in inputs {
            do {
                try await trace.check(binary: binary, directory: directory)
                print("Settings sample models=\(trace.edits.compactMap(\.model).count) catalogFailure=\(trace.catalogFailure == true) seed=\(trace.seed) start=\(trace.start.rawValue) edits=\(trace.edits.count) agents=\(trace.edits.map { $0.agent.rawValue }.joined(separator: ",")) late=\(trace.late) receiptFirst=\(trace.receiptFirst == true) failedProbe=\(trace.failedProbe?.rawValue ?? "none") competing=\(trace.competingSave == true)")
            } catch {
                try propertyEvidence(trace, name: "original.json")
                var reduced = trace
                let failure = (error as? PropertyFailure)?.message ?? error.localizedDescription
                let deadline = ContinuousClock.now + .seconds(budget.shrinkSeconds)
                for index in trace.edits.indices.reversed() where ContinuousClock.now < deadline {
                    var candidate = reduced
                    candidate.edits.remove(at: index)
                    do { try await candidate.check(binary: binary, directory: directory) }
                    catch {
                        let message = (error as? PropertyFailure)?.message ?? error.localizedDescription
                        if message == failure { reduced = candidate }
                    }
                }
                try propertyEvidence(reduced, name: "reduced.json")
                Issue.record(Comment(rawValue: "PBT-HARNESS-SETTINGS seed=\(trace.seed) \(failure) reduced=\(reduced)"))
                return
            }
        }
        print("PBT PASS PBT-HARNESS-SETTINGS seed=\(budget.seed) inputs=\(inputs.count) generated=\(replay == nil ? budget.cases : 0) replay=\(replay != nil)")
    }
}
