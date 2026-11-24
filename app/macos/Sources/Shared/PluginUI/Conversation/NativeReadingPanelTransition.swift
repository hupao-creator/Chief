import AppKit
import ChiefCore
import QuartzCore
import SwiftUI

struct NativeReadingPanelTransition: Equatable {
    let generation: Int
    let closing: Bool
    let duration: TimeInterval
    let emphasized: Bool
    var thread = false
    var report = false
}

/// The compositor owns panel travel while Agent readers prepare invisibly.
struct NativeReadingPanelViewport<Content: View>: NSViewRepresentable {
    let target: CGRect
    let source: CGRect?
    let collectionPanel: Bool
    let open: Bool
    let transition: NativeReadingPanelTransition?
    let contentReady: Bool
    var readerPreloading = false
    var identity: NativeThreadIdentityVisit? = nil
    var onOpeningStarted: ((Int) -> Void)? = nil
    let onCompletion: (Int, Bool) -> Void
    let content: Content

    func makeNSView(context: Context) -> ReadingPanelView {
        let readingMember = context.environment.nativeCollectionPanel?.readingMember != nil
        return ReadingPanelView(collectionPanel: collectionPanel, readingMember: readingMember)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ReadingPanelView, context: Context) -> CGSize? {
        // The workspace owns this viewport; fitting its hosted document would
        // traverse every native text view without changing the panel's size.
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite else { return nil }
        return CGSize(width: width, height: height)
    }

    func updateNSView(_ view: ReadingPanelView, context: Context) {
        var environment = context.environment
        environment.nativeThreadPreparing = !contentReady && identity != nil
        environment.nativeThreadReaderPreloading = readerPreloading
        environment.nativeReadingInteractionActive = environment.nativeReadingInteractionActive && contentReady
        view.configure(target: target, source: source, open: open, transition: transition,
            contentReady: contentReady, identity: identity,
            environment: environment,
            paperColor: NativePalette.thread.canvas.swiftUI.resolve(in: context.environment).cgColor,
            content: AnyView(content.environment(\.self, environment)),
            onOpeningStarted: onOpeningStarted,
            onCompletion: onCompletion)
    }

    static func dismantleNSView(_ view: ReadingPanelView, coordinator: ()) { view.retire() }
}

@MainActor
final class ReadingPanelView: NSView, CAAnimationDelegate {
    private let surface = ReadingPanelSurfaceView()
    private let aperture = CAShapeLayer()
    private let paper = CALayer()
    private let collectionPanel: Bool
    private let windowContentSpace: NSView?
    private var hosting: NSHostingView<AnyView>?
    private var target = CGRect.zero
    private var source = CGRect.zero
    private var command: NativeReadingPanelTransition?
    private var startedGeneration: Int?
    private var completedGeneration: Int?
    private var onCompletion: ((Int, Bool) -> Void)?
    private var onOpeningStarted: ((Int) -> Void)?
    private var acceptsInput = false
    private var identity: NativeThreadIdentityVisit?
    private var flight: NativeThreadIdentityFlight?
    private var preparation: Task<Void, Never>?
    private var prepared = false
    private var environment = EnvironmentValues()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    init(collectionPanel: Bool, readingMember: Bool) {
        self.collectionPanel = collectionPanel
        windowContentSpace = collectionPanel || readingMember ? ReadingPanelSurfaceView() : nil
        super.init(frame: .zero)
        wantsLayer = true
        surface.wantsLayer = true
        // AppKit backs flipped views with an origin anchor. Keep that native
        // coordinate system when animating layer positions directly.
        surface.layer!.anchorPoint = .zero
        addSubview(surface)
        surface.layer!.addSublayer(paper)
        if collectionPanel {
            paper.cornerRadius = 22
            paper.cornerCurve = .continuous
        }
        if let windowContentSpace { surface.addSubview(windowContentSpace) }
        surface.layer!.mask = aperture
    }

    required init?(coder: NSCoder) { nil }

