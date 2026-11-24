import AppKit
import SwiftUI

package struct NativeOverviewIdleMark: NSViewRepresentable {
    private static let size = CGSize(width: 156, height: 68)
    let label: String?
    let hint: String?
    let identifier: String

    package init(label: String? = nil, hint: String? = nil, identifier: String = "overview.idle") {
        self.label = label
        self.hint = hint
        self.identifier = identifier
    }

    package func makeNSView(context: Context) -> NSImageView {
        let view = IdleImageView()
        guard let url = NativeResources.bundle.url(forResource: "ChiefOverviewIdle", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing Chief Overview idle illustration")
        }
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityElement(label != nil)
        view.setAccessibilityRole(.image)
        view.setAccessibilityIdentifier(identifier)
        return view
    }

    package func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        let size = Self.size
        let scale = min(1, (proposal.width ?? size.width) / size.width, (proposal.height ?? size.height) / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    package func updateNSView(_ view: NSImageView, context: Context) {
        view.setAccessibilityLabel(label)
        view.setAccessibilityHelp(hint)
    }
}

private final class IdleImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
