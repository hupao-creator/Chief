import AppKit
import SwiftUI
import ChiefPluginUI

/// A snapshot of the single workspace call. The mounted interaction replay
/// supplies the same controls with a local audio fixture.
struct VoiceDockControls {
    let phase: VoicePhase
    let microphoneMuted: Bool
    let start, toggleMute, end: @MainActor () -> Void
}

extension EnvironmentValues {
    @Entry var chiefVoiceDock: VoiceDockControls? = nil
}

extension VoicePhase {
    var connected: Bool { self == .listening || self == .speaking || self == .muted }

    func menuTitle(_ language: DesktopLocale) -> String {
        switch self {
        case .idle: language.text("开始语音模式", "Start Voice Mode")
        case .connecting: language.text("取消语音连接", "Cancel Voice Connection")
        case .listening, .speaking, .muted: language.text("退出语音模式", "End Voice Mode")
        }
    }
}

/// The editor defines the Bar's size. Both glass surfaces travel in that Bar's
/// native host, including while it moves sideways into an execution column.
struct VoiceDock: ViewModifier {
    static let diameter: CGFloat = 40
    static let gap: CGFloat = 16
    let voice: VoiceDockControls?
    let scene: NativeMokuSceneState
    let pressArea: VoiceBarPress.Area?
    let conversation: Bool
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Namespace private var glass
    @State private var mounted = false
    @State private var separated = false

    static func hitFrame(_ bar: CGRect, scale: CGFloat) -> CGRect {
        let orb = CGRect(x: bar.maxX + gap * scale, y: bar.midY - diameter * scale / 2,
                         width: diameter * scale, height: diameter * scale)
        // Include the path crossed by the button before the glass settles.
        return CGRect(x: bar.maxX, y: orb.minY, width: orb.maxX - bar.maxX, height: orb.height)
    }

    private var active: Bool { voice?.phase.connected == true && !scene.settingsOpen }
    private var language: DesktopLocale { DesktopLocale(primaryLanguage: locale.identifier) }

    func body(content: Content) -> some View {
        content
            .background { if voice != nil && !scene.settingsOpen { material } }
            .overlay { press }
            .overlay(alignment: .trailing) { orbButton }
            .accessibilityActions {
                if let voice, pressArea != nil {
                    Button(voice.phase.menuTitle(language)) {
                        if voice.phase == .idle { voice.start() } else { voice.end() }
                    }
                }
            }
            .task(id: active) { await present(active) }
    }

    @ViewBuilder private var press: some View {
        if let voice, !scene.settingsOpen {
            VoiceBarPress(area: pressArea, route: scene.composerGeneration,
                tip: voice.phase == .idle && !scene.inputOpen
                    ? language.text("轻点写字，长按开启语音", "Click to type or hold for Voice Mode") : nil,
                start: voice.start, click: {
                    if scene.inputOpen { scene.focusOpenComposer() }
                    else { scene.toggleInput(focusOnOpening: true) }
                })
        }
    }

    @ViewBuilder private var orbButton: some View {
        if active, mounted, let voice {
            OrbButton(voice: voice, language: language)
                .frame(width: Self.diameter, height: Self.diameter)
                .nativeCanvasNavigationRegion(in: scene.swipeRegions.voice)
                .offset(x: separated ? Self.diameter + Self.gap : 0)
        }
    }

