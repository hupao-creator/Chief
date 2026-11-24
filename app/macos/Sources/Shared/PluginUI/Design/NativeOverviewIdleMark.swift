import AppKit
import SwiftUI

package struct NativeOverviewIdleMark: NSViewRepresentable {
    let label: String
    let hint: String

    package init(label: String, hint: String) {
        self.label = label
        self.hint = hint
    }

    package func makeNSView(context: Context) -> NSImageView {
        let view = IdleImageView()
        guard let url = NativeResources.bundle.url(forResource: "ChiefOverviewIdle", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing Chief Overview idle illustration")
        }
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        view.setAccessibilityIdentifier("overview.idle")
        return view
    }

    package func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        let scale = min(1, (proposal.width ?? 312) / 312, (proposal.height ?? 136) / 136)
        return CGSize(width: 312 * scale, height: 136 * scale)
    }

    package func updateNSView(_ view: NSImageView, context: Context) {
        view.setAccessibilityLabel(label)
        view.setAccessibilityHelp(hint)
    }
}

private final class IdleImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
