import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI

public struct AgyOverview {
    let card: ThreadCardPresentation
    let excerpt: String
    let request: PublicInteraction?
}

public struct AgyHarnessPlugin: HarnessPlugin {
    public init() {}
    public let descriptor = HarnessPluginDescriptor(id: "agy", displayName: "Antigravity",
        threadCapabilities: .init(instructions: false, threadContext: false, sendContext: true, toolModes: []),
        installationGuide: URL(string: "https://antigravity.google/docs/getting-started?tab=cli"))
    private static let artwork: (image: NSImage, source: String) = {
        guard let url = NativeResources.bundle.url(forResource: "Antigravity", withExtension: "png"),
              let data = try? Data(contentsOf: url), let image = NSImage(data: data) else {
            preconditionFailure("Missing Antigravity logo")
        }
        return (image, "data:image/png;base64," + data.base64EncodedString())
    }()
    public var logoSource: String { Self.artwork.source }
    public func logo(size: CGFloat) -> some View {
        Image(nsImage: Self.artwork.image).renderingMode(.original).resizable().interpolation(.high)
            .scaledToFit().frame(width: size, height: size).accessibilityLabel("Antigravity")
    }
    public var harnessSettingsCodec: PluginValueCodec<JSONValue> { threadSettingsCodec }
    public var threadSettingsCodec: PluginValueCodec<JSONValue> {
        let validate: (JSONValue) throws -> JSONValue = { value in
            guard var fields = value.objectValue else { throw PluginContractError("Invalid Antigravity settings") }
            // Persisted defaults and Thread snapshots can include a retired sign-in preference.
            fields.removeValue(forKey: "authMethod")
            guard fields.allSatisfy({ $0.key == "model" && $0.value.stringValue != nil })
            else { throw PluginContractError("Invalid Antigravity settings") }
            return .object(fields)
        }
        return .init(decode: validate, encode: validate)
    }
    public var settingsPresentationCodec: PluginValueCodec<JSONValue> {
        let validate: (JSONValue) throws -> JSONValue = { value in
            guard value["issue"]?.stringValue != nil || value["models"]?.arrayValue?.allSatisfy({
                $0["id"]?.stringValue != nil && $0["name"]?.stringValue != nil
            }) == true else { throw PluginContractError("Invalid Antigravity model catalog") }
            return value
        }
        return .init(decode: validate, encode: validate)
    }
    public func settingsPresentationIssue(_ presentation: JSONValue) -> String? {
        if let issue = presentation["issue"]?.stringValue { return issue }
        return presentation["models"]?.arrayValue?.isEmpty == true ? "Antigravity returned no models. Check your sign-in in agy." : nil
    }
    public func projectOverview(input: HarnessThreadInput, availableColumns: Int) throws -> HarnessOverviewProjection<AgyOverview> {
        let latest = input.thread.observation.latestExecution
        let request = latest?.interactions.first
        var extensions: [ThreadCardExtensionProjection] = []
        if let request {
            extensions.append(.intervention(.init(id: request.id, title: request.title.string, detail: request.description?.string,
                actions: request.actions.map { .init(id: $0.id, label: $0.label.string) }, questions: [], submitActionId: nil)))
        }
        let card = try composeThreadCard(.standard(extensions: extensions), git: input.git,
                                        layoutContext: .init(availableCols: availableColumns))
        let excerpt = latest?.error?.string ?? latest?.summary?.string ??
            input.thread.sessionState["turns"]?.arrayValue?.last?["prompt"]?.stringValue ?? ""
        return .init(footprint: .init(columns: card.size.cols, rows: card.size.rows), structureKey: JSONText(card.key),
            excerpt: JSONText(excerpt), view: .init(card: card, excerpt: excerpt, request: request))
    }
    public func overviewCard(input: HarnessThreadInput, projection: AgyOverview,
                             respond: @escaping (HarnessRespondRequest) async throws -> Void,
                             openThread: @escaping () -> Void) -> some View {
        let execution = input.thread.observation.latestExecution
        return HarnessThreadCard(identity: .init(title: input.thread.title.string,
            harness: .init(brandKey: "agy", label: "Antigravity", logoSource: logoSource),
            model: input.thread.settings["model"]?.stringValue, runtime: execution.map { .init(startedAt: $0.startedAt, endedAt: $0.finishedAt) },
            excerpt: projection.excerpt), presentation: projection.card, status: threadCardStatus(input.thread.observation),
            completedAt: execution?.finishedAt, emoji: nil, harnessLogo: AnyView(logo(size: 12)),
            onInterventionResponse: { selection in
                guard let request = projection.request else { throw PluginContractError("Permission request has ended") }
                try await respond(.init(interactionID: request.id, actionID: selection.actionId))
            }, onOpenThread: openThread)
    }
    public func threadView(input: HarnessThreadInput, actions: HarnessThreadActions, context: HarnessRenderContext) -> some View {
        AgyThread(input: input, actions: actions, context: context).id(input.thread.id)
    }
    public func threadSettings(input: HarnessThreadInput, resource: HarnessSettingsResource<JSONValue>,
                               update: @escaping (JSONValue) async throws -> Void) -> some View {
        AgyModelSettings(selected: input.thread.settings["model"]?.stringValue, resource: resource, update: update)
    }
    public func harnessSettings(props: HarnessSettingsProps<JSONValue, JSONValue>) -> some View {
        EmptyView()
    }
}

private struct AgyModelSettings: View {
    let selected: String?
    let resource: HarnessSettingsResource<JSONValue>
    let update: (JSONValue) async throws -> Void
    @Environment(\.locale) private var locale
    @State private var failure: String?
    var body: some View {
        switch resource.state {
        case .loading: ProgressView()
        case .error(let message): Text(message)
        case .ready(let value):
            if let issue = AgyHarnessPlugin().settingsPresentationIssue(value) { Text(issue) }
            else {
                Picker(locale.language.languageCode?.identifier == "zh" ? "模型" : "Model", selection: Binding(get: { selected ?? value["effectiveModel"]?["model"]?.stringValue ?? "" }, set: { id in
                    Task { do { try await update(.object(["model": .text(id)])); failure = nil } catch { failure = error.localizedDescription } }
                })) {
                    ForEach(value["models"]?.arrayValue ?? [], id: \.self) { model in
                        Text(model["name"]?.stringValue ?? "").tag(model["id"]?.stringValue ?? "")
                    }
                }
            }
            if let failure { Text(failure) }
        }
    }
}
