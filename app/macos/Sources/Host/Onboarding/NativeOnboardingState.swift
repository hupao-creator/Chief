import Foundation
import Observation
import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI

enum NativeOnboardingStep: Int, CaseIterable {
    case discovery, moku, tag, report, landing
    var settingID: String? {
        switch self { case .tag: "tag.settings"; case .report: "report.settings"; default: nil }
    }
}

/// The profile owns completion, the Runtime owns execution settings, and this
/// window owns the pending step and the visual handoff into its existing Dock.
@MainActor @Observable final class NativeOnboardingState {
    let workspace: NativeWorkspaceModel
    let interactions = NativeSettingsInteractions()
    let visit = UUID()
    private(set) var admitted = false
    private(set) var finished: Bool
    private(set) var step = NativeOnboardingStep.discovery
    private(set) var busy = false
    private var configurationHarnessIDs = Set<JSONText>()
    private var retryingHarnessIDs = Set<JSONText>()
    var error: String?
    private(set) var editors = Dictionary(uniqueKeysWithValues: NativeOnboardingStep.allCases.map { ($0, NativeSettingsReadiness()) })
    var editorReady: Bool { editors[step]?.ready == true }
    var mounted = false
    var mountDock = false
    var dockVisible = false
    enum HandoffPhase: String { case saved, fade, contract, reveal, finished }
    // Read once by the interaction client after AX observes the focused editor.
    @ObservationIgnored private(set) var handoffTimes: [HandoffPhase: UInt64] = [:]
    func markHandoff(_ phase: HandoffPhase) { handoffTimes[phase] = DispatchTime.now().uptimeNanoseconds }

    var panelFrame = CGRect.zero
    var blocksWorkspace: Bool { !finished }
    var settings: NativeSettingsModel { workspace.settingsModel }
    var locale: DesktopLocale { workspace.locale }
    var context: NativeSettingsInteractionContext {
        .init(visit: visit, section: "onboarding.\(step.rawValue)")
    }
    var harnesses: [AnyHarnessPlugin] {
        workspace.plugins.harnesses.modules.filter { harness in
            let plugin = settings.plugins.first { $0.key == "harness:\(harness.descriptor.id.string)" }
            return plugin?.enabled != false && plugin?.unavailableReason == nil
        }
    }
    var installed: [AnyHarnessPlugin] {
        harnesses.filter {
            guard settings.installations[$0.descriptor.id.string]?.status == .installed else { return false }
            // Keep the admitted roster stable across configuration saves. The
            // active editor independently gates readiness of its changed source.
            return step == .discovery ? discoveryState($0) == .ready : configurationHarnessIDs.contains($0.descriptor.id)
        }
    }
    enum DiscoveryState: Equatable { case checking, loading, ready, missing, failed(String) }
    func discoveryState(_ harness: AnyHarnessPlugin) -> DiscoveryState {
        let id = harness.descriptor.id.string
        if retryingHarnessIDs.contains(harness.descriptor.id) {
            return settings.installations[id]?.status == .installed ? .loading : .checking
        }
        switch settings.installationState(id) {
        case .checking, .installing: return .checking
        case .missing: return .missing
        case .error: return .failed(settings.installations[id]?.message ?? locale.text("检测失败，请重试。", "Detection failed. Please retry."))
        case .installed:
            switch workspace.harnessHost.settingsPreparation(harnessID: harness.descriptor.id) {
            case .loading: return .loading
            case .ready: return .ready
            case .failed(let message): return .failed(message)
            }
        }
    }
    var detecting: Bool {
        harnesses.contains { discoveryState($0) == .checking || discoveryState($0) == .loading }
    }
    var selectedHost: AnyHarnessPlugin? {
        let id = settings.draft.value["moku"]?["hostHarnessPreference"]?.stringValue
        return installed.first { $0.descriptor.id.string == id && settings.supports($0, role: .chiefHost) }
    }
    var targets: Set<String> {
        Set(settings.draft.value["moku"]?["targetHarnessIds"]?.arrayValue?.compactMap(\.stringValue) ?? [])
    }
    var canAdvance: Bool {
        guard admitted, !busy, workspace.runtimeAvailable,
              !settings.draft.composing, settings.draft.firstInvalidField == nil else { return false }
        if step != .discovery, settings.draft.error != nil { return false }
        switch step {
        case .discovery: return installed.contains { settings.supports($0, role: .chiefHost) }
        case .moku: return selectedHost != nil && !validTargets.isEmpty && editorReady
        case .tag, .report: return roleIsAvailable && editorReady
        case .landing: return false
        }
    }
    private var dispatchTargetIDs: Set<String> {
        Set(installed.filter { settings.supports($0, role: .agentThread) }.map { $0.descriptor.id.string })
    }
    private var validTargets: Set<String> { targets.intersection(dispatchTargetIDs) }
    private var roleIsAvailable: Bool {
        guard let id = step.settingID,
              let raw = settings.draft.value["pluginSettings"]?.arrayValue?.first(where: { $0["id"] == .text(id) })?["value"],
              let value = try? ApplicationBackgroundExecutionSettings(json: raw) else { return false }
        if !value.enabled { return true }
        switch value.mode {
        case .inherit: return selectedHost.map { settings.supports($0, role: .application(JSONText(id))) } == true
        case .override(let profile):
            return installed.contains { $0.descriptor.id == profile.harnessPreference && settings.supports($0, role: .application(JSONText(id))) }
        }
    }

