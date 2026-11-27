import ChiefPluginAPI
import ChiefPluginUI
import Observation
import SwiftUI
@testable import ChiefUI

private enum Appearance: String, CaseIterable {
    case system = "System appearance"
    case light = "Light"
    case dark = "Dark"

    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor @Observable private final class Fixture {
    enum Route {
        case overview
        case all
        case reading(SampleThread, fromAll: Bool)
        case submitted(String)
    }

    let scene = NativeMokuSceneState()
    let draft = NativeComposerDraft(services: .init(
        chooseItems: { _, _ in throw PluginContractError("This demo accepts text prompts.") },
        stageFiles: { _, _ in throw PluginContractError("This demo accepts text prompts.") },
        discardAttachments: { _ in }
    ))
    var scenario: EmptyScenario = .running
    var candidate: Candidate = .recent
    var appearance: Appearance = .system
    var route: Route = .overview
    var threads = SampleThread.samples(at: .now)

    func markRead(_ id: SampleThread.ID) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[index].lastReadAt = .now
    }

    func resetPreview() {
        route = .overview
        threads = SampleThread.samples(at: .now)
    }
}

struct EmptyStateDemo: App {
    var body: some Scene {
        Window("Chief Empty States", id: "empty-state-demo") {
            ComparisonWindow()
                .frame(minWidth: 800, minHeight: 620)
        }
        .defaultSize(width: 960, height: 690)
        .defaultLaunchBehavior(.presented)
        .windowResizability(.contentMinSize)
    }
}

private struct ComparisonWindow: View {
    @State private var fixture = Fixture()

    var body: some View {
        @Bindable var selection = fixture
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Design", selection: $selection.candidate) {
                    ForEach(Candidate.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 244)
                Spacer(minLength: 0)
                Picker("Scenario", selection: $selection.scenario) {
                    ForEach(EmptyScenario.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 184)
                Menu {
                    Picker("Appearance", selection: $selection.appearance) {
                        ForEach(Appearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Button("Reset preview") { fixture.resetPreview() }
                } label: {
                    Image(systemName: "slider.horizontal.3").accessibilityLabel("Preview settings")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            stage
            Divider()
            Label("Sample workspace", systemImage: "flask")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
        }
        .preferredColorScheme(fixture.appearance.scheme)
        .environment(\.locale, Locale(identifier: "en-US"))
        .onChange(of: fixture.scenario) { fixture.route = .overview }
        .onChange(of: fixture.candidate) { fixture.route = .overview }
    }

    private var stage: some View {
        NativeMokuScene(state: fixture.scene) {
            workspace
        } dock: {
            NativeMokuDock(state: fixture.scene, draft: fixture.draft, cwd: "/demo/Chief",
                onSend: { fixture.route = .submitted($0.text) },
                onCancel: {})
        } settings: {
            EmptyView()
        }
        .coordinateSpace(name: "workspace")
        .clipped()
    }

    private var workspace: some View {
        ZStack {
            palette.canvas.swiftUI
            switch fixture.route {
            case .overview:
                let scenario = fixture.scenario
                let threads = fixture.candidate == .recent ? scenario.recentThreads(in: fixture.threads) : []
                StatusWithRecentThreads(status: NativeOverviewStatusEmptyState(title: scenario.title),
                    scenario: scenario, threads: threads, open: { fixture.route = .reading($0, fromAll: false) })
                ScenarioRail(scenario: scenario, select: { fixture.scenario = $0 })
            case .all:
                result(title: "Chief / All conversations", backTo: fixture.scenario.rawValue,
                       onBack: { fixture.route = .overview }) {
                    VStack(spacing: 0) {
                        ForEach(fixture.threads) { thread in
                            Divider()
                            ThreadRow(thread: thread) { fixture.route = .reading(thread, fromAll: true) }
                        }
                    }
                }
            case .reading(let thread, let fromAll):
                result(title: thread.title, backTo: fromAll ? "All conversations" : fixture.scenario.rawValue,
                       onBack: { fixture.route = fromAll ? .all : .overview }) {
                    SampleConversationBody(thread: thread)
                        .onAppear { fixture.markRead(thread.id) }
                }
            case .submitted(let text):
                result(title: "New conversation", backTo: fixture.scenario.rawValue,
                       onBack: { fixture.route = .overview }) {
                    ScrollView {
                        Text(text).font(NativeTypography.inter(size: 14))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                }
            }
            scopeChrome
        }
        .foregroundStyle(palette.ink.swiftUI)
    }

    private var scopeChrome: some View {
        VStack {
            NativeOverviewChrome(filters: [
                .init(tag: "Chief", scope: "demo", count: fixture.threads.count, isDirectory: true)
            ], selectedTag: "Chief", selectedScope: "demo", selectedKind: .directory,
                onTagChange: { _ in fixture.route = .all })
            Spacer(minLength: 0)
        }
    }

    private func result<Content: View>(title: String, backTo: String, onBack: @escaping () -> Void,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onBack) { Label("Back to \(backTo)", systemImage: "arrow.left") }
                .buttonStyle(.bordered)
            Text(title)
                .font(NativeTypography.inter(size: 22, weight: 680))
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(20)
        .frame(width: 430, alignment: .leading)
        .background(palette.surface.swiftUI, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(palette.line.swiftUI)
                .allowsHitTesting(false)
        }
    }
}

struct ScenarioRail: View {
    let scenario: EmptyScenario
    let select: (EmptyScenario) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(EmptyScenario.allCases) { choice in
                let active = choice == scenario
                Button { select(choice) } label: {
                    Label(choice.rawValue, systemImage: choice.railIcon)
                        .font(NativeTypography.inter(size: 12, weight: active ? 650 : 480))
                        .foregroundStyle(active ? NativePalette.overviewAccentText.swiftUI : palette.ink.swiftUI)
                        .frame(width: 103, height: 31, alignment: .leading)
                        .padding(.leading, 9)
                        .background(active ? palette.accentSoft.swiftUI : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(.leading, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
