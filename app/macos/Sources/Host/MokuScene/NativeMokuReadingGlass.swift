import AppKit
import ChiefPluginUI
import SwiftUI

/// The preview can supply a held-frame version of the same opening curve to
/// both renderers. The live editor and its glass share one destination.
struct NativeMokuReadingOpening {
    let animation: Animation
    let track: (_ from: CGFloat, _ to: CGFloat) -> CAPropertyAnimation
}

struct NativeMokuReadingMorph {
    let opening: NativeMokuReadingOpening?
    let folding: Bool

    func track(_ key: String, from: CGFloat, to: CGFloat, columnChanged: Bool) -> CAPropertyAnimation {
        let track: CAPropertyAnimation
        if !folding, !columnChanged, let opening {
            track = opening.track(from, to)
        } else {
            let basic = CABasicAnimation()
            basic.fromValue = from
            basic.toValue = to
            basic.duration = columnChanged ? NativeSidecardTiming.duration : NativeReadingPageTiming.duration
            basic.timingFunction = columnChanged ? CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                : folding ? CAMediaTimingFunction(name: .easeOut) : NativeReadingPageTiming.emphasizedOpening
            track = basic
        }
        track.keyPath = key
        return track
    }
}

struct NativeMokuReadingGlass: NSViewRepresentable {
    let size: CGSize
    let viewport: CGSize
    let immediate: Bool
    let motion: NativeMokuReadingMorph
    let hovered: Bool
    let compactChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ReadingGlassView { ReadingGlassView() }
    static func dismantleNSView(_ view: ReadingGlassView, coordinator: ()) { view.retire() }

    func updateNSView(_ view: ReadingGlassView, context: Context) {
        view.configure(size: size, viewport: viewport, opaque: context.environment.accessibilityReduceTransparency,
                       immediate: immediate, transaction: context.transaction, motion: motion,
                       hovered: hovered, compactChanged: compactChanged)
    }
}

final class ReadingGlassView: NSView {
    private let glass = NSGlassEffectView()
    private let finish = CALayer()
    private let aperture = CALayer()
    private var generation = 0
    private var target: CGSize?
    private var viewport = CGSize.zero
    private var stamp: (height: CGFloat, scale: CGFloat, opaque: Bool)?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        glass.style = .clear
        glass.cornerRadius = NativeMokuCapsuleLayout.cornerRadius
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.wantsLayer = true
        addSubview(glass)
        aperture.backgroundColor = NSColor.black.cgColor
        aperture.cornerRadius = NativeMokuCapsuleLayout.cornerRadius
        aperture.cornerCurve = .continuous
        glass.layer?.mask = aperture
        layer?.addSublayer(finish)
        finish.zPosition = 1
        for layer in [finish, aperture] { layer.anchorPoint = CGPoint(x: 0.5, y: 1) }
        finish.shadowOpacity = 0.13
        finish.shadowOffset = CGSize(width: 0, height: 6)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }

    func configure(size: CGSize, viewport: CGSize, opaque: Bool, immediate: Bool,
                   transaction: Transaction, motion: NativeMokuReadingMorph, hovered: Bool, compactChanged: @escaping (Bool) -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        finish.shadowRadius = hovered ? 17 : 13
        let scale = window?.backingScaleFactor ?? 2
        if stamp?.height != size.height || stamp?.scale != scale || stamp?.opaque != opaque {
            // Stretch only the middle of the gradient/rim. Text, identity and
            // the glass backdrop never enter this small decorative image.
            let cap = ceil(min(NativeMokuCapsuleLayout.cornerRadius, size.height / 2))
            let width = 2 * cap + 2
            let renderer = ImageRenderer(content: NativeMokuCapsuleFinish(opaque: opaque)
                .frame(width: width, height: max(1, size.height)))
            renderer.scale = scale
            finish.contents = renderer.cgImage
            finish.contentsScale = scale
            finish.contentsCenter = CGRect(x: cap / width, y: 0, width: 2 / width, height: 1)
            glass.isHidden = opaque
            stamp = (size.height, scale, opaque)
        }
        let resized = self.viewport != viewport
        guard size != target || resized || immediate && finish.animationKeys() != nil else { return }
        let previous = target
        let presented = finish.animationKeys() == nil ? nil : finish.presentation()?.bounds.size
        let source = presented ?? previous ?? size
        target = size
        self.viewport = viewport
        let animated = previous != nil && !resized && !immediate
            && !transaction.disablesAnimations && transaction.animation != nil
        // The mask and finish travel on the render server. A backing material
        // large enough for both endpoints stays live throughout the fold.
        let backing = CGSize(width: max(size.width, animated ? source.width : 0),
                             height: max(size.height, animated ? source.height : 0))
        placeGlass(backing, in: viewport)
        generation += 1
        let command = generation
        let idle = NativeMokuCapsuleLayout.idleSize
        let compact = size.width <= idle.width && size.height <= idle.height
        // Only the current presented fold may release the outgoing column.
        // Schedule immediate receipts outside the representable update too.
        if !compact || !animated {
            Task { @MainActor [weak self] in
                guard self?.generation == command else { return }
                compactChanged(compact)
            }
        }
        if animated && (compact || backing != size) {
            CATransaction.setCompletionBlock { [weak self] in
                Task { @MainActor in
                    guard let self, self.generation == command else { return }
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    self.placeGlass(size, in: viewport)
                    CATransaction.commit()
                    if compact { compactChanged(true) }
                }
            }
        }
        finish.position = CGPoint(x: viewport.width / 2, y: viewport.height)
        for layer in [finish, aperture] {
            layer.removeAllAnimations()
            layer.bounds = CGRect(origin: .zero, size: size)
        }
        guard animated else { return }
        for (axis, from, to) in [("bounds.size.width", source.width, size.width),
                                 ("bounds.size.height", source.height, size.height)] where from != to {
            let track = motion.track(axis, from: from, to: to,
                                     columnChanged: transaction.animation == NativeSidecardTiming.foldAnimation)
            finish.add(track, forKey: axis)
            aperture.add(track, forKey: axis)
        }
    }

    func retire() { generation += 1 }

    private func placeGlass(_ backing: CGSize, in viewport: CGSize) {
        glass.frame = CGRect(x: (viewport.width - backing.width) / 2, y: viewport.height - backing.height,
                             width: backing.width, height: backing.height)
        let flipped = glass.isFlipped
        aperture.anchorPoint.y = flipped ? 1 : 0
        aperture.position = CGPoint(x: backing.width / 2, y: flipped ? backing.height : 0)
    }
}

