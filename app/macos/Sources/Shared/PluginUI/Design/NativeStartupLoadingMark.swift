import AppKit
import SwiftUI

/// The startup surface owns the loading announcement and window drag region.
public struct NativeStartupLoadingMark: View {
    public init() {}

    public var body: some View {
        StartupTossImage()
            .frame(width: 96, height: 96)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct StartupTossImage: NSViewRepresentable {
    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        // AppKit owns the GIF clock. Each mount gets its own playback state.
        let url = NativeResources.bundle.url(forResource: "ChiefStartupToss", withExtension: "gif")
        view.image = url.flatMap { NSImage(contentsOf: $0) } ?? NSApp.applicationIconImage
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
