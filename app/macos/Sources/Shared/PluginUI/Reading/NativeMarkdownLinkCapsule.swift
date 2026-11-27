import AppKit
import ChiefCore
import ChiefPluginAPI
import SwiftUI

/// Web links and execution capsules share TextKit selection and wrapping with the prose.
package struct NativeLinkedMessageText: View {
    private let spans: [MarkdownSpan]
    private let harnesses: [JSONText: AnyHarnessPlugin]
    private let compact: Bool
    @Environment(\.openURL) private var openURL
    @State private var reachedViewport = false

    package init(runs: [(text: String, url: URL?)], harnesses: [JSONText: AnyHarnessPlugin], compact: Bool) {
        spans = runs.map { MarkdownSpan(text: $0.text, link: $0.url?.absoluteString) }
        self.harnesses = harnesses
        self.compact = compact
    }

    package var body: some View {
        MarkdownSelectableText(spans: spans, fontSize: compact ? 13 : 15, weight: compact ? 600 : 400,
            strongInk: true, lineHeight: compact ? 19 : 20, alignment: compact ? .center : .left,
            linkCapsuleHarnesses: harnesses, showsLinkControls: compact || reachedViewport, glassLinkCapsules: compact,
            messageInk: compact ? nil : .white, openLink: { openURL($0) })
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: Bool.self) { geometry in
                guard !compact, let viewport = geometry.bounds(of: .scrollView) else { return false }
                // Prepare one viewport ahead. TextKit already reserves the exact inline seats.
                return CGRect(origin: .zero, size: geometry.size)
                    .intersects(viewport.insetBy(dx: 0, dy: -viewport.height))
            } action: { near in
                if near { reachedViewport = true }
            }
    }
}

extension NSAttributedString.Key {
    static let nativeMarkdownLinkCapsule = NSAttributedString.Key("ChiefMarkdownLinkCapsule")
}

/// TextKit owns the inline seat, wrapping and source selection. The live native
/// surface occupies that seat without replacing the document's text layout.
final class MarkdownLinkAttachment: NSTextAttachment {
    enum Kind {
        case web
        case execution(AnyHarnessPlugin?)
    }

    let title: String
    let url: URL
    let kind: Kind
    let usesGlass: Bool
    let fontSize: CGFloat
    let size: CGSize
    let verticalInset: CGFloat
    let wrapsTitle: Bool

    @MainActor init(title: String, url: URL, kind: Kind, usesGlass: Bool, fontSize: CGFloat, width: CGFloat) {
        self.title = title; self.url = url; self.kind = kind; self.usesGlass = usesGlass; self.fontSize = fontSize
        let font = NativeTypography.interPlatformFont(size: fontSize)
        let scale = fontSize / 13
        verticalInset = 4 * scale
        let chrome = 57 * scale
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3 * scale
        let text = NSAttributedString(string: title, attributes: [.font: font, .paragraphStyle: paragraph])
        let idealWidth = ceil(text.size().width) + chrome
        wrapsTitle = idealWidth > width
        let fittedWidth = min(width, idealWidth)
        let height = text.boundingRect(with: CGSize(width: max(1, fittedWidth - chrome), height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        size = CGSize(width: max(1, fittedWidth), height: ceil(max(fontSize * 1.2, height) + 14 * scale))
        super.init(data: nil, ofType: nil)
        let cell = MarkdownLinkCell(size: size, baseline: font.descender - 7 * scale)
        cell.setAccessibilityElement(false)
        attachmentCell = cell
    }

    required init?(coder: NSCoder) { nil }
}

private final class MarkdownLinkCell: NSTextAttachmentCell {
    let size: CGSize
    let baseline: CGFloat
    init(size: CGSize, baseline: CGFloat) {
        self.size = size; self.baseline = baseline
        super.init(textCell: "")
    }
    required init(coder: NSCoder) { fatalError("Link cells are document-owned") }
    override func cellSize() -> NSSize { size }
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: baseline) }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {}
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int) {}

    override func trackMouse(with event: NSEvent, in cellFrame: NSRect, of controlView: NSView?,
                             atCharacterIndex index: Int, untilMouseUp flag: Bool) -> Bool {
        guard event.clickCount == 1, event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty,
              let text = controlView as? MarkdownTextView, let window = text.window,
              let link = attachment as? MarkdownLinkAttachment else {
            return super.trackMouse(with: event, in: cellFrame, of: controlView, atCharacterIndex: index, untilMouseUp: flag)
        }
        // AppKit treats a drag starting on a standard attachment as a drag of
        // that attachment. A capsule instead anchors a text range at the press.
        let origin = text.convert(event.locationInWindow, from: nil)
        let anchor = text.characterIndexForInsertion(at: origin)
        var selecting = false
        while let sample = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let released = sample.type == .leftMouseUp
            selecting = selecting || !released
            if !released { _ = text.autoscroll(with: sample) }
            let point = text.convert(sample.locationInWindow, from: nil)
            if selecting, let storage = text.textStorage, anchor <= storage.length {
                let end = text.characterIndexForInsertion(at: point)
                text.setSelectedRange(NSRange(location: min(anchor, end), length: abs(end - anchor)),
                                      affinity: .downstream, stillSelecting: !released)
            } else if released, !selecting, cellFrame.contains(point), window.isKeyWindow,
                      let storage = text.textStorage, index < storage.length,
                      (storage.attribute(.attachment, at: index, effectiveRange: nil) as? MarkdownLinkAttachment) === link {
                _ = text.delegate?.textView?(text, clickedOnLink: link.url, at: index)
            }
            if released { return true }
        }
        return true
    }
}

