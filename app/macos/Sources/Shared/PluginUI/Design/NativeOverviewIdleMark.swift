import AppKit
import SwiftUI

package struct NativeOverviewIdleMark: NSViewRepresentable {
    private let size: CGSize
    let identifier: String

    package init(identifier: String, scale: CGFloat = 1) {
        size = CGSize(width: 156 * scale, height: 68 * scale)
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
        view.setAccessibilityElement(false)
        view.setAccessibilityIdentifier(identifier)
        return view
    }

    package func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        let scale = min(1, (proposal.width ?? size.width) / size.width, (proposal.height ?? size.height) / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    package func updateNSView(_ view: NSImageView, context: Context) {
        view.setAccessibilityIdentifier(identifier)
    }
}

private final class IdleImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
