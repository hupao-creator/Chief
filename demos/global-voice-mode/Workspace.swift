import ChiefCore
import ChiefHarnessClaude
import ChiefPluginAPI
import ChiefPluginUI
@testable import ChiefUI
import Observation
import SwiftUI

@MainActor @Observable final class Workspace {
    static let title = "整理本周发布说明"
    static let brief = "把本周的更新整理成一页，优先写用户能感受到的变化。"
    static let result = "发布说明的初稿已完成，分为新增功能和体验改进两部分。"
    static let threadID: JSONText = "demo-release-notes"
    let voice = VoiceSession()
    let scene = NativeMokuSceneState()
    let harness = AnyHarnessPlugin(ClaudeHarnessPlugin())
    let card = try! composeThreadCard(.standard(identity: .init(), extensions: []),
                                      layoutContext: .init(availableCols: 3))
    let chiefDraft = makeDraft()
    let agentDraft = makeDraft()
    private(set) var taskOpen = false
    private(set) var route = UUID()
    private(set) var chiefMessages: [String] = []
    private(set) var agentMessages: [String] = []

    init() { scene.setComposerContext(chiefDraft, opensInput: false) }

    private static func makeDraft() -> NativeComposerDraft {
        NativeComposerDraft(services: .init(stageFiles: { _, _ in [] }, discardAttachments: { _ in }))
    }

    func showTask(_ open: Bool) {
        guard taskOpen != open else { return }
        route = UUID()
        scene.executionDockPlacement.beginRoute(route)
        taskOpen = open
        if open {
            scene.readingPanelVisible = true
            scene.overviewVisible = false
            scene.setComposerContext(agentDraft, opensInput: true, keepsInputOpen: true, autofocus: false)
        } else {
            scene.overviewVisible = true
            scene.readingPanelVisible = false
            scene.setComposerContext(chiefDraft, opensInput: false)
        }
    }

    func receive(_ submission: NativeComposerSubmission, forTask: Bool) {
        if forTask { agentMessages.append(submission.text) }
        else { chiefMessages.append(submission.text) }
    }

    static func columnWidth(in width: CGFloat) -> CGFloat { min(358, width * 0.40) }
}

struct DemoWorkspace: View {
    let model: Workspace
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geometry in
            NativeMokuScene(state: model.scene) {
                if model.taskOpen { taskPage(in: geometry.size) } else { overview }
            } dock: {
                let forTask = model.taskOpen
                NativeMokuDock(state: model.scene, draft: forTask ? model.agentDraft : model.chiefDraft,
                    cwd: "/demo", threadID: forTask ? Workspace.threadID : nil,
                    threadHarness: forTask ? model.harness : nil,
                    onThreadClose: forTask ? { model.showTask(false) } : nil,
                    onSend: { model.receive($0, forTask: forTask) }, onCancel: {})
                    .environment(\.chiefVoiceDock, VoiceDockControls(phase: model.voice.phase,
                        microphoneMuted: model.voice.microphoneMuted,
                        levels: { (model.voice.awaitingReply ? 0.8 : 0, model.voice.phase == .speaking ? 0.95 : 0) },
                        start: model.voice.start,
                        toggleMute: model.voice.toggleMute, end: model.voice.end))
            } settings: { EmptyView() }
            .environment(\.nativeExecutionDockRoute, model.route)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(scheme == .dark ? Color(red: 0.13, green: 0.14, blue: 0.14)
                                    : Color(red: 0.94, green: 0.94, blue: 0.92))
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .background { VoiceMenu(model: model, state: VoiceMenuState(model)).frame(width: 0, height: 0) }
        .onDisappear { model.voice.end() }
    }

    private var overview: some View {
        VStack(spacing: 0) {
            HStack {
                Text("概览").font(.title2.weight(.semibold))
                Spacer()
                simulationLabel
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Text("最近任务").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Button { model.showTask(true) } label: {
                    HarnessThreadCard(identity: .init(title: Workspace.title,
                        harness: .init(brandKey: "claude", label: "Claude", logoSource: model.harness.logoSource),
                        model: "Claude Sonnet", excerpt: Workspace.brief),
                        presentation: model.card, status: .init(kind: .completed, label: "已完成"),
                        emoji: "📝", harnessLogo: model.harness.logo(size: 12))
                        .frame(width: 216, height: 152)
                        .background(NativePalette.overview.surface.swiftUI, in: RoundedRectangle(cornerRadius: 22))
                        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(NativePalette.overview.lineSoft.swiftUI) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开任务，整理本周发布说明")
                .accessibilityIdentifier("voice-demo-task")
            }
            Spacer()
            if !model.scene.inputOpen, model.voice.phase == .idle {
                Text(model.chiefMessages.last.map { "已发给 Chief · " + $0 } ?? "轻点 Chief Bar 写字，长按开启语音。")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    .padding(.bottom, 89)
            } else { Color.clear.frame(height: 108) }
        }
        .padding(.horizontal, 32).padding(.top, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var simulationLabel: some View {
        Label("模拟通话 · 麦克风未启用", systemImage: "mic.slash")
            .font(.caption).foregroundStyle(.secondary)
            .help("在菜单栏的「语音演示」中可以模拟说话和打断回复。")
    }

    private func taskPage(in size: CGSize) -> some View {
        let column = Workspace.columnWidth(in: size.width)
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                Button { model.showTask(false) } label: { Label("概览", systemImage: "chevron.left") }
                    .buttonStyle(.borderless).accessibilityIdentifier("voice-demo-back")
                Spacer().frame(height: 10)
                Text(Workspace.title).font(.title.weight(.semibold))
                Text(Workspace.brief).font(.body).foregroundStyle(.secondary)
                Divider()
                Text("初稿").font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    Text("新增功能").font(.subheadline.weight(.medium))
                    Text("在概览里按标签筛选任务。")
                    Text("体验改进").font(.subheadline.weight(.medium)).padding(.top, 6)
                    Text("重新打开文字框，继续编辑之前的草稿。")
                }
                Spacer()
                simulationLabel.padding(.bottom, 96)
            }
            .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 8) {
                    model.harness.logo(size: 20)
                    Text("Claude 任务对话").font(.headline)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(Workspace.result)
                        ForEach(Array(model.agentMessages.enumerated()), id: \.offset) { _, text in
                            Text("你 · " + text).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, 120)
            }
            .padding(24)
            .frame(width: column, height: size.height, alignment: .topLeading)
            .background(.background.opacity(0.50))
            .background {
                NativeExecutionDockRegion(placement: model.scene.executionDockPlacement,
                                          threadID: Workspace.threadID)
            }
        }
    }
}
