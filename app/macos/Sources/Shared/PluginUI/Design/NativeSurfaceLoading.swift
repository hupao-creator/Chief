import ImageIO
import SwiftUI

/// A loading state for an entire workspace, sheet or reader viewport.
public struct NativeSurfaceLoading: View {
    @Environment(\.locale) private var locale
    private let caption: String?
    private var startedAt: TimeInterval?

    public init(_ caption: String? = nil) { self.caption = caption }

    package init(startedAt: TimeInterval) {
        self.caption = nil
        self.startedAt = startedAt
    }

    public var body: some View {
        VStack(spacing: 6) {
            NativeLoadingMark(startedAt: startedAt)
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

    var startedAt: TimeInterval?
    @State private var mountedAt = CACurrentMediaTime()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { _ in
            let elapsed = CACurrentMediaTime() - (startedAt ?? mountedAt)
            NativeTossedSkillet(elapsed: reduceMotion ? nil : elapsed, sleep: startedAt == nil ? nil : 0)
        }
        .aspectRatio(250.0 / 152.0, contentMode: .fit)
        .frame(maxWidth: 250, maxHeight: 152)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

package struct NativeTossedSkillet: View {
    private let pose: NativeSkilletPose
    let motion: Double
    let tuck: Double
    let sleep: Double?

    package init(elapsed: TimeInterval?, motion: Double = 1, tuck: Double = 0, sleep: Double? = nil) {
        self.pose = elapsed.map { .toss(at: $0) } ?? .init()
        self.motion = motion
        self.tuck = tuck
        self.sleep = sleep
    }

    package var body: some View {
        GeometryReader { geometry in
            // The sleeping skillet paints 610 of its 624 pixels at 195 pt.
            // Keep the same bowl centerline, including room for the handle.
            ZStack(alignment: .topLeading) {
                if tuck < 1 {
                    awakeAgents
                        .offset(y: tuck * 48)
                        .mask(alignment: .top) { Rectangle().frame(height: sleep == nil ? 152 : 95) }
                }
                Group {
                    TossArtwork.flick.frame(width: 10, height: 10).position(x: 85, y: 30)
                    TossArtwork.flick.frame(width: 8, height: 8).scaleEffect(x: -1, y: 1)
                        .position(x: 190, y: 51)
                }
                .opacity(motion * pow(sin(.pi * pose.flight), 4))
                if let sleep {
                    workspacePan(sleep: sleep)
                        .frame(width: 195, height: 85)
                        .position(x: 150, y: 98.5)
                } else {
                    TossArtwork.pan.frame(width: 191, height: 77).position(x: 150.5, y: 100.5)
                }
            }
            .frame(width: 250, height: 152)
            .rotationEffect(.degrees(motion * pose.pitch), anchor: UnitPoint(x: 239.0 / 250, y: 71.0 / 152))
            .scaleEffect(geometry.size.width / 250, anchor: .topLeading)
        }
    }

    private var awakeAgents: some View {
        ZStack(alignment: .topLeading) {
            agent(TossArtwork.codex, at: CGPoint(x: 85, y: 83), width: 39, delay: 0,
                  rise: 28, spread: -8, tilt: -12, flight: pose.flight)
            agent(TossArtwork.claude, at: CGPoint(x: 125, y: 77), width: 52, delay: 0.06,
                  rise: 43, spread: -2, tilt: -20, flight: pose.flight)
            agent(TossArtwork.pi, at: CGPoint(x: 164, y: 80), width: 33, delay: 0.12,
                  rise: 24, spread: 6, tilt: -16, flight: pose.flight)
        }
        .frame(width: 250, height: 152)
    }

    // Both ends of workspace admission draw this very same pan. The rim
    // occludes the awake marks on landing, then the sleepy faces rise behind it.
    private func workspacePan(sleep: Double) -> some View {
        ZStack {
            if sleep > 0 {
                TossArtwork.idle.offset(y: 38 * (1 - sleep))
                    .mask(WorkspaceSkilletCut(bowl: false))
            }
            TossArtwork.idle.mask(WorkspaceSkilletCut(bowl: true))
        }
    }

    private func agent(_ image: Image, at center: CGPoint, width: CGFloat, delay: Double,
                       rise: CGFloat, spread: CGFloat, tilt: Double, flight: Double) -> some View {
        let t = min(1, max(0, (flight - delay) / 0.88))
        let lift = motion * 4 * t * (1 - t)
        return image.scaledToFit().frame(width: width)
            .rotationEffect(.degrees(tilt * (1 - lift)))
            .position(x: center.x + lift * spread, y: center.y - lift * rise)
    }
}

/// The rim in the 624 × 272 idle drawing divides the faces from the bowl.
/// The two complementary cuts reassemble the original pixels at rest.
private struct WorkspaceSkilletCut: Shape {
    let bowl: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 97))
        path.addLine(to: CGPoint(x: 22, y: 97))
        path.addQuadCurve(to: CGPoint(x: 237, y: 120), control: CGPoint(x: 121, y: 121))
        path.addQuadCurve(to: CGPoint(x: 443, y: 102), control: CGPoint(x: 355, y: 121))
        path.addLine(to: CGPoint(x: 452, y: 93))
        path.addLine(to: CGPoint(x: 452, y: 0))
        if bowl {
            path.addLine(to: CGPoint(x: 624, y: 0))
            path.addLine(to: CGPoint(x: 624, y: 272))
            path.addLine(to: CGPoint(x: 0, y: 272))
        } else {
            path.addLine(to: .zero)
        }
        path.closeSubpath()
        return path.applying(.init(scaleX: rect.width / 624, y: rect.height / 272))
    }
}

private struct NativeSkilletPose {
    @MainActor static func toss(at elapsed: TimeInterval) -> Self {
        timeline.value(time: max(0, elapsed).truncatingRemainder(dividingBy: timeline.duration))
    }

    @MainActor private static let timeline = KeyframeTimeline(initialValue: Self()) {
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

    var pitch = 0.0
    var flight = 0.0
}

private enum TossArtwork {
    static let idle = load("ChiefOverviewIdle")
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
