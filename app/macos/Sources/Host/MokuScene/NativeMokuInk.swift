import AppKit
import QuartzCore
import SwiftUI

/// A fixed-layout live seat. Its caller owns geometry, input and accessibility.
/// Replacing the ink transaction never replaces the SwiftUI or AppKit controls inside.
struct NativeMokuInk<Content: View>: NSViewRepresentable {
    let visible: Bool
    let curve: UnitCurve
    let duration: TimeInterval
    var passive = false
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> NativeMokuInkView { NativeMokuInkView() }
    func updateNSView(_ view: NativeMokuInkView, context: Context) {
        view.passive = passive
        view.update(content: AnyView(content.environment(\.self, context.environment)),
                    transaction: context.transaction, visible: visible, curve: curve, duration: duration)
    }
}

@Observable @MainActor private final class MokuInkContent {
    var view: AnyView
    init(_ view: AnyView) { self.view = view }
}

private struct MokuInkRoot: View {
    let content: MokuInkContent
    var body: some View { content.view }
}

final class NativeMokuInkView: NSView {
    private let carrier = NSView()
    private var root: MokuInkContent?
    private var opacity = NativeMokuInkTrack()
    var passive = false
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { passive ? nil : super.hitTest(point) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        carrier.wantsLayer = true
        carrier.frame = bounds
        carrier.autoresizingMask = [.width, .height]
        addSubview(carrier)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }

    func update(content: AnyView, transaction: Transaction, visible: Bool, curve: UnitCurve, duration: Double) {
        if let root { withTransaction(transaction) { root.view = content } }
        else {
            let root = MokuInkContent(content)
            self.root = root
            let host = NSHostingView(rootView: MokuInkRoot(content: root))
            host.sizingOptions = []
            host.safeAreaRegions = []
            host.frame = carrier.bounds
            host.autoresizingMask = [.width, .height]
            carrier.addSubview(host)
        }
        if let layer = carrier.layer {
            opacity.set(visible, on: layer, at: layer.convertTime(CACurrentMediaTime(), from: nil),
                        curve: curve, duration: duration, animated: !transaction.disablesAnimations)
        }
    }
}

/// Local layer time allows several independently hosted controls to share the same submission.
struct NativeMokuInkTrack {
    private struct Leg {
        let start: Double
        let duration: Double
        let target: Double
        let curve: UnitCurve

        func value(at time: Double, from value: Double) -> Double {
            let fraction = min(1, max(0, (time - start) / duration))
            return value + (target - value) * curve.value(at: fraction)
        }
    }

    private var visible: Bool?
    private var legs: [Leg] = []
    private var base = 0.0

    @MainActor mutating func set(_ visible: Bool, on layer: CALayer, at start: Double,
                                 curve: UnitCurve, duration: Double, animated: Bool) {
        guard self.visible != visible else { return }
        let mounted = self.visible != nil
        let previousTarget = self.visible == true ? 1.0 : 0.0
        self.visible = visible
        let target = visible ? 1.0 : 0.0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        layer.opacity = Float(target)
        let playing = layer.animation(forKey: "chief.ink") != nil
        layer.removeAnimation(forKey: "chief.ink")
        guard mounted, animated, duration > 0 else {
            base = target
            legs.removeAll()
            return
        }

        // At a reversal, SwiftUI interpolates from the previous trajectory as it
        // continues to run. Freezing that trajectory at its current value drops
        // the outgoing slope, including the brief continued reveal on hover exit.
        if !playing {
            base = previousTarget
            legs.removeAll()
        } else if let settled = legs.lastIndex(where: { $0.start + $0.duration <= start }) {
            base = legs[settled].target
            legs.removeFirst(settled + 1)
        }
        legs.append(Leg(start: start, duration: duration, target: target, curve: curve))
        // Once this leg reaches its target it replaces every older contribution.
        // Its own duration also bounds preparation when a parent changes clocks.
        let steps = max(1, Int((duration * 600).rounded()))
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        // UnitCurve is the source curve. The standard CA timing function picks
        // different intermediate values even when its Bezier controls agree.
        fade.values = (0...steps).map { index in
            let time = start + duration * Double(index) / Double(steps)
            return legs.reduce(base) { $1.value(at: time, from: $0) }
        }
        fade.duration = duration
        fade.beginTime = start
        fade.fillMode = .backwards
        fade.calculationMode = .linear
        layer.add(fade, forKey: "chief.ink")
    }
}
