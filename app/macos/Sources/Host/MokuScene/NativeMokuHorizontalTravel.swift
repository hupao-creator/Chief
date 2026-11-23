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
    // SwiftUI installs the destination reading inset at route release. Keep
    // the old screen y in the native seat until the column trip has arrived.
    private var heldLift: CGFloat = 0
    private var travelling: Bool { !activeAxes.isEmpty || heldLift != 0 }

    var presentationCorrection: CGPoint {
        let transform = surface.layer?.presentation()?.transform ?? CATransform3DIdentity
        return CGPoint(x: transform.m41, y: heldLift + transform.m42)
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
        placeSurface()
        if hosting?.frame != surface.bounds { hosting?.frame = surface.bounds }
        CATransaction.commit()
    }

    private func placeSurface() {
        let frame = bounds.offsetBy(dx: destination?.offset ?? 0, dy: heldLift)
        if surface.frame != frame { surface.frame = frame }
    }

    func configure(destination next: NativeMokuHorizontalDestination, hitRects: [CGRect],
                   onSettled: @escaping (NativeMokuHorizontalDestination) -> Void) {
        let previous = destination
        self.hitRects = hitRects; self.onSettled = onSettled; destination = next
        let visible = presentationCorrection
        guard previous != next else { return }

        let immediate = previous == nil || next.inactive || next.dragging || previous?.viewport != next.viewport
        if !immediate, previous?.offset == next.offset,
           previous?.verticalOffset == next.verticalOffset, previous?.frame == next.frame,
           previous?.reading == next.reading, travelling { return }
        generation += 1
        let current = generation
        let delta = CGPoint(x: visible.x + (previous?.offset ?? next.offset) - next.offset,
            y: visible.y + (previous?.verticalOffset ?? next.verticalOffset) - next.verticalOffset)
        // Commit the horizontal model seat with its presentation correction.
        // A separate SwiftUI offset can show the destination a frame early.
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let columnChanged = previous?.frame != next.frame
        let duration: TimeInterval = columnChanged ? 0.38 : 0.42
        let timing = columnChanged
            ? CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            : abs(delta.y) > 0.01 ? CAMediaTimingFunction(name: .easeInEaseOut)
            : next.reading ? NativeReadingPageTiming.emphasizedOpening : CAMediaTimingFunction(name: .easeInEaseOut)

        if immediate || previous?.offset != next.offset {
            retarget("transform.translation.x", delta: immediate ? 0 : delta.x,
                duration: columnChanged ? 0.52 : duration,
                timing: columnChanged ? CAMediaTimingFunction(controlPoints: 0.30, 0.12, 0.44, 1) : timing)
        }
        let holdHeight = !immediate && !next.reading && (next.frame != nil || activeAxes["transform.translation.x"] != nil)
        if immediate || previous?.verticalOffset != next.verticalOffset || heldLift != 0 || holdHeight {
            heldLift = holdHeight && abs(delta.y) > 0.01 ? delta.y : 0
            retarget("transform.translation.y", delta: immediate || holdHeight ? 0 : delta.y, duration: duration, timing: timing)
        }
        placeSurface()
        if !travelling { deliverCompletion(generation: current) }
    }

    private func retarget(_ axis: String, delta: CGFloat, duration: TimeInterval, timing: CAMediaTimingFunction) {
        let layer = surface.layer!
        layer.removeAnimation(forKey: axis)
        guard abs(delta) > 0.01 else { activeAxes[axis] = nil; return }
        activeAxes[axis] = generation
        let animation = CABasicAnimation(keyPath: axis)
        animation.fromValue = delta; animation.toValue = 0
        animation.duration = duration; animation.timingFunction = timing
        // Let Core Animation start the trip when this transaction commits.
        // Preparing the Overview can take time after this layer is configured.
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
            if axis == "transform.translation.x", heldLift != 0, destination?.frame == nil {
                let lift = heldLift
                CATransaction.begin(); CATransaction.setDisableActions(true)
                heldLift = 0
                placeSurface()
                retarget("transform.translation.y", delta: lift, duration: NativeReadingPageTiming.duration,
                    timing: CAMediaTimingFunction(name: .easeInEaseOut))
                CATransaction.commit()
            }
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
        heldLift = 0
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
