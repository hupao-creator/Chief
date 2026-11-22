import AppKit
import ChiefPluginUI
import Observation
import QuartzCore
import SwiftUI

struct NativeMokuHorizontalDestination: Equatable {
    let offset: CGFloat
    let verticalOffset: CGFloat
    let frame: CGRect?
    let revision: Int
    let viewport: CGSize
    let dragging: Bool
    let inactive: Bool
    let composer: UUID
    let reading: Bool
}

@MainActor final class NativeMokuHorizontalTravelHandle {
    weak var view: MokuHorizontalTravelView?
}

extension EnvironmentValues {
    @Entry var nativeMokuHorizontalTravel: NativeMokuHorizontalTravelHandle? = nil
}

/// Preserve the Dock's hosting root and update its observable content. Replacing
/// rootView during an outer update can settle the shell's layout while its face
/// is still animating in the previous coordinate space.
/// The compositor owns column travel and the compact reading-seat descent;
/// SwiftUI retains shell resizing, composer expansion and identity animation.
struct NativeMokuHorizontalTravel<Content: View>: NSViewRepresentable {
    @ViewBuilder var content: Content
    func makeNSView(context: Context) -> MokuHorizontalTravelView { MokuHorizontalTravelView() }
    func updateNSView(_ view: MokuHorizontalTravelView, context: Context) {
        view.updateContent(AnyView(content.environment(\.nativeMokuHorizontalTravel, view.handle)
            .environment(\.self, context.environment)), transaction: context.transaction)
    }
    static func dismantleNSView(_ view: MokuHorizontalTravelView, coordinator: ()) { view.retire() }
}

struct NativeMokuHorizontalTravelCommand: NSViewRepresentable {
    let destination: NativeMokuHorizontalDestination
    let hitRects: [CGRect]
    let onSettled: (NativeMokuHorizontalDestination) -> Void
    @Environment(\.nativeMokuHorizontalTravel) private var handle
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        handle?.view?.configure(destination: destination, hitRects: hitRects, onSettled: onSettled)
    }
}

@MainActor final class MokuHorizontalTravelView: NSView, CAAnimationDelegate {
    private let surface = MokuHorizontalSurfaceView()
    private var hosting: NSHostingView<MokuHorizontalContent>?
    private var contentState: MokuHorizontalContentState?
    private var destination: NativeMokuHorizontalDestination?
    let handle = NativeMokuHorizontalTravelHandle()
    private var hitRects: [CGRect] = []
    private var onSettled: ((NativeMokuHorizontalDestination) -> Void)?
    private var generation = 0
    private var activeAxes: [String: Int] = [:]
    private var travelling: Bool { !activeAxes.isEmpty }

    var presentationCorrection: CGPoint {
        let transform = surface.layer?.presentation()?.transform ?? CATransform3DIdentity
        return CGPoint(x: transform.m41, y: transform.m42)
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        surface.wantsLayer = true
        addSubview(surface)
        handle.view = self
    }
    required init?(coder: NSCoder) { nil }

