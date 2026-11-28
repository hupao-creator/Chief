import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import ChiefUI
import Observation
import SwiftUI

/// The native shell receives the same view models as a workspace, with process-local drafts and sample settings.
@MainActor @Observable
final class DemoWorkspaceShell {
    let motion: NativeReadingPageMotion
    let scene: NativeMokuSceneState
    private let overviewDraft: NativeComposerDraft
    private var threadDrafts: [JSONText: NativeComposerDraft] = [:]
    private(set) var draft: NativeComposerDraft
    private let settingsNavigation = NativeSettingsNavigation()
    private let settings: NativeSettingsModel

    init() {
        let motion = NativeReadingPageMotion()
        self.motion = motion
        scene = NativeMokuSceneState(readingPanelMotion: motion)
        let overviewDraft = Self.makeDraft()
        self.overviewDraft = overviewDraft
        draft = overviewDraft
        settings = NativeSettingsModel(settings: .object(["moku": .object([
            "hostHarnessPreference": .text("codex"), "targetHarnessIds": .array([.text("codex")])])]),
            revision: 1, save: { .saved(settings: $0, revision: $1 + 1) },
            loadInstallations: { .object(["codex": .object(["status": .text("installed")])]) },
            installHarness: { _ in throw DemoThread.readOnly })
        let codex: JSONValue = .object(["key": .text("harness:codex"), "enabled": .bool(true),
            "harnessRoles": .array(["agent", "moku", "tag.settings", "report.settings"].map(JSONValue.text))])
        settings.receive(snapshot: .object(["plugins": .array([codex])]), runtimeAvailable: true)
    }

    private static func makeDraft() -> NativeComposerDraft {
        NativeComposerDraft(services: .init(chooseItems: { _, _ in [] },
            stageFiles: { _, _ in throw DemoThread.readOnly }, discardAttachments: { _ in }))
    }

    func showOverview() {
        scene.readingPanelVisible = false
        scene.overviewVisible = true
        draft = overviewDraft
        scene.setComposerContext(draft, opensInput: false)
    }

    func showReader(threadID: JSONText?, inputReady: Bool = true) {
        scene.readingPanelVisible = true
        scene.overviewVisible = false
        if let threadID {
            let next = threadDrafts[threadID] ?? Self.makeDraft()
            threadDrafts[threadID] = next
            draft = next
        } else {
            draft = overviewDraft
        }
        let admitted = threadID != nil && inputReady
        scene.setComposerContext(draft, opensInput: threadID != nil, keepsInputOpen: threadID != nil,
                                 inputAdmissionReady: admitted, autofocus: false)
        if admitted { scene.setInputOpen(true) }
    }

    func openSettings() {
        settings.draft.beginPageEditing()
        settingsNavigation.section = NativeSettingsNavigation.defaultSection
        settingsNavigation.visit = UUID()
        scene.openSettings()
        Task { await settings.refreshInstallations(force: false) }
    }

    func settingsPage(locale: DesktopLocale, plugins: NativePluginComposition) -> some View {
        NativeSettingsPage(model: settings, navigation: settingsNavigation, locale: locale,
            harnesses: plugins.harnesses.modules, harnessSettings: { request in
                do {
                    let plugin = try plugins.harnesses.require(request.harnessID)
                    let session = plugin.makeSettingsSession(load: { _ in Self.codexPresentation }, onError: { _ in })
                    try session.publishStored(Self.codexPresentation)
                    return try session.harnessSettings(section: request.section, executionSnapshot: request.executionSnapshot,
                        settingsFormPage: true, value: request.value.wrappedValue, host: nil, change: { request.value.wrappedValue = $0 })
                } catch { return AnyView(Text(error.localizedDescription)) }
            }, onClose: { [scene] _ in scene.closeSettings() }, mokuController: scene.settingsCharacter,
            onCoordinatorFrame: { [scene] frame, pending in scene.setCoordinatorFrame(frame, pending: pending) })
    }

    private static let codexPresentation: JSONValue = .object([
        "cli": .object(["available": .bool(true)]),
        "models": .array([.object([
            "value": .text("GPT-5.4"), "displayName": .text("GPT-5.4"),
            "thinking": .object(["kind": .text("effort"), "efforts": .array([.text("medium")])]),
            "supportedReasoningEfforts": .array([.object(["value": .text("medium")])]),
            "defaultReasoningEffort": .text("medium"), "serviceTiers": .array([])
        ])])
    ])
}
