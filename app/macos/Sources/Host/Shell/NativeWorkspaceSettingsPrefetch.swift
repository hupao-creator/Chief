import Foundation
import ChiefCore
import ChiefPluginAPI

/// Settings acquisition belongs to the connected workspace, so opening a page
/// or selecting a Harness only attaches to resources that are already loading.
@MainActor
final class NativeWorkspaceSettingsPrefetch {
    private let host: NativeHarnessHost
    private var configurations: [NativeHarnessSettingsConfiguration] = []
    private var availablePreviews: [NativeHarnessSettingsConfiguration] = []
    private var refreshSequences: [String: Int] = [:]
    private var authority: UUID?
    private var tasks: [NativeHarnessSettingsConfiguration: Task<Void, Never>] = [:]

    init(host: NativeHarnessHost) { self.host = host }

    func update(workspace: NativeWorkspaceModel) {
        guard workspace.runtimeAvailable else { stop(); return }
        host.setSettingsAvailable(true)
        let model = workspace.settingsModel
        let settings = model.savedSettings
        let cwd = JSONText(model.defaultCwd)
        let enabled = Set(model.plugins.filter { $0.enabled && $0.unavailableReason == nil }.map(\.key))
        // Installation reads use the same bounded queue. Resolve availability
        // first instead of putting speculative CLI probes ahead of detection.
        let harnesses = workspace.plugins.harnesses.modules.filter {
            enabled.contains("harness:" + $0.descriptor.id.string)
                && model.installations[$0.descriptor.id.string]?.status == .installed
        }
        let backgroundSettings = workspace.plugins.applications.modules
            .filter { enabled.contains("extension:" + $0.manifest.id.string) }
            .flatMap(\.settings)
            .filter { $0.requires.contains(ApplicationCapabilities.backgroundConfigurationUI.requirement) }
        var next: [NativeHarnessSettingsConfiguration] = []
        var previews: [NativeHarnessSettingsConfiguration] = []
        for harness in harnesses {
            let id = harness.descriptor.id
            let defaults = NativeHarnessSettingsConfiguration(harnessID: id, cwd: cwd, source: settings["harnesses"]?[id.string] ?? .null)
            guard harness.descriptor.threadCapabilities.canHostMoku else { next.append(defaults); continue }
            let execution = settings["moku"]?["executionHarnesses"]?[id.string] ?? .null
            next.append(.init(harnessID: id, cwd: cwd, source: execution, scope: .global(executionOwner: .moku)))
            for definition in backgroundSettings {
                guard let entry = settings["pluginSettings"]?.arrayValue?.first(where: { $0["id"] == .string(definition.id) }),
                      let value = entry["value"], let saved = try? ApplicationBackgroundExecutionSettings(json: value) else { continue }
                let configuration = NativeHarnessSettingsConfiguration.background(harnessID: id, cwd: cwd, settingID: definition.id,
                                                                                 saved: saved, chiefSource: execution)
                // Allow an editor to open an independent draft on demand.
                // Discovery waits only for enabled, committed role scopes.
                if case .override = saved.mode, saved.enabled { next.append(configuration) }
                else { previews.append(configuration) }
            }
            // Prioritize execution admission without holding defaults behind
            // execution retry backoff; all scopes share the bounded read queue.
            next.append(defaults)
        }
        let sequences = model.detailRefreshSequences
        guard next != configurations || previews != availablePreviews || sequences != refreshSequences || authority != workspace.snapshotAuthority else { return }
        let changedHarnesses = sequences.keys.filter { sequences[$0] != refreshSequences[$0, default: 0] }
        // Discovery and saves arrive independently. Each unchanged source keeps
        // both its pending retry and its deadline for the next catalog read.
        let retained = Set(next)
        for (configuration, task) in tasks where authority != workspace.snapshotAuthority ||
            changedHarnesses.contains(configuration.harnessID.string) || !retained.contains(configuration) {
            task.cancel()
            tasks[configuration] = nil
        }
        for id in changedHarnesses {
            host.releaseGlobalSettings(harnessID: JSONText(id))
        }
        configurations = next; availablePreviews = previews; refreshSequences = sequences; authority = workspace.snapshotAuthority
        host.retainGlobalSettings(configurations: next, availablePreviews: previews)
        for configuration in next where tasks[configuration] == nil {
            tasks[configuration] = Task { [host] in
                while !Task.isCancelled {
                    await host.prefetchSettings(configuration)
                    let deadline = host.cachedSettingsSurface(configuration: configuration)?.revalidationDeadline
                    let now = ContinuousClock.now
                    // Failed admission can leave no current load timestamp.
                    let nextRead = deadline.flatMap { $0 > now ? $0 : nil } ?? now.advanced(by: NativeHarnessSettingsSurface.revalidationInterval)
                    do { try await Task.sleep(until: nextRead, clock: .continuous) } catch { return }
                }
            }
        }
    }

    func stop() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll(); configurations = []; availablePreviews = []; refreshSequences = [:]; authority = nil
        host.setSettingsAvailable(false)
    }
}
