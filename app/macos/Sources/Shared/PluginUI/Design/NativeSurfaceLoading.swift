import AppKit
import SwiftUI

/// A loading state for an entire workspace, sheet or reader viewport.
public struct NativeSurfaceLoading: View {
    @Environment(\.locale) private var locale
    private let caption: String?

    public init(_ caption: String? = nil) { self.caption = caption }

    public var body: some View {
        VStack(spacing: 6) {
            TossImage()
            if let caption {
                Text(caption).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption ?? (locale.language.languageCode?.identifier == "zh" ? "正在加载…" : "Loading…"))
    }
}

private struct TossImage: NSViewRepresentable {
    private static let size = CGSize(width: 96, height: 96)

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        Self.size
    }

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        // AppKit owns the GIF clock. Each mount gets its own playback state.
        let url = NativeResources.bundle.url(forResource: "ChiefStartupToss", withExtension: "gif")
        if let image = url.flatMap({ NSImage(contentsOf: $0) }) {
            // The bitmap is 2×. NSImage otherwise treats each GIF pixel as a point.
            image.size = Self.size
            view.image = image
        } else {
            view.image = NSApp.applicationIconImage
        }
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        let play = !context.environment.accessibilityReduceMotion
        if view.animates != play { view.animates = play }
    }

    static func dismantleNSView(_ view: NSImageView, coordinator: Void) {
        view.animates = false
        view.image = nil
    }
}
