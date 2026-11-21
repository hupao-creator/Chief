import AppKit
import QuartzCore
import SwiftUI

/// The overlay supplies the text mask. This view owns only the moving highlight.
struct ThreadExecutionLoadingSweep: NSViewRepresentable {
    func makeNSView(context: Context) -> SweepView { SweepView() }
    func updateNSView(_ view: SweepView, context: Context) {
        view.setInk(NativePalette.thread.inkStrong.swiftUI.resolve(in: context.environment).cgColor)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SweepView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
    static func dismantleNSView(_ view: SweepView, coordinator: ()) { view.stop() }

    final class SweepView: NSView {
        private let gradient = CAGradientLayer()
        private let width: CGFloat = 64
        private var animatedSize = CGSize.zero
        private var startedAt: CFTimeInterval?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)
            gradient.locations = [0, 0.35, 0.65, 1]
            layer?.addSublayer(gradient)
        }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func isAccessibilityElement() -> Bool { false }

        func setInk(_ color: CGColor) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let clear = color.copy(alpha: 0) ?? .clear
            gradient.colors = [clear, color, color, clear]
            CATransaction.commit()
        }

        override func layout() { super.layout(); synchronize() }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); synchronize() }

        func stop() {
            gradient.removeAnimation(forKey: "execution.sweep")
            animatedSize = .zero
            startedAt = nil
        }

        private func synchronize() {
            guard window != nil, bounds.width > 0, bounds.height > 0 else { stop(); return }
            guard bounds.size != animatedSize else { return }
            animatedSize = bounds.size
            let distance = bounds.width + width
            let travel = max(0.8, distance / 180)
            let cycle = travel + 0.25
            let end = bounds.maxX + width / 2
            let animation = CAKeyframeAnimation(keyPath: "position.x")
            animation.values = [bounds.minX - width / 2, end, end]
            animation.keyTimes = [0, NSNumber(value: travel / cycle), 1]
            animation.duration = cycle
            animation.repeatCount = .infinity
            // A live count or width change retimes this pass from its original admission.
            let start = startedAt ?? CACurrentMediaTime()
            startedAt = start
            animation.beginTime = gradient.convertTime(start, from: nil)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            gradient.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            gradient.position = CGPoint(x: end, y: bounds.midY)
            gradient.add(animation, forKey: "execution.sweep")
            CATransaction.commit()
        }
    }
}