    func updateContent(_ content: AnyView, transaction: Transaction) {
        if let contentState { withTransaction(transaction) { contentState.content = content } }
        else {
            let state = MokuHorizontalContentState(content: content)
            contentState = state
            let host = NSHostingView(rootView: MokuHorizontalContent(state: state))
            host.sizingOptions = []; host.safeAreaRegions = []; host.wantsLayer = true
            hosting = host; surface.addSubview(host)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let frame = bounds.offsetBy(dx: destination?.offset ?? 0, dy: 0)
        if surface.frame != frame { surface.frame = frame }
        if hosting?.frame != surface.bounds { hosting?.frame = surface.bounds }
        CATransaction.commit()
    }

    func configure(destination next: NativeMokuHorizontalDestination, hitRects: [CGRect],
                   onSettled: @escaping (NativeMokuHorizontalDestination) -> Void) {
        let previous = destination
        self.hitRects = hitRects; self.onSettled = onSettled; destination = next
        let layer = surface.layer!
        guard previous != next else { return }

        let immediate = previous == nil || next.inactive || next.dragging || previous?.viewport != next.viewport
        if !immediate, previous?.offset == next.offset,
           previous?.verticalOffset == next.verticalOffset, travelling { return }
        generation += 1
        let current = generation
        let visible = presentationCorrection
        let delta = CGPoint(x: visible.x + (previous?.offset ?? next.offset) - next.offset,
            y: visible.y + (previous?.verticalOffset ?? next.verticalOffset) - next.verticalOffset)
        // Commit the horizontal model seat with its presentation correction.
        // A separate SwiftUI offset can show the destination a frame early.
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let origin = CGPoint(x: bounds.minX + next.offset, y: bounds.minY)
        if surface.frame.origin != origin { surface.setFrameOrigin(origin) }
        let columnChanged = previous?.frame != next.frame
        // Route release can arrive before, during or after column travel. Use
        // the submitted X animation’s layer-local end time so the compositor
        // holds the current height through its last frame, even on a busy return.
        let xAxis = "transform.translation.x"
        let yAxis = "transform.translation.y"
        let now = layer.convertTime(CACurrentMediaTime(), from: nil)
        if immediate || previous?.offset != next.offset {
            let timing = columnChanged ? CAMediaTimingFunction(controlPoints: 0.30, 0.12, 0.44, 1)
                : next.reading && abs(delta.y) <= 0.01 ? NativeReadingPageTiming.emphasizedOpening
                : CAMediaTimingFunction(name: .easeInEaseOut)
            retarget(xAxis, delta: immediate ? 0 : delta.x, begin: now,
                     duration: columnChanged ? 0.52 : 0.42, timing: timing)
        }
        let returning = !next.reading && next.frame == nil
        if immediate || previous?.verticalOffset != next.verticalOffset
            || (returning && previous?.offset != next.offset && activeAxes[yAxis] != nil) {
            let xTravel = returning ? layer.animation(forKey: xAxis) : nil
            let begin = xTravel.map { max(now, $0.beginTime + $0.duration) } ?? now
            retarget(yAxis, delta: immediate ? 0 : delta.y, begin: begin, duration: 0.42,
                     timing: CAMediaTimingFunction(name: .easeInEaseOut))
        }
        if !travelling { deliverCompletion(generation: current) }
    }

    private func retarget(_ axis: String, delta: CGFloat, begin: CFTimeInterval, duration: TimeInterval, timing: CAMediaTimingFunction) {
        let layer = surface.layer!
        layer.removeAnimation(forKey: axis)
        guard abs(delta) > 0.01 else { activeAxes[axis] = nil; return }
        activeAxes[axis] = generation
        let animation = CABasicAnimation(keyPath: axis)
        animation.fromValue = delta; animation.toValue = 0
        animation.duration = duration; animation.timingFunction = timing
        animation.beginTime = begin
        animation.fillMode = .backwards
        animation.delegate = self; animation.setValue(generation, forKey: "generation")
        layer.add(animation, forKey: axis)
    }

    nonisolated func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard flag, let axis = (anim as? CABasicAnimation)?.keyPath,
              let token = anim.value(forKey: "generation") as? Int else { return }
        Task { @MainActor [weak self] in
            guard let self, activeAxes[axis] == token else { return }
            activeAxes[axis] = nil
            if !travelling { deliverCompletion(generation: generation) }
        }
    }

    private func deliverCompletion(generation expected: Int) {
        // Native delivery can arrive after a reversal, resize or route replacement.
        // Defer immediate receipts too: never publish scene state during updateNSView.
        Task { @MainActor [weak self] in
            guard let self, generation == expected, let destination else { return }
            onSettled?(destination)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if travelling {
            // The controls already have destination coordinates. Absorb presses
            // on both seats so a moving bar cannot click the reading backdrop.
            let visible = presentationCorrection
            return hitRects.contains(where: {
                $0.contains(local) || $0.offsetBy(dx: visible.x, dy: visible.y).contains(local)
            }) ? self : nil
        }
        guard hitRects.contains(where: { $0.contains(local) }),
              let hit = super.hitTest(point), hit !== self, hit !== surface else { return nil }
        return hit
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}

    func retire() {
        generation += 1; destination = nil; onSettled = nil; handle.view = nil
        activeAxes.removeAll()
        surface.layer?.removeAllAnimations()
        hosting?.removeFromSuperview(); hosting = nil; contentState = nil
    }
}

private final class MokuHorizontalSurfaceView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor @Observable private final class MokuHorizontalContentState {
    var content: AnyView
    init(content: AnyView) { self.content = content }
}

private struct MokuHorizontalContent: View {
    let state: MokuHorizontalContentState
    var body: some View {
        // The nested host occupies the complete logical workspace viewport.
        // Named SwiftUI spaces do not cross an NSHostingView boundary.
        state.content.coordinateSpace(name: "workspace")
    }
}