    func configure(target: CGRect, source: CGRect?, open: Bool,
                   transition: NativeReadingPanelTransition?, contentReady: Bool, identity: NativeThreadIdentityVisit? = nil,
                   environment: EnvironmentValues,
                   paperColor: CGColor, content: AnyView,
                   onOpeningStarted: ((Int) -> Void)? = nil, onCompletion: @escaping (Int, Bool) -> Void) {
        self.environment = environment
        if self.identity !== identity {
            preparation?.cancel(); preparation = nil; prepared = false
            flight?.retire(); flight = nil; self.identity = identity
            identity?.onOpeningTargetsChange = { [weak self] in self?.prepareOpening() }
        }
        if identity?.pending != true { flight?.retire(); flight = nil }
        let resized = self.target != target
        self.target = target
        self.source = source ?? target.insetBy(dx: min(24, target.width / 4), dy: min(24, target.height / 4))
        self.onCompletion = onCompletion
        self.onOpeningStarted = onOpeningStarted
        command = transition
        acceptsInput = open && transition == nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Reader updates during a close must not restore the layer's model
        // position to the open frame; removing the animation would snap back.
        if resized {
            let size = CGSize(width: target.width + 76, height: target.height)
            surface.frame = CGRect(origin: target.origin, size: size)
        }
        paper.frame = CGRect(origin: .zero, size: target.size)
        // The collection grid shares the workspace window's backdrop.
        paper.backgroundColor = collectionPanel && !environment.accessibilityReduceTransparency ? nil : paperColor
        if contentReady || identity?.pending == true {
            windowContentSpace?.frame = surface.bounds
            if let hosting { hosting.rootView = content }
            else {
                let view = NSHostingView(rootView: content)
                // The compositor supplies the host's frame, independently of
                // the document's minimum, ideal and maximum content sizes.
                view.sizingOptions = []
                view.wantsLayer = true
                hosting = view
                // The lightweight identity ink remains above the newly admitted
                // opaque reader until its measured heading takes ownership.
                if let windowContentSpace { windowContentSpace.addSubview(view) }
                else { surface.addSubview(view, positioned: .below, relativeTo: nil) }
            }
            hosting?.frame = windowContentSpace?.bounds ?? surface.bounds
        }
        if transition?.closing != true {
            hosting?.layer?.opacity = contentReady ? 1 : 0
            hosting?.layer?.transform = CATransform3DIdentity
        }
        if transition?.closing == false, identity?.pending == true, startedGeneration == nil {
            surface.layer?.opacity = 0
        }
        CATransaction.commit()
        if let transition {
            if resized && startedGeneration == transition.generation {
                // The stack will settle resize in the same update; do not retime
                // the old motion against a different viewport in the meantime.
                return
            }
            startIfReady()
        } else {
            startedGeneration = nil
            completedGeneration = nil
            surface.layer?.removeAllAnimations()
            aperture.removeAllAnimations()
            hosting?.layer?.removeAllAnimations()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            surface.layer?.opacity = 1
            surface.layer?.mask = open ? nil : aperture
            aperture.path = path(self.source.size)
            surface.layer?.position = open ? target.origin : self.source.origin
            paper.isHidden = open && contentReady && !collectionPanel
            CATransaction.commit()
            if open && contentReady { flight?.completeOpening() }
        }
    }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); startIfReady() }
    override func layout() { super.layout(); startIfReady() }

    private func prepareOpening() {
        guard startedGeneration == nil, preparation == nil, identity?.openingTarget["title"] != nil,
              identity?.openingTarget["emoji"] != nil else { return }
        preparation = Task { @MainActor [weak self] in
            // Coalesce anchor publication, then resolve the current native
            // layout before freezeOpeningTargets reads the actual views. A
            // trailing debounce can postpone travel on every layout update.
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            defer { preparation = nil }
            hosting?.layoutSubtreeIfNeeded()
            prepared = true; startIfReady()
        }
    }

    private func startIfReady() {
        guard window != nil, bounds.width > 0, bounds.height > 0,
              let command, startedGeneration != command.generation, let layer = surface.layer else { return }
        // Report's main and auxiliary surfaces return independently. The native
        // carrier stays fixed and only owns generation-fenced completion; applying
        // its normal full-workspace aperture would widen/crop the split reader.
        if command.closing && command.report {
            flight?.retire(); flight = nil
            startedGeneration = command.generation
            completedGeneration = nil
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.removeAllAnimations(); aperture.removeAllAnimations()
            layer.mask = nil
            layer.position = target.origin
            paper.isHidden = true
            CATransaction.commit()
            let completion = CABasicAnimation(keyPath: "opacity")
            completion.fromValue = layer.opacity; completion.toValue = layer.opacity
            completion.duration = command.duration
            completion.setValue(command.generation, forKey: "generation")
            completion.delegate = self
            layer.add(completion, forKey: "reading.report.return")
            return
        }
        if command.closing { flight?.retire(); flight = nil }
        else if flight == nil, let identity, identity.pending {
            guard prepared else { return }
            identity.freezeOpeningTargets()
            flight = NativeThreadIdentityFlight(visit: identity, surface: surface, source: source,
                environment: environment,
                duration: command.duration, timing: command.emphasized ? NativeReadingPageTiming.emphasizedOpening
                    : CAMediaTimingFunction(controlPoints: 0.42, 0, 0.58, 1))
        }
        let wasMoving = startedGeneration != nil
        let fromPosition = wasMoving ? layer.presentation()?.position ?? layer.position : (command.closing ? target.origin : source.origin)
        let fromPath = wasMoving ? aperture.presentation()?.path ?? aperture.path : path(command.closing ? target.size : source.size)
        let fromOpacity = hosting?.layer?.presentation()?.opacity ?? 1
        startedGeneration = command.generation
        completedGeneration = nil
        let destination = command.closing ? source : target
        let timing = command.emphasized ? NativeReadingPageTiming.emphasizedOpening
            : command.thread ? CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1)
                : CAMediaTimingFunction(controlPoints: 0.42, 0, 0.58, 1)
        if command.closing && command.thread, let content = hosting?.layer {
            NativeReadingPanelReturn.animate(surface: layer, content: content, aperture: aperture, paper: paper,
                fromPosition: fromPosition, fromPath: fromPath, source: source,
                readerWidth: target.width, duration: command.duration,
                generation: command.generation, delegate: self)
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        aperture.removeAllAnimations()
        layer.mask = aperture
        paper.isHidden = false
        if !command.closing { layer.opacity = 1 }
        layer.position = destination.origin
        aperture.path = path(destination.size)
        CATransaction.commit()

        let travel = CABasicAnimation(keyPath: "position")
        travel.fromValue = NSValue(point: fromPosition)
        travel.toValue = NSValue(point: layer.position)
        travel.duration = command.duration
        travel.timingFunction = timing
        travel.setValue(command.generation, forKey: "generation")
        travel.delegate = self
        let clip = CABasicAnimation(keyPath: "path")
        clip.fromValue = fromPath
        clip.toValue = aperture.path
        clip.duration = command.duration
        clip.timingFunction = timing
        if command.closing, let contentLayer = hosting?.layer {
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [fromOpacity, fromOpacity, 0, 0]
            fade.keyTimes = [0, 0.2, 0.8, 1]
            fade.duration = command.duration
            fade.timingFunction = timing
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            contentLayer.opacity = 0
            CATransaction.commit()
            contentLayer.add(fade, forKey: "reading.fade")
        }
        layer.add(travel, forKey: "reading.travel")
        aperture.add(clip, forKey: "reading.aperture")
    }

    // Start delivery follows native animation submission. Preparing a hidden
    // reader here overlaps travel without doing heavy work in the submission
    // update or advancing text entrance/secondary surfaces before arrival.
    nonisolated func animationDidStart(_ anim: CAAnimation) {
        guard let generation = anim.value(forKey: "generation") as? Int else { return }
        Task { @MainActor [weak self] in
            guard let self, let command, command.generation == generation,
                  startedGeneration == generation, completedGeneration != generation,
                  !command.closing else { return }
            if command.thread { onOpeningStarted?(generation) }
        }
    }

    // Delegate delivery may be delayed by unrelated main-thread work. Only this
    // generation may admit content or close the route; the layers already finish
    // on the compositor even while that delivery is waiting.
    nonisolated func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard flag, let generation = anim.value(forKey: "generation") as? Int else { return }
        Task { @MainActor [weak self] in
            guard let self, let command, command.generation == generation,
                  completedGeneration != generation else { return }
            completedGeneration = generation
            onCompletion?(generation, command.closing)
        }
    }

    private func path(_ size: CGSize) -> CGPath {
        CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: 22, cornerHeight: 22, transform: nil)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard acceptsInput else { return nil }
        if collectionPanel, !target.contains(convert(point, from: superview)) { return nil }
        guard let hit = super.hitTest(point), hit !== self, hit !== surface, hit !== windowContentSpace else { return nil }
        return hit
    }

    override func accessibilityChildren() -> [Any]? {
        acceptsInput ? super.accessibilityChildren() : []
    }

    func retire() {
        preparation?.cancel(); preparation = nil
        command = nil
        flight?.retire(); flight = nil; identity = nil
        onCompletion = nil
        surface.layer?.removeAllAnimations()
        aperture.removeAllAnimations()
        hosting?.layer?.removeAllAnimations()
        hosting?.removeFromSuperview()
        hosting = nil
    }
}

private final class ReadingPanelSurfaceView: NSView {
    override var isFlipped: Bool { true }
}
