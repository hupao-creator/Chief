@testable import ChiefUI
import AppKit
import ChiefPluginUI
import SwiftUI

@main @MainActor struct VoiceDemo: App {
    @State private var model = Workspace()
    init() {
        if CommandLine.arguments.contains("--replay") {
            do { try prepareIsolatedNativeReplay() }
            catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
        }
        NativeTypography.registerFonts()
    }

    var body: some Scene {
        Window("Chief · 全局 Voice Mode", id: "global-voice-demo") {
            DemoWorkspace(model: model)
                .frame(minWidth: 740, minHeight: 520)
                .transformEnvironment(\.accessibilityEnabled) { if CommandLine.arguments.contains("--replay") { $0 = true } }
                .task {
                    if let flag = CommandLine.arguments.firstIndex(of: "--replay"),
                       CommandLine.arguments.indices.contains(flag + 1) {
                        let directory = URL(fileURLWithPath: CommandLine.arguments[flag + 1], isDirectory: true)
                        await VoiceDemoReplay.run(model: model, directory: directory)
                    }
                }
        }
        .defaultSize(width: 1020, height: 620)
        .defaultLaunchBehavior(.presented)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
    }
}

/// Publish values from the mounted window so AppKit refreshes menu availability
/// when a mouse gesture changes the call or playback finishes.
struct VoiceMenuState: Equatable {
    let phase: VoicePhase
    let muted, awaitingReply, taskOpen: Bool

    @MainActor init(_ model: Workspace) {
        phase = model.voice.phase
        muted = model.voice.microphoneMuted
        awaitingReply = model.voice.awaitingReply
        taskOpen = model.taskOpen
    }
}

struct VoiceMenu: NSViewRepresentable {
    let model: Workspace
    let state: VoiceMenuState

    func makeNSView(context: Context) -> Host { Host(model: model) }
    func updateNSView(_ view: Host, context: Context) { view.update(state) }
    static func dismantleNSView(_ view: Host, coordinator: ()) { view.detach() }

    final class Host: NSView, NSMenuDelegate {
        let model: Workspace
        private let voiceMenu = NSMenu(title: "语音演示")
        private let entry = NSMenuItem(title: "语音演示", action: nil, keyEquivalent: "")
        private let toggle = NSMenuItem(title: "", action: #selector(toggleVoice(_:)), keyEquivalent: "V")
        private let sample = NSMenuItem(title: "模拟说一句", action: #selector(playSample(_:)), keyEquivalent: "P")
        private let interrupt = NSMenuItem(title: "打断回复", action: #selector(interruptReply(_:)), keyEquivalent: "")
        private let mute = NSMenuItem(title: "", action: #selector(toggleMicrophone(_:)), keyEquivalent: "")
        private let route = NSMenuItem(title: "", action: #selector(toggleTask(_:)), keyEquivalent: "")

        init(model: Workspace) {
            self.model = model
            super.init(frame: .zero)
            voiceMenu.autoenablesItems = false
            voiceMenu.delegate = self
            entry.submenu = voiceMenu
            toggle.keyEquivalentModifierMask = [.command, .shift]
            sample.keyEquivalentModifierMask = [.command, .shift]
            for item in [toggle, sample, interrupt, mute, NSMenuItem.separator(), route] {
                item.target = self
                voiceMenu.addItem(item)
            }
            setAccessibilityElement(false)
        }
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { update(VoiceMenuState(model)) }
            else { detach() }
        }
        func menuNeedsUpdate(_ menu: NSMenu) { update(VoiceMenuState(model)) }
        func update(_ state: VoiceMenuState) {
            toggle.title = state.phase.menuTitle(.chinese)
            sample.isEnabled = state.phase == .listening && !state.awaitingReply
            interrupt.isEnabled = state.phase == .speaking
            mute.title = state.muted ? "恢复收音" : "静音"
            mute.isEnabled = state.phase != .idle && state.phase != .connecting
            route.title = state.taskOpen ? "返回概览" : "打开示例任务"
            guard window != nil, let bar = NSApp.mainMenu, entry.menu !== bar else { return }
            detach()
            let index = bar.items.firstIndex { $0.submenu != nil && $0.submenu === NSApp.windowsMenu }
            bar.insertItem(entry, at: index ?? bar.numberOfItems)
        }
        func detach() { entry.menu?.removeItem(entry) }

        @objc private func toggleVoice(_ sender: NSMenuItem) {
            if model.voice.phase == .idle { model.voice.start() } else { model.voice.end() }
        }
        @objc private func playSample(_ sender: NSMenuItem) { model.voice.playExample() }
        @objc private func interruptReply(_ sender: NSMenuItem) { model.voice.interrupt() }
        @objc private func toggleMicrophone(_ sender: NSMenuItem) { model.voice.toggleMute() }
        @objc private func toggleTask(_ sender: NSMenuItem) { model.showTask(!model.taskOpen) }
    }
}