    private var material: some View {
        GeometryReader { bar in
            let width = bar.size.width, height = bar.size.height
            GlassEffectContainer(spacing: 14) {
                ZStack(alignment: .leading) {
                    Color.clear.frame(width: width, height: height)
                        .glassEffect(opaque ? .identity : conversation ? .regular : .clear.interactive(),
                                     in: .rect(cornerRadius: NativeMokuCapsuleLayout.cornerRadius))
                        .glassEffectID("chief", in: glass)
                        .glassEffectTransition(.matchedGeometry)
                        .overlay { NativeMokuCapsuleFinish(opaque: opaque).opacity(conversation && !opaque ? 0 : 1) }
                    if mounted {
                        Circle().fill(opaque ? Color(white: 0.25) : .clear)
                            .frame(width: Self.diameter, height: Self.diameter)
                            .glassEffect(opaque ? .identity : .clear.tint(.blue.opacity(0.16)), in: .circle)
                            .glassEffectID("voice", in: glass)
                            .glassEffectTransition(.matchedGeometry)
                            .overlay {
                                if let voice, voice.phase.connected {
                                    VoiceOrb(phase: voice.phase, microphoneMuted: voice.microphoneMuted)
                                        .opacity(separated ? 1 : 0)
                                }
                            }
                            .offset(x: width + (separated ? Self.gap : -Self.diameter))
                    }
                }
                .frame(width: width + Self.gap + Self.diameter, height: height, alignment: .leading)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func present(_ active: Bool) async {
        if reduceMotion {
            mounted = active
            separated = active
            return
        }
        guard active || mounted else { return }
        if active && !mounted {
            mounted = true
            // Give the compositor a frame with both surfaces at the trailing cap.
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
        }
        let duration = 0.48
        withAnimation(.easeInOut(duration: duration)) { separated = active }
        if !active {
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            mounted = false
        }
    }
}

/// Look toward the edge where the orb will emerge. The passive seat can
/// briefly show Chief's own eyes even when an execution owns the editor.
struct VoiceGlance: ViewModifier {
    let preparing: Bool
    let inTask: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(inTask && preparing ? 0 : 1)
            .overlay {
                if inTask && preparing {
                    NativeMokuCapsuleEyes(expression: .idle, focus: 0).fill(.white)
                }
            }
            .scaleEffect(x: 1, y: preparing ? 0.90 : 1)
            .rotationEffect(.degrees(preparing ? -10 : 0))
            .offset(x: preparing ? 4 : 0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.13), value: preparing)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct OrbButton: NSViewRepresentable {
    let voice: VoiceDockControls
    let language: DesktopLocale

    func makeNSView(context: Context) -> Button {
        let button = Button()
        button.identifier = .init("voice-orb")
        button.isBordered = false
        button.title = ""
        button.refusesFirstResponder = true
        button.target = button
        button.action = #selector(Button.toggleMute)
        return button
    }

    func updateNSView(_ button: Button, context: Context) {
        button.voice = voice
        let primary = voice.microphoneMuted ? language.text("恢复收音", "Unmute") : language.text("静音", "Mute")
        let exit = language.text("退出语音模式", "End Voice Mode")
        button.toolTip = language.text("轻点\(primary)，右键退出语音模式", "Click to \(primary.lowercased()) or right-click to end Voice Mode")
        button.setAccessibilityLabel(language.text("语音球，\(primary)", "Voice orb, \(primary)"))
        button.setAccessibilityHelp(language.text("右键退出语音模式", "Right-click to end Voice Mode"))
        let input = voice.microphoneMuted ? language.text("麦克风已静音", "Microphone muted") : language.text("正在聆听", "Listening")
        button.setAccessibilityValue(voice.phase == .speaking ? language.text("Chief 正在说话", "Chief is speaking") + ", " + input : input)
        button.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: exit, target: button, selector: #selector(Button.exitVoice))])
        button.setAccessibilityIdentifier("voice-orb")
    }

    final class Button: NSButton {
        var voice: VoiceDockControls?
        private var secondaryPress = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        @objc func toggleMute() { voice?.toggleMute() }
        @objc func exitVoice() -> Bool {
            guard let voice, voice.phase.connected else { return false }
            voice.end()
            return true
        }

        override func rightMouseDown(with event: NSEvent) { secondaryPress = true }
        override func rightMouseUp(with event: NSEvent) { finishSecondaryPress(event) }
        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { secondaryPress = true }
            else {
                secondaryPress = false
                super.mouseDown(with: event)
            }
        }
        override func mouseUp(with event: NSEvent) {
            if secondaryPress { finishSecondaryPress(event) }
            else { super.mouseUp(with: event) }
        }
        override func mouseCancelled(with event: NSEvent) {
            secondaryPress = false
            super.mouseCancelled(with: event)
        }

        private func finishSecondaryPress(_ event: NSEvent) {
            guard secondaryPress else { return }
            secondaryPress = false
            if bounds.contains(convert(event.locationInWindow, from: nil)) { _ = exitVoice() }
        }
    }
}
