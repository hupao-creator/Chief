import ImageIO
import SwiftUI

/// A loading state for an entire workspace, sheet or reader viewport.
public struct NativeSurfaceLoading: View {
    @Environment(\.locale) private var locale
    private let caption: String?

    public init(_ caption: String? = nil) { self.caption = caption }

    public var body: some View {
        VStack(spacing: 6) {
            NativeLoadingMark()
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                artwork(TossPose())
            } else {
                KeyframeAnimator(initialValue: TossPose(), repeating: true) { pose in
                    artwork(pose)
                } keyframes: { _ in
                    KeyframeTrack(\.pitch) {
                        CubicKeyframe(-3, duration: 0.52, startVelocity: 0)
                        CubicKeyframe(5, duration: 0.26)
                        CubicKeyframe(0, duration: 0.66)
                        CubicKeyframe(0, duration: 0.36)
                        CubicKeyframe(-2.5, duration: 0.32)
                        CubicKeyframe(0.7, duration: 0.32)
                        CubicKeyframe(0, duration: 0.36, endVelocity: 0)
                    }
                    KeyframeTrack(\.flight) {
                        MoveKeyframe(0)
                        LinearKeyframe(0, duration: 0.58)
                        LinearKeyframe(1, duration: 1.49)
                        LinearKeyframe(1, duration: 0.73)
                    }
                }
            }
        }
        .aspectRatio(250.0 / 152.0, contentMode: .fit)
        .frame(maxWidth: 250, maxHeight: 152)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func artwork(_ pose: TossPose) -> some View {
        GeometryReader { geometry in
            // The sleeping skillet paints 610 of its 624 pixels at 195 pt.
            // Keep the same bowl centerline, including room for the handle.
            ZStack(alignment: .topLeading) {
                agent(TossArtwork.codex, at: CGPoint(x: 85, y: 83), width: 39, delay: 0,
                      rise: 28, spread: -8, tilt: -12, flight: pose.flight)
                agent(TossArtwork.claude, at: CGPoint(x: 125, y: 77), width: 52, delay: 0.06,
                      rise: 43, spread: -2, tilt: -20, flight: pose.flight)
                agent(TossArtwork.pi, at: CGPoint(x: 164, y: 80), width: 33, delay: 0.12,
                      rise: 24, spread: 6, tilt: -16, flight: pose.flight)
                Group {
                    TossArtwork.flick.frame(width: 10, height: 10).position(x: 85, y: 30)
                    TossArtwork.flick.frame(width: 8, height: 8).scaleEffect(x: -1, y: 1)
                        .position(x: 190, y: 51)
                }
                .opacity(pow(sin(.pi * pose.flight), 4))
                TossArtwork.pan.frame(width: 191, height: 77).position(x: 150.5, y: 100.5)
            }
            .frame(width: 250, height: 152)
            .rotationEffect(.degrees(pose.pitch), anchor: UnitPoint(x: 239.0 / 250, y: 71.0 / 152))
            .scaleEffect(geometry.size.width / 250, anchor: .topLeading)
        }
    }

    private func agent(_ image: Image, at center: CGPoint, width: CGFloat, delay: Double,
                       rise: CGFloat, spread: CGFloat, tilt: Double, flight: Double) -> some View {
        let t = min(1, max(0, (flight - delay) / 0.88))
        let lift = 4 * t * (1 - t)
        return image.scaledToFit().frame(width: width)
            .rotationEffect(.degrees(tilt * (1 - lift)))
            .position(x: center.x + lift * spread, y: center.y - lift * rise)
    }
}

private struct TossPose {
    var pitch = 0.0
    var flight = 0.0
}

private enum TossArtwork {
    static let pan = load("TossPan")
    static let codex = load("TossCodex")
    static let claude = load("TossClaude")
    static let pi = load("TossPi")
    static let flick = load("TossFlick")

    private static func load(_ name: String) -> Image {
        guard let url = NativeResources.bundle.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            preconditionFailure("Missing loading artwork: \(name)")
        }
        return Image(decorative: image, scale: 1).resizable().interpolation(.high)
    }
}