private struct MarkdownLinkCapsule: View {
    let attachment: MarkdownLinkAttachment
    let selected: Bool
    let open: () -> Void
    @Environment(\.locale) private var locale
    private var scale: CGFloat { attachment.fontSize / 13 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 15 * scale) }
    private var web: Bool {
        if case .web = attachment.kind { return true }
        return false
    }
    private var name: String {
        let chinese = locale.language.languageCode?.identifier == "zh"
        switch attachment.kind {
        case .web: return chinese ? "网页链接" : "Web link"
        case .execution(let harness): return harness?.descriptor.displayName.string ?? (chinese ? "执行记录" : "Execution")
        }
    }

    var body: some View {
        Group {
            if attachment.usesGlass {
                button.glassEffect(.clear, in: shape)
            } else {
                // A solid fill gives the capsule the same color on both conversation bubbles.
                button.background(NativePalette.color(0x3c424b).swiftUI, in: shape)
                    .overlay { shape.strokeBorder(.white.opacity(0.12), lineWidth: 1) }
            }
        }
        .overlay {
            if selected { shape.strokeBorder(NativePalette.thread.accent.swiftUI, lineWidth: 1) }
        }
        .help(web ? attachment.url.absoluteString : "\(name) · \(attachment.title)")
        .accessibilityLabel("\(name) · \(attachment.title)")
        .accessibilityIdentifier(web ? "chief-web-link" : "chief-execution-link")
    }

    private var button: some View {
        Button(action: open) {
            HStack(spacing: 6 * scale) {
                Group {
                    if case .execution(.some(let harness)) = attachment.kind {
                        harness.logo(size: 15 * scale)
                    } else {
                        Image(systemName: web ? "globe" : "terminal").resizable().scaledToFit()
                            .foregroundStyle(web ? NativePalette.thread.accent.swiftUI : NativePalette.thread.muted.swiftUI)
                    }
                }.frame(width: 15 * scale, height: 15 * scale).accessibilityHidden(true)
                Text(verbatim: attachment.title).font(NativeTypography.inter(size: attachment.fontSize))
                    .foregroundStyle(NativePalette.thread.inkStrong.swiftUI)
                    .lineSpacing(3 * scale).fixedSize(horizontal: !attachment.wrapsTitle, vertical: true)
                Image(systemName: "arrow.up.right").font(.system(size: 10 * scale, weight: .medium))
                    .foregroundStyle(NativePalette.thread.muted.swiftUI).accessibilityHidden(true)
            }
            .padding(.horizontal, 10 * scale).padding(.vertical, 3 * scale)
            .frame(width: attachment.size.width, height: attachment.size.height - 2 * attachment.verticalInset)
            .contentShape(shape)
        }
        // Keep the painted capsule and its hit area stable during selection.
        .buttonStyle(.plain)
    }
}

/// Pointer events stay with TextKit, including drag selection beginning on a
/// capsule. The hosted Button remains keyboard/AX activatable independently.
final class MarkdownLinkHost: NSHostingView<AnyView> {
    private struct Presentation: Equatable {
        let attachment: ObjectIdentifier
        let selected: Bool
        let locale: Locale
        let dark: Bool
    }
    private var presentation: Presentation?
    private var openAction: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        sizingOptions = []; safeAreaRegions = []
    }
    required init?(coder: NSCoder) { nil }

    func update(_ attachment: MarkdownLinkAttachment, selected: Bool, locale: Locale, dark: Bool, open: @escaping () -> Void) {
        // Layout and selection notifications often repeat with identical input.
        // Replacing rootView each time invalidates a separate SwiftUI/glass graph
        // for every capsule. Navigation still receives the current callback.
        openAction = open
        let next = Presentation(attachment: ObjectIdentifier(attachment), selected: selected, locale: locale, dark: dark)
        guard presentation != next else { return }
        presentation = next
        rootView = AnyView(MarkdownLinkCapsule(attachment: attachment, selected: selected, open: { [weak self] in self?.openAction?() })
            .environment(\.locale, locale).environment(\.colorScheme, dark ? .dark : .light))
    }
}

extension MarkdownTextView {
    func updateLinkSurfaces() {
        guard showsLinkControls, let storage = textStorage, let layout = layoutManager, let container = textContainer else { return }
        var retained = Set<Int>()
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let attachment = value as? MarkdownLinkAttachment else { return }
            let index = range.location
            retained.insert(index)
            let host = linkSurfaces[index] ?? MarkdownLinkHost(rootView: AnyView(EmptyView()))
            if host.superview == nil { addSubview(host); linkSurfaces[index] = host }
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += textContainerOrigin.x; rect.origin.y += textContainerOrigin.y
            // The seat includes breathing room so adjacent TextKit lines cannot
            // touch the glass, including when a long title wraps inside it.
            let frame = CGRect(x: rect.minX, y: rect.minY + attachment.verticalInset,
                               width: attachment.size.width, height: attachment.size.height - 2 * attachment.verticalInset)
            if host.frame != frame { host.frame = frame }
            host.update(attachment, selected: NSIntersectionRange(selectedRange(), range).length > 0, locale: linkLocale,
                        dark: effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) { [weak self] in
                guard let self else { return }
                _ = self.delegate?.textView?(self, clickedOnLink: attachment.url, at: index)
            }
        }
        for index in linkSurfaces.keys where !retained.contains(index) {
            linkSurfaces.removeValue(forKey: index)?.removeFromSuperview()
        }
    }
}