    init(workspace: NativeWorkspaceModel) {
        self.workspace = workspace
        finished = workspace.preferences.onboardingCompleted
        mountDock = finished; dockVisible = finished
    }

    func admitIfNeeded() {
        guard !finished, !admitted, workspace.hasInitialContent else { return }
        do {
            let catalog = workspace.catalog
            // Switching the default Harness can archive the empty Chief shell
            // before the first catalog arrives. Only history with activity
            // should cause an otherwise fresh desktop to skip setup.
            let previousActivity = catalog.threads.contains {
                !$0.mokuHistory || $0.observation.latestExecution != nil || $0.pendingInput
                    || $0.transcript?.arrayValue?.isEmpty == false
            }
                || !catalog.applicationThreads.isEmpty
                || catalog.moku?.observation.latestExecution != nil || catalog.moku?.pendingInput == true
            if !workspace.preferences.onboardingPending, previousActivity {
                try workspace.preferences.setOnboardingCompleted(true)
                finishHandoff()
                return
            }
            // Store pending before any normal preference save can make a fresh
            // profile look like an established desktop on its next launch.
            try workspace.preferences.setOnboardingCompleted(false)
            settings.draft.reconcileFirstRunDiscovery = true
            admitted = true; error = nil
        } catch { self.error = error.localizedDescription }
    }

    func advance() async {
        guard canAdvance else { return }
        let trace = DevDiagnostics.makeTrace()
        DevDiagnostics.event("onboarding.advance", "validating", trace: trace)
        busy = true; error = nil
        defer { busy = false }
        do {
            if step == .discovery {
                configurationHarnessIDs = Set(installed.map(\.descriptor.id))
                seedAvailableSelections()
            } else {
                // Discovery can change while the editor is mounted. Keep only
                // real targets at the configuration boundary before persisting.
                if step == .moku, targets != validTargets {
                    settings.draft.change(settingsReplacing(settings.draft.value, path: ["moku", "targetHarnessIds"],
                        value: .array(validTargets.sorted().map(JSONValue.text))))
                }
                try await settings.draft.flush()
            }
            try Task.checkCancellation()
            guard workspace.runtimeAvailable else { throw RuntimeError("UNAVAILABLE", locale.text("连接恢复后再继续。", "Reconnect before continuing.")) }
            if step == .report {
                try workspace.preferences.setOnboardingCompleted(true)
                markHandoff(.saved)
                settings.draft.reconcileFirstRunDiscovery = false
            }
            step = NativeOnboardingStep(rawValue: step.rawValue + 1)!
            editors[step] = NativeSettingsReadiness()
            DevDiagnostics.event("onboarding.advance", "advanced", trace: trace)
        } catch {
            DevDiagnostics.failure("onboarding.advance", error, trace: trace)
            self.error = error.localizedDescription
        }
    }

    func back() {
        guard admitted, !busy, step != .discovery, step != .landing else { return }
        step = NativeOnboardingStep(rawValue: step.rawValue - 1)!
        editors[step] = NativeSettingsReadiness(); error = nil
    }

    func retry() {
        error = nil
        if !admitted { admitIfNeeded() }
        else if settings.draft.error != nil { settings.draft.retry() }
        else if step == .discovery {
            for harness in harnesses { if case .failed = discoveryState(harness) { retryDiscovery(harness) } }
        }
        else { Task { await advance() } }
    }

    func retryDiscovery(_ harness: AnyHarnessPlugin) {
        let id = harness.descriptor.id
        guard workspace.runtimeAvailable, !retryingHarnessIDs.contains(id) else { return }
        retryingHarnessIDs.insert(id)
        Task {
            defer { retryingHarnessIDs.remove(id) }
            if settings.installations[id.string]?.status == .installed {
                await workspace.harnessHost.retrySettingsPreparation(harnessID: id)
            } else {
                await settings.refreshInstallation(id.string, retry: true)
            }
        }
    }

    func scan() {
        guard workspace.runtimeAvailable, !settings.probing else { return }
        let ids = Set(harnesses.map(\.descriptor.id))
        retryingHarnessIDs.formUnion(ids)
        Task {
            defer { retryingHarnessIDs.subtract(ids) }
            await settings.refreshInstallations()
        }
    }

    func finishHandoff() {
        finished = true; mountDock = true; dockVisible = true
    }

    private func seedAvailableSelections() {
        guard let host = selectedHost ?? installed.first(where: { settings.supports($0, role: .chiefHost) }) else { return }
        var value = settingsReplacing(settings.draft.value, path: ["moku", "hostHarnessPreference"], value: .string(host.descriptor.id))
        let selection = validTargets.isEmpty ? dispatchTargetIDs : validTargets
        value = settingsReplacing(value, path: ["moku", "targetHarnessIds"], value: .array(selection.sorted().map(JSONValue.text)))
        settings.draft.change(value)
    }
}
