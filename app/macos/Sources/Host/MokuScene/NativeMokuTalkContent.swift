import AppKit
import CoreText
import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI

@MainActor enum NativeMokuTalkTypography {
    static let lineSpacing: CGFloat = 3
    static let verticalPadding: CGFloat = 19
    static let leading: CGFloat = 64
    static let trailing: CGFloat = 20
    // Reserve the eyes and mirror that inset to keep prose centered on the shell.
    static let centeredInset: CGFloat = 64
    static let lineHeight: CGFloat = 16
    static var maximumHeight: CGFloat { lineHeight * 8 + lineSpacing * 7 }
    static func height(_ text: String, width: CGFloat) -> CGFloat {
        // Match the rendered weight so Latin wrapping and the viewport agree.
        let font = NativePlatformFont.systemFont(ofSize: 13, weight: .semibold)
        var spacing = lineSpacing
        let paragraph = withUnsafePointer(to: &spacing) { pointer in
            var setting = CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: pointer)
            return CTParagraphStyleCreate(&setting, 1)
        }
        let value = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph])
        let framesetter = CTFramesetterCreateWithAttributedString(value)
        return ceil(CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: max(1, width), height: .greatestFiniteMagnitude), nil).height)
    }
    static func scrollbarGutter(for style: NSScroller.Style) -> CGFloat {
        style == .legacy ? NSScroller.scrollerWidth(for: .mini, scrollerStyle: style) : 0
    }
    static func capsuleHeight(_ text: String, width: CGFloat, leadingInset: CGFloat = leading, trailingInset: CGFloat? = nil,
                              maximumHeight: CGFloat = NativeMokuTalkTypography.maximumHeight,
                              scrollbarStyle: NSScroller.Style = NSScroller.preferredScrollerStyle) -> CGFloat {
        max(58, min(maximumHeight, height(text, width: width - leadingInset - (trailingInset ?? trailing) - scrollbarGutter(for: scrollbarStyle))) + verticalPadding * 2)
    }
}
/// Resolve only the public Threads named in this message. Their identifiers remain
/// in the destination even when a title or Harness is unavailable.
struct NativeMokuTalkLinks: View {
    let content: NativeMokuTalkText
    let workspace: NativeWorkspaceModel?
    let compact: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        var harnesses = [JSONText: AnyHarnessPlugin]()
        let runs: [(String, URL?)] = content.parts.map { part in
            switch part {
            case .text(let text):
                return (text, nil)
            case .link(let label, let url, let reference):
                let id = reference.thread.threadID
                let target = workspace?.catalog.thread(id)
                var title = label
                if let target, target.isOrdinaryAgent {
                    harnesses[id] = try? workspace?.plugins.harnesses.require(target.harnessID)
                    if title == nil, !target.title.string.isEmpty { title = target.title.string }
                }
                let fallback = locale.language.languageCode?.identifier == "zh" ? "执行记录" : "Execution"
                return (title ?? fallback, url)
            }
        }
        return NativeExecutionCapsuleText(runs: runs, harnesses: harnesses, compact: compact)
    }
}

struct NativeMokuTalkContent: View {
    let message: NativeMokuTalkMessage
    var scrollbarStyle: NSScroller.Style = NSScroller.preferredScrollerStyle
    var workspace: NativeWorkspaceModel?
    var linkedHeight: (CGFloat) -> Void = { _ in }
    var body: some View {
        GeometryReader { viewport in
            NativeScrollView {
                // Pin the text to its natural height before the viewport clips it.
                // Otherwise a shorter proposal can truncate wrapped transcript text
                // instead of letting the scroller reveal it.
                Group {
                    if message.content.hasLinks {
                        NativeMokuTalkLinks(content: message.content, workspace: workspace, compact: true)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { linkedHeight($0) }
                    } else {
                        Text(verbatim: message.text).font(.system(size: 13, weight: .semibold))
                            .lineSpacing(NativeMokuTalkTypography.lineSpacing).multilineTextAlignment(.center).textSelection(.enabled)
                    }
                }
                    .contentTransition(.opacity)
                    .mokuInk(value: message.id)
                    .fixedSize(horizontal: false, vertical: true)
                    // AppKit reserves a persistent gutter after SwiftUI has proposed
                    // the full scroll width. Constrain prose to the actual clip width;
                    // the flexible outer frame prevents it centering under that
                    // gutter without forcing the native viewport to grow for it.
                    .frame(maxWidth: max(1, viewport.size.width - NativeMokuTalkTypography.scrollbarGutter(for: scrollbarStyle)))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: viewport.size.width, height: viewport.size.height)
            .defaultScrollAnchor(.top)
            .defaultScrollAnchor(.center, for: .alignment)
            .id(message.id)
            .accessibilityIdentifier("moku-talk-content")
        }
    }
}
