import AppKit
import QuartzCore
import SwiftUI

struct NativeMokuBlinkingEyes: NSViewRepresentable {
    var expression: MokuExpression
    var focus: Double
    @Environment(\.scenePhase) private var scenePhase

    func makeNSView(context: Context) -> ComposerEyes { ComposerEyes() }
    func updateNSView(_ view: ComposerEyes, context: Context) {
        let pose = NativeMokuCapsuleEyes.resolved(expression: expression, focus: focus)
        view.configure(left: pose.left, right: pose.right,
                       color: Color.primary.resolve(in: context.environment).cgColor, active: scenePhase == .active)
    }
    static func dismantleNSView(_ view: ComposerEyes, coordinator: ()) { view.eyes.stop() }

    final class ComposerEyes: NSView {
        fileprivate let eyes = NativeMokuBlinkLayers()
        private var pose: (MokuEye, MokuEye)?
        private var ink: CGColor = .black
        private var active = false
        override var isFlipped: Bool { true }
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            if let layer { eyes.install(in: layer) }
            setAccessibilityElement(false)
        }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        func configure(left: MokuEye, right: MokuEye, color: CGColor, active: Bool) {
            pose = (left, right); ink = color; self.active = active
            synchronize()
        }
        override func layout() { super.layout(); synchronize() }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); synchronize() }
        private func synchronize() {
            guard let pose else { return }
            eyes.update(left: pose.0, right: pose.1, bounds: bounds, ink: ink, active: active && window != nil, first: nil)
        }
    }
}

enum NativeMokuCapsuleBlinkTiming {
    static let interval = 4.2
    static let duration = 0.32

    static func window(at date: Date, first: Date? = nil) -> Range<Date> {
        let origin = first ?? Date(timeIntervalSinceReferenceDate: 0)
        let cycle = floor(date.timeIntervalSince(origin) / interval)
        var start = origin.addingTimeInterval((first == nil ? cycle : max(0, cycle)) * interval)
        if date >= start.addingTimeInterval(duration) { start.addTimeInterval(interval) }
        return start..<start.addingTimeInterval(duration)
    }

    static func factor(progress: Double) -> Double { 1 - sin(progress * .pi) * 0.91 }
}

/// Each eye keeps its own centre and tilt. Rebuild the original rounded outline at
/// each lid height so that a closed eye retains its end caps.
@MainActor final class NativeMokuBlinkLayers {
    private let left = Eye()
    private let right = Eye()

    func install(in layer: CALayer) {
        layer.addSublayer(left.layer)
        layer.addSublayer(right.layer)
    }
    func stop() { left.stop(); right.stop() }

    func update(left poseL: MokuEye, right poseR: MokuEye, bounds: CGRect, ink: CGColor, active: Bool, first: Date?) {
        let now = Date.now
        let start = NativeMokuCapsuleBlinkTiming.window(at: now, first: first).lowerBound
        let beginTime = CACurrentMediaTime() + start.timeIntervalSince(now)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        left.update(poseL, bounds: bounds, ink: ink, active: active, first: first, beginTime: beginTime)
        right.update(poseR, bounds: bounds, ink: ink, active: active, first: first, beginTime: beginTime)
        CATransaction.commit()
    }

    private final class Eye {
        let layer = CAShapeLayer()
        private var lastPose: MokuEye?
        private var scheduled = false
        private var first: Date?
        private let key = "moku.blink"
        func stop() {
            if scheduled { layer.removeAnimation(forKey: key); scheduled = false }
        }
        func update(_ pose: MokuEye, bounds: CGRect, ink: CGColor, active: Bool, first: Date?, beginTime: Double) {
            let scale = NativeMokuCapsuleEyes.eyeScale
            // A centred local coordinate system keeps rotation independent of the lid.
            let size = CGSize(width: ceil(pose.w * scale) + 2, height: ceil(pose.h * scale) + 2)
            layer.bounds = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
            layer.position = CGPoint(x: bounds.midX + pose.x * scale, y: bounds.midY + pose.y * scale)
            layer.setAffineTransform(CGAffineTransform(rotationAngle: pose.rotation * .pi / 180))
            layer.fillColor = ink
            let geometryChanged = lastPose?.w != pose.w || lastPose?.h != pose.h || lastPose?.radius != pose.radius
            lastPose = pose
            if geometryChanged { layer.path = NativeMokuCapsuleEyes.contour(pose, blink: 1).cgPath }
            guard active else { stop(); return }
            guard geometryChanged || !scheduled || self.first != first else { return }
            self.first = first
            scheduled = true
            let timing = NativeMokuCapsuleBlinkTiming.self
            // 8ms segments across the original sine. The second half retraces
            // the same paths. The model's open eye fills the rest of the cycle.
            let half = 20
            let closing = (0...half).map { step in
                NativeMokuCapsuleEyes.contour(pose, blink: timing.factor(progress: Double(step) / Double(2 * half))).cgPath
            }
            let animation = CAKeyframeAnimation(keyPath: "path")
            animation.values = closing + closing.dropLast().reversed()
            animation.duration = timing.duration
            let cycle = CAAnimationGroup()
            cycle.animations = [animation]
            cycle.duration = timing.interval
            cycle.repeatCount = .infinity
            cycle.beginTime = layer.convertTime(beginTime, from: nil)
            layer.add(cycle, forKey: key)
        }
    }
}
