import AppKit
import QuartzCore
import SwiftUI

struct RunningBadgeAnchor {
    let center: Anchor<CGPoint>
    let tint: Color
}

struct RunningBadgeAnchorKey: PreferenceKey {
    static var defaultValue: RunningBadgeAnchor? { nil }
    static func reduce(value: inout RunningBadgeAnchor?, nextValue: () -> RunningBadgeAnchor?) {
        value = nextValue() ?? value
    }
}

public extension View {
    /// Mount on the finished card shell so the bloom can straddle its border.
    func threadCardRunningEdge(reach: CGFloat = 88) -> some View {
        overlayPreferenceValue(RunningBadgeAnchorKey.self) { badge in
            if let badge, reach > 0 {
                GeometryReader { proxy in
                    let center = proxy[badge.center]
                    let inset = NativeGeometry.overviewCardRadius * (1 - sqrt(0.5))
                    // A wide card can put extension cells to the right of its badge.
                    // In that layout the nearest physical edge is directly above it.
                    let corner = proxy.size.width - center.x < reach
                    let focus = CGPoint(x: corner ? proxy.size.width - inset : center.x, y: corner ? inset : 0)
                    let origin = CGPoint(x: focus.x - reach, y: focus.y - reach)
                    RunningEdgeBand(card: CGRect(origin: .zero, size: proxy.size)
                        .offsetBy(dx: -origin.x, dy: -origin.y),
                        badge: CGPoint(x: center.x - origin.x, y: center.y - origin.y),
                        reach: reach, tint: badge.tint)
                        .frame(width: 2 * reach, height: 2 * reach)
                        .position(focus)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

private struct RunningEdgeBand: NSViewRepresentable {
    let card: CGRect
    let badge: CGPoint
    let reach: CGFloat
    let tint: Color
    @Environment(\.threadCardAnimationVisibility) private var visibility
    @Environment(\.threadCardCloudAnimationsEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var scale

    func makeNSView(context: Context) -> RunningEdgeSurface { RunningEdgeSurface(frame: .zero) }
    func updateNSView(_ view: RunningEdgeSurface, context: Context) {
        view.configure(.init(card: card, badge: badge, reach: reach, scale: scale),
            color: tint.resolve(in: context.environment).cgColor,
            active: enabled && !reduceMotion && scenePhase != .background && (visibility?.isVisible ?? true))
    }
}

private final class RunningEdgeSurface: RunningSweepSurface {
    @MainActor struct Geometry: Equatable {
        let card: CGRect
        let badge: CGPoint
        let reach: CGFloat
        let scale: CGFloat
        var side: CGFloat { 2 * reach }

        // Every point on a crest has the same x+y coordinate. Continue the
        // badge's linear travel beyond its last visible diagonal to clear the rim.
        func crest(_ time: Double) -> CGFloat {
            let diagonal = RunningSweep.diagonal(time)
            let outside = max(0, abs(diagonal) - 6) / 4
            let extra = 156 * outside * outside
            return (badge.x + badge.y + RunningSweep.pitch * diagonal + (diagonal < 0 ? -extra : extra)) / 2
        }

        func mask(holes: Bool) -> CGImage? {
            let pixels = Int(ceil(side * scale))
            guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.translateBy(x: 0, y: CGFloat(pixels))
            context.scaleBy(x: scale, y: -scale)
            let radius = NativeGeometry.overviewCardRadius
            func outline(_ inset: CGFloat) -> CGPath {
                Path(roundedRect: card.insetBy(dx: inset, dy: inset), cornerRadius: radius - inset,
                     style: .continuous).cgPath
            }
            let white = CGColor(gray: 1, alpha: 1)
            if holes {
                context.addPath(outline(3))
                context.addPath(outline(12))
                context.clip(using: .evenOdd)
                context.setFillColor(white)
                let pitch = RunningSweep.pitch
                let firstX = badge.x.truncatingRemainder(dividingBy: pitch)
                let firstY = badge.y.truncatingRemainder(dividingBy: pitch)
                for y in stride(from: firstY, through: side, by: pitch) {
                    for x in stride(from: firstX, through: side, by: pitch)
                    where y < card.minY + 15 || x > card.maxX - 15 {
                        context.fillEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    }
                }
            } else {
                let rim = outline(0.5)
                // Draw only the shadow of the broad stroke, then its sharp core.
                context.saveGState()
                let displacement = CGFloat(pixels) + card.width * scale + 16
                context.setShadow(offset: CGSize(width: displacement, height: 0), blur: 3.5 * scale,
                                  color: CGColor(gray: 1, alpha: 0.46))
                context.translateBy(x: -displacement / scale, y: 0)
                context.setStrokeColor(white)
                context.setLineWidth(5)
                context.addPath(rim)
                context.strokePath()
                context.restoreGState()
                context.setStrokeColor(white)
                context.setLineWidth(1.2)
                context.addPath(rim)
                context.strokePath()
            }
            return context.makeImage()
        }
    }

    private let rim = CALayer()
    private let wash = CALayer()
    private let rimBand = CAGradientLayer()
    private let holes = CALayer()
    private let holeBand = CAGradientLayer()
    private let fade = CAGradientLayer()
    private var geometry: Geometry?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(rim)
        rim.addSublayer(wash)
        rim.addSublayer(rimBand)
        layer?.addSublayer(holes)
        holes.addSublayer(holeBand)
        holes.opacity = 0.48
        fade.type = .radial
        fade.colors = [0.86, 0.53, 0.15, 0].map { CGColor(gray: 1, alpha: $0) }
        fade.locations = [0, 0.42, 0.78, 1]
        fade.startPoint = CGPoint(x: 0.5, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 1)
        layer?.mask = fade
    }
    required init?(coder: NSCoder) { nil }

    func configure(_ value: Geometry, color: CGColor, active: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if geometry != value {
            setSweeping(false)
            geometry = value
            let tile = CGRect(x: 0, y: 0, width: value.side, height: value.side)
            for plane in [fade, rim, wash, holes] { plane.frame = tile }
            for (plane, holes) in [(rim, false), (self.holes, true)] {
                let mask = CALayer()
                mask.frame = tile
                mask.contents = value.mask(holes: holes)
                plane.mask = mask
            }
            // The crest is a narrow strip perpendicular to its (+x,+y) travel.
            for (band, width) in [(rimBand, 8.0), (holeBand, 2.5)] {
                band.bounds = CGRect(x: 0, y: 0, width: sqrt(2) * width * RunningSweep.pitch,
                                     height: ceil(sqrt(2) * value.side) + 2)
                band.startPoint = CGPoint(x: 0, y: 0.5)
                band.endPoint = CGPoint(x: 1, y: 0.5)
                band.setAffineTransform(CGAffineTransform(rotationAngle: .pi / 4))
                let crest = value.crest(RunningSweep.still)
                band.position = CGPoint(x: crest, y: crest)
            }
            wash.opacity = Float(Self.washOpacity(RunningSweep.still))
        }
        if wash.backgroundColor != color {
            wash.backgroundColor = color
            let colors = [0.0, 0.4, 1, 0.4, 0].map { color.copy(alpha: $0) ?? color }
            rimBand.colors = colors
            holeBand.colors = colors
        }
        animates = active
        synchronize()
    }

    private static func washOpacity(_ time: Double) -> Double { 0.45 * pow(sin(.pi * RunningSweep.phase(time)), 2) }

    override func setSweeping(_ active: Bool) {
        guard let geometry, active != (wash.animation(forKey: "edge.wash") != nil) else { return }
        if active {
            let positions = RunningSweep.times.map { time in
                let crest = geometry.crest(time)
                return NSValue(point: CGPoint(x: crest, y: crest))
            }
            for band in [rimBand, holeBand] {
                RunningSweep.animate(band, "position", values: positions, key: "edge.crest")
            }
            RunningSweep.animate(wash, "opacity", values: RunningSweep.times.map(Self.washOpacity), key: "edge.wash")
        } else {
            for band in [rimBand, holeBand] { band.removeAnimation(forKey: "edge.crest") }
            wash.removeAnimation(forKey: "edge.wash")
        }
    }

    override func layout() { super.layout(); synchronize() }
}
