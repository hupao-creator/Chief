import AppKit
import SwiftUI

/// A loading state for an entire workspace, sheet or reader viewport.
public struct NativeSurfaceLoading: View {
    @Environment(\.locale) private var locale
    private let caption: String?

    public init(_ caption: String? = nil) { self.caption = caption }

    public var body: some View {
        VStack(spacing: 6) {
            NativeLoadingMark(size: 120)
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

struct NativeLoadingMark: View {
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TossImage(size: CGSize(width: size, height: size)).id(colorScheme)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

private struct TossImage: NSViewRepresentable {
    let size: CGSize

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        size
    }

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        // AppKit owns the GIF clock. Each mount gets its own playback state.
        let resource = context.environment.colorScheme == .dark ? "ChiefStartupTossDark" : "ChiefStartupToss"
        let url = NativeResources.bundle.url(forResource: resource, withExtension: "gif")
        if let image = url.flatMap({ NSImage(contentsOf: $0) }) {
            // The bitmap is 2×. NSImage otherwise treats each GIF pixel as a point.
            image.size = size
            view.image = image
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
