import SwiftUI
import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI

struct NativeOnboardingSurface: View {
    @Bindable var state: NativeOnboardingState
    let scene: NativeMokuSceneState
    let applicationSections: [NativeApplicationSettingsSection]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mapMotion = NativeMokuSettingsAnimationState()
    @State private var panelStep = NativeOnboardingStep.discovery
    @State private var presentedStep = NativeOnboardingStep.discovery
    @State private var documentHeight: CGFloat = 160
    @State private var handoffPanelSize: CGSize?
    @State private var contentVisible = true
    @State private var collapsed = false
    @State private var panelVisible = true
    private let ink = NativePalette.settings.text.swiftUI
    private let secondary = NativePalette.settings.muted.swiftUI
    private var motion: Animation { .easeInOut(duration: 0.32) }
    private var locale: DesktopLocale { state.locale }
    private var pageReady: Bool { presentedStep == state.step && panelStep == state.step }

    var body: some View {
        GeometryReader { geometry in
            let illustrationWidth = min(NativeSettingsContentLayout.illustrationWidth, max(0, geometry.size.width - 124))
            let panelWidth = illustrationWidth + 2 * NativeSettingsContentLayout.horizontalInset
            let heightLimit = min(820, max(0, geometry.size.height - 64))
            let fallback = NativeMokuCapsuleLayout.surface(in: NativeMokuCapsuleLayout.frame(
                in: CGRect(origin: .zero, size: geometry.size), landing: true), expanded: true, height: 76, centered: true)
            let destination = scene.capsuleFrame.width > 0 ? scene.capsuleFrame : fallback
            panel(illustrationWidth: illustrationWidth, heightLimit: heightLimit)
                .frame(width: panelWidth)
                .opacity(contentVisible ? 1 : 0)
                .frame(width: collapsed ? destination.width : handoffPanelSize?.width,
                       height: collapsed ? destination.height : handoffPanelSize?.height)
                // Once the form ink has retired, carry the capsule's material
                // color through the contraction so the Dock can appear behind it.
                .background {
                    if collapsed { Color(white: 0.10) }
                    else { NativeSettingsPanelBackground() }
                }
                .clipShape(RoundedRectangle(cornerRadius: NativeMokuCapsuleLayout.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: NativeMokuCapsuleLayout.cornerRadius)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 0.8)
                        .opacity(collapsed ? 0 : 1)
                }
                .shadow(color: .black.opacity(0.13), radius: collapsed ? 13 : 30, y: collapsed ? 6 : 16)
                .position(x: collapsed ? destination.midX : geometry.size.width / 2,
                          y: collapsed ? destination.midY : geometry.size.height / 2)
                .opacity(panelVisible ? 1 : 0)
                .allowsHitTesting(state.step != .landing)
                .accessibilityHidden(state.step == .landing)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("onboarding")) } action: { state.panelFrame = $0 }
                .animation(reduceMotion ? nil : motion, value: documentHeight)
        }
        .coordinateSpace(name: "onboarding")
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .environment(\.nativeSettingsFormPage, true)
        .environment(\.nativeSettingsCompactPresentation, true)
        .environment(\.nativeSettingsInteractions, state.interactions)
        .environment(\.nativeSettingsInteractionContext, state.context)
        .environment(\.nativeSettingsInteractionRefresh, state.interactions.refresh)
        .environment(\.nativeOnboardingHarnessIDs, Set(state.installed.map(\.descriptor.id)))
        .nativeSettingsTextEditing(onComposition: { state.settings.draft.composing = $0 }, onBlur: { state.settings.draft.flushText() })
        .onAppear { state.mounted = true; state.admitIfNeeded() }
        .onDisappear { state.mounted = false }
        .task(id: state.step) { await transition() }
    }

    private func panel(illustrationWidth: CGFloat, heightLimit: CGFloat) -> some View {
        let isBackgroundRole = panelStep == .tag || panelStep == .report
        let navigationTopInset: CGFloat = 8
        return NativeOnboardingPanelLayout(documentHeight: documentHeight, heightLimit: heightLimit) {
            HStack(spacing: 8) {
                ForEach(NativeOnboardingStep.allCases, id: \.rawValue) { step in
                    Capsule().fill(step.rawValue <= panelStep.rawValue ? ink : secondary.opacity(0.2))
                        .frame(width: step == panelStep ? 32 : 20, height: 3)
                }
            }.frame(height: 28).padding(.top, 16).padding(.bottom, 10)
                .accessibilityLabel(locale.text("第 \(panelStep.rawValue + 1) 步，共 5 步", "Step \(panelStep.rawValue + 1) of 5"))
            // Balance the space below the picker with the insets above the buttons.
            scrollContent(illustrationWidth: illustrationWidth, bottomInset: isBackgroundRole
                ? NativeApplicationBackgroundEditor.agentPickerBottomInset - navigationTopInset : 20)
            HStack {
                if panelStep != .discovery {
                    Button(action: state.back) { Label(locale.text("返回", "Back"), systemImage: "chevron.left") }
                        .buttonStyle(.glass)
                        .nativeSettingsAction("back", label: "Back") { state.back() }.disabled(!pageReady || state.busy)
                }
                Spacer()
                if panelStep == .discovery, state.installed.isEmpty, !state.detecting, !discoveryHasFailures, discoveryError == nil {
                    Button(locale.text("重新检测", "Check again"), action: state.scan)
                        .buttonStyle(.glass)
                        .nativeSettingsAction("scan", label: "Check for Agents", action: state.scan)
                        .disabled(state.settings.probing || !state.workspace.runtimeAvailable)
                } else {
                    Button { Task { await state.advance() } } label: {
                        HStack(spacing: 15) {
                            if state.busy { ProgressView().controlSize(.small) }
                            Text(panelStep == .report ? locale.text("开始使用 Chief", "Start using Chief") : locale.text("继续", "Continue"))
                            Image(systemName: "arrow.right")
                        }.font(.system(size: 12, weight: .medium)).frame(minWidth: 116, minHeight: 24)
                    }.buttonStyle(.glass).keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("onboarding-confirm-\(panelStep)")
                        .nativeSettingsAction("next", label: "Continue") { Task { await state.advance() } }
                        .disabled(!pageReady || !state.canAdvance)
                }
            }.frame(maxWidth: NativeSettingsContentLayout.formWidth)
                .padding(.horizontal, NativeSettingsContentLayout.horizontalInset)
                .padding(.bottom, 22).padding(.top, navigationTopInset)
        }
        .font(.system(size: 13)).foregroundStyle(ink)
        .tint(NativePalette.settings.accent.swiftUI)
    }

    private func scrollContent(illustrationWidth: CGFloat, bottomInset: CGFloat) -> some View {
        let waiting = !state.admitted && state.error == nil && state.settings.draft.error == nil && discoveryError == nil
        return ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("onboarding-top")
                    if let error = state.error ?? state.settings.draft.error ?? discoveryError {
                        NativeSettingsNotice(message: error, kind: .error, action: AnyView(
                            HStack {
                                Button(locale.text("重试", "Retry"), action: state.retry)
                                    .nativeSettingsAction("retry", label: "Retry onboarding") { state.retry() }
                                if state.settings.draft.conflicted {
                                    Button(locale.text("使用已保存的配置", "Use saved settings")) { state.settings.draft.discardConflict() }
                                }
                            }.buttonStyle(.borderless))).padding(.bottom, 12)
                            .frame(maxWidth: NativeSettingsContentLayout.formWidth)
                    }
                    if state.admitted && panelStep == .discovery { discovery.padding(.top, 22) }
                    else if state.admitted {
                        NativeRoleConfigurationPanel(role: panelStep == .moku ? .moku : panelStep == .tag ? .tag : .report,
                            harnesses: state.installed, locale: locale, showsHeading: true, illustrationWidth: illustrationWidth) {
                            configurationForStep(panelStep, illustrationWidth: illustrationWidth).disabled(state.busy)
                        }
                    }
                }
                .id(panelStep).transition(.opacity.combined(with: .offset(y: 10)))
                .allowsHitTesting(pageReady)
                .accessibilityHidden(!pageReady)
                .frame(width: illustrationWidth)
                .padding(.bottom, bottomInset)
                .frame(minHeight: waiting ? 160 : nil)
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { documentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: panelStep) { _, _ in reader.scrollTo("onboarding-top", anchor: .top) }
            .overlay { if waiting { NativeSurfaceLoading() } }
        }
    }

    private var discoveryError: String? {
        guard panelStep == .discovery else { return nil }
        if case .failed(let message) = state.settings.installationLoadState { return message }
        return nil
    }
    private var discoveryHasFailures: Bool {
        state.harnesses.contains { if case .failed = state.discoveryState($0) { return true }; return false }
    }
    private var pendingDiscoveryDescription: String {
        state.harnesses.compactMap { harness in
            let name = harness.descriptor.displayName.string
            switch state.discoveryState(harness) {
            case .checking: return name + " " + locale.text("检测中", "Checking")
            case .loading: return name + " " + locale.text("读取配置中", "Loading settings")
            default: return nil
            }
        }.joined(separator: ", ")
    }

    private var discovery: some View {
        let ready = state.installed
        let missing = state.harnesses.filter { state.discoveryState($0) == .missing }
        let needsInstall = ready.isEmpty && !state.detecting && !discoveryHasFailures && discoveryError == nil
        return VStack(spacing: 44) {
            HStack(spacing: 10) {
                if state.detecting { ProgressView().controlSize(.small) }
                Text(state.detecting ? locale.text("正在发现 Agent", "Discovering Agents")
                     : needsInstall ? locale.text("安装一个 Agent", "Install an Agent")
                     : ready.isEmpty ? locale.text("暂时无法发现 Agent", "Unable to discover Agents")
                     : locale.text("发现 \(ready.count) 个 Agent", ready.count == 1 ? "Found 1 Agent" : "Found \(ready.count) Agents"))
                    .font(.system(size: 16, weight: .medium)).contentTransition(.numericText())
                    .accessibilityValue(pendingDiscoveryDescription)
            }
            if !ready.isEmpty || state.detecting {
                HStack(spacing: 28) {
                    ForEach(ready, id: \.descriptor.id) { harness in
                        VStack(spacing: 26) {
                            harness.logo(size: 72).frame(width: 86, height: 90).accessibilityHidden(true)
                            Text(harness.descriptor.displayName.string).font(.system(size: 16, weight: .medium))
                        }.frame(maxWidth: .infinity, minHeight: 168)
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(locale.text("已就绪", "Ready"))
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 18)))
                    }
                }.frame(height: 190)
            }
            if !missing.isEmpty {
                HStack(spacing: 24) {
                    ForEach(missing, id: \.descriptor.id) { harness in
                        VStack(spacing: 16) {
                            if needsInstall { harness.logo(size: 50).frame(height: 64).accessibilityHidden(true) }
                            if let guide = harness.descriptor.installationGuide {
                                Button { open(guide) } label: {
                                    Label(harness.descriptor.displayName.string, systemImage: "arrow.up.right")
                                }.buttonStyle(.plain)
                                    .accessibilityLabel(locale.text("安装 ", "Install ") + harness.descriptor.displayName.string)
                            } else if needsInstall { Text(harness.descriptor.displayName.string) }
                        }.font(.system(size: 12)).frame(maxWidth: .infinity)
                    }
                }
            }
            ForEach(state.harnesses, id: \.descriptor.id) { harness in
                if case .failed(let message) = state.discoveryState(harness) {
                    NativeSettingsNotice(message: harness.descriptor.displayName.string + ": " + message, kind: .error,
                        action: AnyView(Button(locale.text("重试", "Retry")) { state.retryDiscovery(harness) }
                            .buttonStyle(.borderless).disabled(!state.workspace.runtimeAvailable)
                            .nativeSettingsAction("retry." + harness.descriptor.id.string, label: "Retry " + harness.descriptor.displayName.string) {
                                state.retryDiscovery(harness)
                            }))
                }
            }
            if needsInstall {
                Text(locale.text("安装并登录后，重新检测。", "Install and sign in, then check again."))
                    .font(.system(size: 12)).foregroundStyle(secondary)
            }
        }.animation(reduceMotion ? nil : motion, value: ready.map(\.descriptor.id))
    }

    private func configurationForStep(_ step: NativeOnboardingStep, illustrationWidth: CGFloat) -> some View {
        configuration(step, illustrationWidth: illustrationWidth).environment(\.nativeSettingsReadiness, state.editors[step])
    }

    @ViewBuilder private func configuration(_ step: NativeOnboardingStep, illustrationWidth: CGFloat) -> some View {
        if step == .moku {
            NativeMokuSettings(model: state.settings, harnesses: state.installed, locale: locale, focusRequest: 0, motion: mapMotion,
                harnessSettings: { request in
                    AnyView(NativeHarnessSettingsView(host: state.workspace.harnessHost,
                        configuration: .init(harnessID: request.harnessID, cwd: JSONText(state.settings.defaultCwd),
                            source: request.savedValue, scope: .global(executionOwner: .moku)),
                        section: request.section, executionSnapshot: true, settingsFormPage: true,
                        refreshSequence: request.refreshSequence, value: request.value))
                }, onCoordinatorFrame: { _, _ in }, onCloseRequest: {}, presentation: .compact, illustrationWidth: illustrationWidth)
        } else if let id = step.settingID, let section = applicationSections.first(where: { $0.id == id }) {
            let saved = state.settings.savedSettings["pluginSettings"]?.arrayValue?.first(where: { $0["id"] == .text(id) })?["value"] ?? .null
            section.content(saved, state.settings.applicationValueBinding(id))
                .environment(\.nativeSettingsInteractionScope, id)
        } else {
            NativeSettingsNotice(message: locale.text("正在读取配置…", "Loading configuration…"))
                .nativeSettingsEditorReady(false)
        }
    }

    private func open(_ url: URL) {
        Task { do { try await state.workspace.services.openExternal(JSONText(url.absoluteString)) }
            catch { state.error = error.localizedDescription } }
    }

    @MainActor private func transition() async {
        let destination = state.step
        guard destination == .landing else {
            guard panelStep != destination else { return }
            await animate(motion) { panelStep = destination }
            guard !Task.isCancelled, state.step == destination else { return }
            presentedStep = destination
            return
        }

        // Prepare the hidden Dock while the form fades. Its actual geometry is
        // then available for the contraction to the existing composer seat.
        handoffPanelSize = state.panelFrame.isEmpty ? nil : state.panelFrame.size
        scene.disabled = !state.workspace.runtimeAvailable
        state.mountDock = true
        scene.setInputOpen(true)
        state.markHandoff(.fade)
        await animate(.easeOut(duration: 0.14)) { contentVisible = false }
        guard !Task.isCancelled else { return }
        state.markHandoff(.contract)
        await animate(.timingCurve(0.22, 1, 0.36, 1, duration: 0.78)) { collapsed = true }
        guard !Task.isCancelled else { return }
        // The Dock appears at full opacity behind the still-opaque panel, so
        // fading the panel never exposes the light workspace between them.
        state.markHandoff(.reveal)
        state.dockVisible = true
        let revealDuration = 0.18
        if scene.windowVisible {
            scene.dockCharacter?.scheduleOnboardingBlink(at: .now.addingTimeInterval(revealDuration))
        }
        await animate(.easeInOut(duration: revealDuration)) { panelVisible = false }
        guard !Task.isCancelled else { return }
        state.markHandoff(.finished)
        state.finishHandoff()
        if scene.windowVisible && NSApp.isActive { scene.focusOpenComposer() }
    }

    @MainActor private func animate(_ animation: Animation, _ updates: () -> Void) async {
        await withCheckedContinuation { continuation in
            // Ease curves reach their destination at logical completion.
            // Descendant illustrations can keep animating after input opens.
            withAnimation(animation, completionCriteria: .logicallyComplete, updates) { continuation.resume() }
        }
    }
}

/// The scroll document measures at its natural height. Only its viewport
/// gives up space when the panel reaches the window or panel height limit.
private struct NativeOnboardingPanelLayout: Layout {
    let documentHeight: CGFloat
    let heightLimit: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let chromeHeight = subviews[0].sizeThatFits(.init(width: width, height: nil)).height
            + subviews[2].sizeThatFits(.init(width: width, height: nil)).height
        return CGSize(width: width, height: max(chromeHeight, min(heightLimit, chromeHeight + documentHeight)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let chrome = ProposedViewSize(width: bounds.width, height: nil)
        let headerHeight = subviews[0].sizeThatFits(chrome).height
        let footerHeight = subviews[2].sizeThatFits(chrome).height
        let viewportHeight = max(0, bounds.height - headerHeight - footerHeight)
        subviews[0].place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top, proposal: chrome)
        subviews[1].place(at: CGPoint(x: bounds.midX, y: bounds.minY + headerHeight), anchor: .top,
                          proposal: .init(width: bounds.width, height: viewportHeight))
        subviews[2].place(at: CGPoint(x: bounds.midX, y: bounds.maxY), anchor: .bottom, proposal: chrome)
    }
}