/// The mark stays live through a flip. Inside a reader its fixed-size native
/// seat follows the shell on the same curve, independently of editor layout.
struct NativeMokuIdentityPosition<Content: View>: NSViewRepresentable {
    let plane: CGSize
    let offset: CGPoint
    let motion: NativeMokuReadingMorph?
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> ReadingIdentityView { ReadingIdentityView() }

    func updateNSView(_ view: ReadingIdentityView, context: Context) {
        view.ink.update(content: AnyView(content.environment(\.self, context.environment)),
                        transaction: context.transaction, visible: true, curve: .linear, duration: 0)
        view.place(plane: plane, offset: offset, motion: motion, transaction: context.transaction)
    }
}

final class ReadingIdentityView: NSView {
    let ink = NativeMokuInkView()
    private var previous: CGPoint?
    private var plane = CGSize.zero
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(ink)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }

    func place(plane: CGSize, offset: CGPoint, motion: NativeMokuReadingMorph?, transaction: Transaction) {
        guard previous != offset || self.plane != plane || motion == nil && ink.layer?.animationKeys() != nil else { return }
        let size = NativeMokuFaceLayout.seat
        let layer = ink.layer!
        let visible = layer.presentation()?.transform ?? CATransform3DIdentity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        ink.frame = CGRect(x: (plane.width - size.width) / 2 + offset.x,
                           y: plane.height - size.height + offset.y, width: size.width, height: size.height)
        layer.removeAnimation(forKey: "transform.translation.x")
        layer.removeAnimation(forKey: "transform.translation.y")
        if let motion, let previous, !transaction.disablesAnimations, transaction.animation != nil {
            for (key, delta) in [("transform.translation.x", previous.x + visible.m41 - offset.x),
                                 ("transform.translation.y", previous.y + visible.m42 - offset.y)] where abs(delta) > 0.01 {
                let track = motion.track(key, from: delta, to: 0,
                                         columnChanged: transaction.animation == NativeSidecardTiming.foldAnimation)
                layer.add(track, forKey: key)
            }
        }
        self.plane = plane
        previous = offset
    }
}
