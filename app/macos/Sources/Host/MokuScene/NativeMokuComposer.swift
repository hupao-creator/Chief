import AppKit
import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI

extension EnvironmentValues {
    /// Cached workspaces can edit device-local text while host actions remain
    /// unavailable. A disabled lifecycle or read-only history owner still stays inert.
    @Entry public var nativeOfflineDraftEditing = false
}

/// Shared completion chrome. The Dock mounts it above the fixed input row so
/// insertion cannot animate the editor separately from its persistent face.
struct NativeMokuComposerCompletion: View {
    let mentions: NativeMokuDirectoryMentions
    let draft: NativeComposerDraft
    let maxHeight: CGFloat
    var onFrame: (CGRect?) -> Void = { _ in }

    var body: some View {
        NativeMokuDirectoryMentionList(mentions: mentions, maxHeight: maxHeight,
            onChoose: { mentions.choose($0, draft: draft) })
            .clipped()
            .padding(.horizontal, 12).padding(.top, 12)
            .overlay(alignment: .bottom) { Color.primary.opacity(0.08).frame(height: 1).padding(.horizontal, 18) }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("native-moku-dock")) } action: { onFrame($0) }
            .onDisappear { onFrame(nil) }
    }
}

/// Reflows the four persistent seats without replacing the native editor at a
/// width breakpoint; focus, selection and marked text belong to that same view.
private struct NativeMokuComposerRowLayout: Layout {
    var compact: Bool

    private func sizes(_ subviews: Subviews, width: CGFloat) -> [CGSize] {
        let eye = subviews[0].sizeThatFits(.unspecified)
        let attachment = subviews[1].sizeThatFits(.unspecified)
        let actions = subviews[3].sizeThatFits(.unspecified)
        let editorWidth = compact ? width : max(0, width - eye.width - attachment.width - actions.width)
        let editor = subviews[2].sizeThatFits(.init(width: editorWidth, height: nil))
        return [eye, attachment, CGSize(width: editorWidth, height: editor.height), actions]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 560
        let seats = sizes(subviews, width: width)
        let height = compact ? seats[2].height + 40
            : seats.map(\.height).max()!
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let seats = sizes(subviews, width: bounds.width)
        if compact {
            let controlsY = bounds.minY + seats[2].height + 17
            subviews[0].place(at: CGPoint(x: bounds.minX, y: controlsY),
                anchor: .leading, proposal: .init(seats[0]))
            subviews[1].place(at: CGPoint(x: bounds.minX + seats[0].width, y: controlsY),
                anchor: .leading, proposal: .init(seats[1]))
            subviews[2].place(at: bounds.origin, anchor: .topLeading, proposal: .init(seats[2]))
            subviews[3].place(at: CGPoint(x: bounds.maxX, y: controlsY),
                anchor: .trailing, proposal: .init(seats[3]))
        } else {
            var x = bounds.minX
            for index in seats.indices {
                subviews[index].place(at: CGPoint(x: x, y: bounds.midY),
                    anchor: .leading, proposal: .init(seats[index]))
                x += seats[index].width
            }
        }
    }
}

enum NativeOverviewComposerAction {
    case send, stop, dockStop
}

/// The scene supplies the Dock input row with its draft and send authority.
struct NativeMokuComposerInput: View {
    static let actionTrailingInset: CGFloat = 13

    let draft: NativeComposerDraft
    var cwd: JSONText = ""
    var disabled = false
    var awaitingContinuation = false
    // A native Return can arrive on the settlement stack before SwiftUI
    // refreshes the editor callback. Read the draft's live send barrier.
    private var submissionPending: Bool { draft.submitting || awaitingContinuation }
    var targetsThread = false
    var sidecardComposer: SidecardComposerRequest?
    var placeholderIcon: AnyView?
    var onEmptyEditorHold: (() -> Void)?
    var readOnly = false
    var focusEnabled = true
    var automaticFocus = true
    var focusRequestKey = 0
    var suppressInitialFocus = false
    var onFocusRequestAcquired: ((Int, NSTextView) -> Void)? = nil
    var maxHeight: CGFloat = 126
    var landing = false
    var compact = false
    var retainedText: String?
    var retainedAttachments: [NativeComposerAttachment]?
    var retainedDirectories: [NativeComposerDirectory]?
    var running = false
    var onCancel: () -> Void = {}
    var overviewAction: NativeOverviewComposerAction?
    var showsEyes = false
    var selectionRequest: NativeComposerSelectionRequest?
    var initialSelection: NSRange?
    var onEditorStateChange: ((NativeComposerEditorState) -> Void)?
    var onKeyDown: ((NativeComposerKeyEvent) -> Bool)?
    var onEditorSeatChange: ((CGFloat) -> Void)?
    var onEscape: (() -> Void)?
    let onSend: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Environment(\.nativeOfflineDraftEditing) private var offlineDraftEditing
    @Namespace private var composerSpace
    @State private var editorID = UUID()
    @State private var composingDraft: NativeComposerDraft?
    @State private var hostPicker: NativeComposerHostFilePicker.Mode?

