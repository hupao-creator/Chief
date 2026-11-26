import AppKit
import QuartzCore
import SwiftUI

/// The transparent pattern behind an active Overview filter's stationary glyph.
public struct NativeTagActivityPerforations: View {
    public init() {}
    public var body: some View {
        RunningThreadBadge(transparentFace: true, surfaceID: "OverviewTagActivityPerforations")
            .environment(\.threadCardProviderColor, NativePalette.overview.accent.swiftUI)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Only the perforations animate. The caller owns the glyph, status and hit target.
struct RunningThreadBadge: NSViewRepresentable {
    let transparentFace: Bool
    var surfaceID: String?
    @Environment(\.threadCardAnimationVisibility) private var visibility
    @Environment(\.threadCardCloudAnimationsEnabled) private var enabled
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> RunningThreadBadgeSurface {
        let surface = RunningThreadBadgeSurface(frame: .zero)
        if let surfaceID { surface.identifier = NSUserInterfaceItemIdentifier(surfaceID) }
        return surface
    }

    func updateNSView(_ view: RunningThreadBadgeSurface, context: Context) {
        let env = context.environment
        let graphite = Color(red: 0.13, green: 0.15, blue: 0.18)
        let ceramic = NativePalette.overview.surfaceStrong.swiftUI.mix(with: graphite,
            by: env.colorScheme == .dark ? 0.20 : 0.08)
        view.update(face: (transparentFace ? Color.clear : ceramic).resolve(in: env).cgColor,
            unlit: ceramic.mix(with: NativePalette.overview.ink.swiftUI, by: 0.18).resolve(in: env).cgColor,
            lit: env.threadCardProviderColor.resolve(in: env).cgColor,
            animates: !reduceMotion && enabled && scenePhase != .background && (visibility?.isVisible ?? true))
    }
}

enum RunningSweep {
    @MainActor static let pitch = (ThreadCardProviderStatus.diameter / 2 - 1) / 4
    static let cycle = 2.8
    static let still = 0.8
    static let times = (0...84).map { Double($0) / 30 }
    static func phase(_ time: Double) -> Double { min(1, time / 2.25) }
    static func diagonal(_ time: Double) -> Double { phase(time) * 20 - 10 }

    static func animate(_ layer: CALayer, _ property: String, values: [Any], key: String) {
        let animation = CAKeyframeAnimation(keyPath: property)
        animation.values = values
        animation.duration = cycle
        animation.repeatCount = .infinity
        let phase = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - phase
        layer.add(animation, forKey: key)
    }
}

class RunningSweepSurface: NSView {
    var animates = false
    isolated deinit { NotificationCenter.default.removeObserver(self) }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    override func viewDidHide() { super.viewDidHide(); synchronize() }
    override func viewDidUnhide() { super.viewDidUnhide(); synchronize() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged(_:)),
                name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        synchronize()
    }
    @objc private func visibilityChanged(_ notification: Notification) { synchronize() }

    func synchronize() {
        setSweeping(animates && !bounds.isEmpty && !isHiddenOrHasHiddenAncestor && window?.occlusionState.contains(.visible) == true)
    }
    func setSweeping(_ active: Bool) {}
}

final class RunningThreadBadgeSurface: RunningSweepSurface {
    private static let diameter = ThreadCardProviderStatus.diameter
    private static let key = "badge.sweep"
    // Holes on a diagonal have identical brightness. Cache their geometry and one cycle
    // of opacity samples so Overview panning never requires a SwiftUI or CPU frame clock.
    private static let bands: [(path: CGPath, samples: [Double], still: Float)] = {
        let radius = diameter / 2, pitch = RunningSweep.pitch
        return (-8...8).compactMap { diagonal in
            let path = CGMutablePath()
            for y in -4...4 {
                let x = diagonal - y
                let dx = CGFloat(x) * pitch, dy = CGFloat(y) * pitch
                guard abs(x) <= 4, hypot(dx, dy) < radius + 1 else { continue }
                path.addEllipse(in: CGRect(x: radius + dx - 1, y: radius + dy - 1, width: 2, height: 2))
            }
            guard !path.isEmpty else { return nil }
            func intensity(_ seconds: Double) -> Double {
                let sweep = RunningSweep.diagonal(seconds)
                let distance = (Double(diagonal) - sweep) / 1.25
                return exp(-distance * distance)
            }
            return (path, RunningSweep.times.map(intensity), Float(intensity(RunningSweep.still)))
        }
    }()

    private let disk = CALayer()
    private let unlit = CAShapeLayer()
    private let highlights = RunningThreadBadgeSurface.bands.map { _ in CAShapeLayer() }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let size = Self.diameter
        disk.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        disk.cornerRadius = size / 2
        disk.masksToBounds = true
        layer?.addSublayer(disk)
        let holes = CGMutablePath()
        disk.addSublayer(unlit)
        unlit.frame = disk.bounds
        for (band, highlight) in zip(Self.bands, highlights) {
            holes.addPath(band.path)
            highlight.frame = disk.bounds
            highlight.path = band.path
            highlight.opacity = band.still
            disk.addSublayer(highlight)
        }
        unlit.path = holes
    }
    required init?(coder: NSCoder) { nil }
    func update(face: CGColor, unlit: CGColor, lit: CGColor, animates: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        disk.backgroundColor = face
        self.unlit.fillColor = unlit
        for highlight in highlights { highlight.fillColor = lit }
        CATransaction.commit()
        self.animates = animates
        synchronize()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scale = min(bounds.width, bounds.height) / Self.diameter
        disk.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        disk.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
        synchronize()
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 1
        unlit.contentsScale = scale
        for highlight in highlights { highlight.contentsScale = scale }
    }
    override func setSweeping(_ active: Bool) {
        guard active != (highlights.first?.animation(forKey: Self.key) != nil) else { return }
        for (band, highlight) in zip(Self.bands, highlights) {
            if active {
                RunningSweep.animate(highlight, "opacity", values: band.samples, key: Self.key)
            } else {
                highlight.removeAnimation(forKey: Self.key)
            }
        }
    }
}
