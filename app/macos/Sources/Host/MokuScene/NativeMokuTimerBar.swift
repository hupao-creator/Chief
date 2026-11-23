import AppKit
import ChiefPluginUI
import SwiftUI

struct NativeMokuTimerBar: View {
    static let preferredWidth: CGFloat = 420
    let timer: NativeMokuTimerController
    let message: NativeMokuTimerMessage
    let exclusions: NativeClickExclusions
    @Environment(\.reminderScrollRegions) private var reminderScrollRegions
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                NativeMokuCapsuleEyes(expression: .surprised, focus: 0)
                    .fill(.white).frame(width: 38, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Label(caption, systemImage: "bell.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 1, green: 0.82, blue: 0.54))
                    messageContent.id(message.id)
                }
                NativeMokuTimerReceiptButton(title: localize("已收到", "Received")) {
                    timer.acknowledge(id: message.id)
                }.fixedSize()
            }
            if let error = timer.audioError {
                HStack {
                    Text(localize("铃声播放失败：", "Bell unavailable: ") + error).font(.caption)
                    Button(localize("重试铃声", "Retry bell")) { timer.retryAudio() }.fixedSize()
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18).padding(.vertical, 11)
        .background {
            NativeMokuCapsuleGlass(interactive: false)
                .background(Color(white: 0.15), in: .rect(cornerRadius: NativeMokuCapsuleLayout.cornerRadius))
        }
        .shadow(color: .black.opacity(0.17), radius: 7, y: 4)
        .background(NativeClickExclusionRegion(exclusions: exclusions))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localize("Chief 提醒，等待确认", "Chief timer, awaiting acknowledgment"))
        .accessibilityIdentifier("moku-timer")
        .environment(\.colorScheme, .dark)
    }

    private var caption: String {
        let waiting = timer.pending.count - 1
        return waiting > 0 ? localize("提醒 · 另有 \(waiting) 条待确认", "Alert · \(waiting) more waiting")
            : localize("提醒 · 等待确认", "Alert · Awaiting receipt")
    }

    private var messageContent: some View {
        let text = Text(message.text).font(.system(size: 14, weight: .medium))
            .lineSpacing(3).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("moku-timer-content")
        return ViewThatFits(in: .vertical) {
            text
            NativeScrollView { text }.defaultScrollAnchor(.top).frame(height: 40)
                .nativeCanvasNavigationRegion()
                .environment(\.nativeCanvasInputRegions, reminderScrollRegions)
        }
        .frame(maxHeight: 40).fixedSize(horizontal: false, vertical: true)
    }

    private func localize(_ zh: String, _ en: String) -> String {
        locale.language.languageCode?.identifier == "zh" ? zh : en
    }
}

/// Native accessibility remains available in a windowless host. Ignore the
/// second mouse-down of a double click even if the next queued message has
/// already updated this same button's action in between the two events.
struct NativeMokuTimerReceiptButton: NSViewRepresentable {
    let title: String
    let acknowledge: () -> Void

    func makeNSView(context: Context) -> ReceiptButton {
        let button = ReceiptButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.identifier = .init("moku-timer-acknowledge")
        button.target = button
        button.action = #selector(ReceiptButton.receive)
        updateNSView(button, context: context)
        return button
    }
    func updateNSView(_ button: ReceiptButton, context: Context) {
        button.title = title
        button.setAccessibilityLabel(title)
        button.acknowledge = acknowledge
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ReceiptButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    @MainActor final class ReceiptButton: NSButton {
        var acknowledge: () -> Void = {}
        @objc func receive() { acknowledge() }
        override func accessibilityPerformPress() -> Bool {
            guard isEnabled else { return false }
            // A receipt does not need AppKit's click animation or a responder
            // transfer. Report the accessibility action as handled explicitly.
            receive()
            return true
        }
        override func mouseDown(with event: NSEvent) {
            guard event.clickCount == 1 else { return }
            super.mouseDown(with: event)
        }
    }
}