    private var actionsUnavailable: Bool {
        disabled || (submissionPending && sidecardComposer == nil) || draft.clearing || draft.isDisposed
    }
    private var editingUnavailable: Bool { (disabled && !offlineDraftEditing) || draft.clearing || draft.isDisposed }

    private var hasInput: Bool {
        !NativeComposerSubmissionPolicy.trimmedText(retainedText ?? draft.inputText).isEmpty
            || !(retainedAttachments ?? draft.inputAttachments).isEmpty
            || !(retainedDirectories ?? draft.inputDirectories).isEmpty
    }
    private var placeholder: String {
        if let sidecardComposer { return sidecardComposer.placeholder }
        if onEmptyEditorHold != nil {
            return localize("长按开启语音，或输入消息…", "Hold for Voice Mode or type a message…")
        }
        return localize("输入消息…", "Type a message…")
    }
    var body: some View {
        input.foregroundStyle(.primary).disabled(editingUnavailable || readOnly)
            .onChange(of: ObjectIdentifier(draft)) { _, _ in
                if composingDraft !== draft { updateComposition(false) }
            }
            .onDisappear { updateComposition(false) }
            .sheet(item: $hostPicker) { mode in NativeComposerHostFilePicker(draft: draft, mode: mode) }
    }
    private var input: some View {
        let attachments = retainedAttachments ?? draft.inputAttachments
        let directories = retainedDirectories ?? draft.inputDirectories
        return VStack(spacing: 0) {
            NativeComposerAttachmentChips(attachments: attachments, directories: directories,
                containerRadius: NativeMokuCapsuleLayout.cornerRadius,
                onRemove: { id in Task { await draft.removeAttachment(id) } }, onRemoveDirectory: draft.removeDirectory)
                .disabled(actionsUnavailable || readOnly)
            NativeMokuComposerRowLayout(compact: compact) {
                eyeSeat
                attachmentButton
                editor
                HStack(spacing: 0) { actions }
            }.padding(.leading, 6).padding(.trailing, Self.actionTrailingInset)
            footer
        }.coordinateSpace(name: composerSpace)
            .foregroundStyle(.primary).disabled(editingUnavailable || readOnly)
    }
    private var footer: some View {
        VStack(spacing: 0) {
            if let previous = draft.interruptedInput {
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.requiresForkReview
                        ? localize("分支已创建，消息未发送。选择如何保留草稿后，可在该分支继续。", "The fork exists and the message was not sent. Choose what to keep, then continue in that branch.")
                        : localize("请核对会话中是否已收到上一条消息。", "Check the conversation for this interrupted send."))
                    Text(([previous.text] + previous.directories.map { $0.name.string }
                        + previous.attachments.map { $0.name.string }).joined(separator: " ")).lineLimit(3).textSelection(.enabled)
                    if draft.hasTrackedReceipt {
                        Button(localize("查询上一条回执", "Check previous receipt")) {
                            Task { await draft.checkPendingReceipt() }
                        }
                    } else {
                        HStack {
                            Button(localize("恢复到草稿", "Restore to draft")) { Task { await draft.reviewInterruptedSend(restore: true) } }
                            Button(localize("仅保留下一条草稿", "Keep next draft")) { Task { await draft.reviewInterruptedSend(restore: false) } }
                        }
                    }
                }.font(.caption).padding(.bottom, 8)
            }
            if draft.cleanupReceipt != nil && !draft.submitting {
                Button(localize("完成上一条回执清理", "Finish previous receipt cleanup")) {
                    Task { await draft.checkPendingReceipt() }
                }
            }
            if let error = draft.error {
                Text(sidecardComposer == nil ? composerLocalized(error, locale: locale)
                    : NativePluginLocalization.localize(error, locale: locale))
                    .font(.system(size: 11)).foregroundStyle(.red).padding(.bottom, 10)
            }
        }
    }
    // At high zoom/narrow widths the editor gets its own line. Fixed action
    // seats must never consume its entire width or compress native text to zero.
    private var eyeSeat: some View {
        Color.clear.frame(width: 43, height: 34)
            // Read the reserved seat inside the editor, including any footer.
            // Reopening must publish its current inset even if layout settled while folded.
            .onGeometryChange(for: CGFloat?.self) { [active = onEditorSeatChange != nil, composerSpace] geometry in
                guard active, let composer = geometry.bounds(of: .named(composerSpace)) else { return nil }
                return composer.maxY - geometry.size.height / 2
            } action: { inset in
                if let inset { onEditorSeatChange?(inset) }
            }
            .overlay {
                if showsEyes {
                    NativeMokuBlinkingEyes(expression: .focus, focus: 1)
                        .frame(width: 34, height: 25).offset(x: 4.5)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .allowsHitTesting(false)
    }
    private var editor: some View {
        NativeComposerTextInput(value: Binding(get: { retainedText ?? draft.inputText }, set: { draft.inputText = $0 }),
            draft: draft, placeholder: placeholder, placeholderIcon: placeholderIcon, placeholderLineLimit: 1,
            disabled: editingUnavailable, readOnly: readOnly || (submissionPending && sidecardComposer != nil),
            focusEnabled: focusEnabled, automaticFocus: automaticFocus,
            focusRequestKey: focusRequestKey, focusContext: "moku-dock",
            suppressInitialFocus: suppressInitialFocus,
            onFocusRequestAcquired: onFocusRequestAcquired,
            minHeight: compact ? 32 : (landing ? 76 : 58), maxHeight: compact ? max(32, maxHeight - 40) : maxHeight,
            fontSize: landing ? 16 : 14, lineHeight: landing ? 24 : 20,
            insets: .init(top: compact ? 6 : (landing ? 26 : 19), left: 6,
                         bottom: compact ? 6 : (landing ? 26 : 19), right: 6),
            onSubmit: { if !actionsUnavailable && draft.canSubmit && (sidecardComposer?.ready ?? true) { onSend() } }, onEscape: onEscape,
            onFiles: importFiles, preparePaste: preparePaste,
            selectionRequest: selectionRequest, initialSelection: initialSelection, preservesSelection: true, onEditorStateChange: { state in
                updateComposition(state.composing)
                onEditorStateChange?(state)
            }, onKeyDown: onKeyDown, onTypingKey: NativeMokuTypingSound.play, submitOnReturn: true,
            emphasizedInsertionPoint: true, onEmptyEditorHold: onEmptyEditorHold)
            .help(editorHelp)
    }
    private func updateComposition(_ active: Bool) {
        let owner = active ? draft : nil
        guard composingDraft !== owner else { return }
        composingDraft?.setComposing(false, editor: editorID)
        composingDraft = owner
        owner?.setComposing(true, editor: editorID)
    }

    private var importFiles: (([NativeComposerFile]) async -> Void)? {
        guard sidecardComposer == nil else { return nil }
        return { files in if !actionsUnavailable { await draft.importFiles(files) } }
    }
    private var preparePaste: (() -> NativeComposerPastePreparation?)? {
        guard sidecardComposer == nil else { return nil }
        return draft.preparePaste
    }
    private var editorHelp: String {
        if sidecardComposer != nil {
            return localize("描述当前网页选区；Return 发送，Shift+Return 换行，Esc 取消标注", "Describe the selected page area; Return sends, Shift+Return adds a line, Escape cancels annotation")
        }
        return targetsThread
            ? localize("输入内容将直接发送给此 Thread", "Input is sent directly to this thread")
            : localize("输入内容将发送给 Chief", "Input is sent to Chief")
    }
    @ViewBuilder private var actions: some View {
        if overviewAction == nil && running && !targetsThread {
            stopMark.frame(width: 32, height: 32).accessibilityHidden(true)
                .overlay { stopButton }
        }
        // The ordinary Overview Dock carries Stop through the fold. Its hit
        // target occupies this same seat when the editor is open.
        let send = overviewAction == .send || (overviewAction == nil && hasInput)
        let stop = !send && (overviewAction == .stop || (overviewAction == nil && running && targetsThread))
        let enabled = !actionsUnavailable && draft.canSubmit && !readOnly && (sidecardComposer?.ready ?? true)
        ZStack {
            NativeIcon(name: "ArrowUp", size: 16).frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.18), in: Circle())
                // A chip can disappear in the same update. Only the ink fades;
                // the glyph must move with the bottom-anchored editor row.
                .animation(reduceMotion ? nil : .mokuInk) { $0.opacity(send ? (enabled ? 1 : 0.3) : 0) }
            stopMark.animation(reduceMotion ? nil : .mokuInk) { $0.opacity(stop ? 1 : 0) }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .frame(width: 32, height: 32)
        .overlay {
            if send {
                let label = sidecardComposer == nil ? localize("发送", "Send") : localize("发送批注", "Send annotation")
                NativeMokuSendButton(draft: draft, label: label, send: onSend)
                    .disabled(!enabled)
                    .transition(.identity)
            } else if stop {
                stopButton.transition(.identity)
            }
        }
    }
    private var stopMark: some View {
        RoundedRectangle(cornerRadius: 1).fill(.foreground).frame(width: 10, height: 10)
    }
    private var stopButton: some View {
        Button(action: onCancel) {
            Color.clear.frame(width: 32, height: 32).contentShape(Circle())
        }.buttonStyle(.plain).disabled(actionsUnavailable || readOnly)
            .help(stopLabel)
            .accessibilityLabel(stopLabel)
            .accessibilityIdentifier("moku-stop")
    }
    private var attachmentButton: some View {
        let annotating = sidecardComposer != nil
        let label = annotating ? localize("取消标注", "Cancel annotation") : localize("添加文件或文件夹", "Add files or folders")
        return Button {
            if let sidecardComposer { sidecardComposer.cancel() }
            else { chooseDeviceItems() }
        } label: {
            ZStack {
                Image(systemName: "plus").font(.system(size: 14, weight: .medium))
                    .animation(reduceMotion ? nil : .mokuInk) { $0.opacity(annotating ? 0 : 1) }
                NativeIcon(name: "X", size: 16)
                    .animation(reduceMotion ? nil : .mokuInk) { $0.opacity(annotating ? 1 : 0) }
            }.frame(width: 28, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !annotating && draft.supportsHostFiles {
                Button(localize("从主机选择文件", "Choose host files")) { hostPicker = .files }
                Button(localize("从主机选择目录", "Choose a host directory")) { hostPicker = .directory }
            }
        }
        .disabled(!annotating && (actionsUnavailable || draft.importing || readOnly))
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier(annotating ? "moku-cancel-annotation" : "moku-add-attachment")
    }
    private func chooseDeviceItems() {
        Task.immediate { await draft.chooseItems(cwd: cwd) }
    }
    private var stopLabel: String {
        targetsThread ? localize("停止此 Thread", "Stop this thread") : localize("停止 Chief", "Stop Chief")
    }
    private func localize(_ zh: String, _ en: String) -> String { locale.language.languageCode?.identifier == "zh" ? zh : en }
}

private struct NativeMokuSendButton: NSViewRepresentable {
    let draft: NativeComposerDraft
    let label: String
    let send: () -> Void
    @Environment(\.isEnabled) private var enabled

    final class Control: NSButton {
        weak var draft: NativeComposerDraft?
        var send: (() -> Void)?
        override var acceptsFirstResponder: Bool {
            NSApp.currentEvent?.type == .leftMouseDown ? false : super.acceptsFirstResponder
        }
        @objc func submit() {
            guard isEnabled, draft?.canSubmit == true else { return }
            send?()
        }
        override func mouseDown(with event: NSEvent) {
            // Tracking can end an input method session. Reject the press while
            // the marked buffer still belongs to the input method.
            guard event.clickCount == 1, draft?.canSubmit == true else { return }
            super.mouseDown(with: event)
        }
    }

    func makeNSView(context: Context) -> Control {
        let button = Control()
        button.title = ""
        button.isBordered = false
        button.isTransparent = true
        button.setButtonType(.momentaryPushIn)
        button.identifier = .init("moku-send")
        button.setAccessibilityIdentifier("moku-send")
        button.target = button
        button.action = #selector(Control.submit)
        return button
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Control, context: Context) -> CGSize? {
        CGSize(width: 32, height: 32)
    }

    func updateNSView(_ button: Control, context: Context) {
        button.isEnabled = enabled
        button.setAccessibilityLabel(label)
        button.draft = draft
        button.send = send
    }
}
