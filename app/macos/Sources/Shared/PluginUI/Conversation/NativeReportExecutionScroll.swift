import AppKit
import QuartzCore
import SwiftUI

/// Only the execution viewport turns. A submitted page can land before its
/// receipt, while the accepted reader still owns content and input readiness.
public struct NativeReportExecutionScroll<Content: View>: NSViewRepresentable {
    private let visit: UUID
    private let continuing: Bool
    private let active: Bool
    private let onReady: () -> Void
    private let connection: NativeReportSidecardPresentation.Connection?
    private let content: Content
    @Environment(\.scenePhase) private var scenePhase

    public init(visit: UUID, continuing: Bool, active: Bool, connection: NativeReportSidecardPresentation.Connection? = nil,
                onReady: @escaping () -> Void,
                @ViewBuilder content: () -> Content) {
        self.visit = visit; self.continuing = continuing; self.active = active
        self.connection = connection; self.onReady = onReady; self.content = content()
    }

    public func makeNSView(context: Context) -> NSView { ReportExecutionScrollView() }
    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ReportExecutionScrollView else { return }
        view.update(content: AnyView(content), environment: context.environment, visit: visit,
            continuing: continuing, animated: active && scenePhase == .active && !context.environment.accessibilityReduceMotion,
            connection: connection,
            onReady: onReady)
    }
    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
    public static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? ReportExecutionScrollView)?.retire()
    }
}

@MainActor private final class ReportExecutionScrollView: NSView {
    private var current = ReportExecutionScrollSeat()
    private var outgoing: ReportExecutionScrollSeat?
    private var visit: UUID?
    private var animated = false
    private var resized = false
    private var travelling = false
    private var scheduled = false
    private var viewportSize = CGSize.zero
    private var onReady: (() -> Void)?

    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; layer?.masksToBounds = true
        addSubview(current)
    }
    required init?(coder: NSCoder) { nil }

    func update(content: AnyView, environment: EnvironmentValues, visit: UUID,
                continuing: Bool, animated: Bool, connection: NativeReportSidecardPresentation.Connection?, onReady: @escaping () -> Void) {
        if self.visit != visit {
            discardOutgoing()
            resized = false
            if self.visit != nil, continuing {
                outgoing = current
                outgoing?.setActive(false)
            } else { current.removeFromSuperview() }
            current = ReportExecutionScrollSeat()
            current.fades = !continuing
            addSubview(current)
            self.visit = visit
        }
        self.animated = animated && !resized; self.onReady = onReady
        current.update(content: content, environment: environment, connection: connection, active: outgoing == nil) { [weak self, weak current] in
            guard let self, let current, self.current === current, self.visit == visit else { return }
            current.ready = true
            if current.landed { publishContent() } else { scheduleLanding() }
        }
        layoutSeats()
        if travelling && !self.animated { finish() }
        else { scheduleLanding() }
    }

    override func layout() {
        super.layout()
        layoutSeats()
        scheduleLanding()
    }

    private func layoutSeats() {
        let previousSize = viewportSize
        viewportSize = bounds.size
        if outgoing != nil, previousSize != .zero, previousSize != viewportSize {
            // A resize invalidates the travel distance; keep loading covered,
            // but settle an admitted destination without stale geometry.
            resized = true; animated = false
            if travelling { finish() }
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        current.frame = bounds; outgoing?.frame = bounds
        current.alphaValue = outgoing == nil || travelling ? 1 : 0
        CATransaction.commit()
    }

    private func scheduleLanding() {
        guard current.hasPage, !current.landed, !travelling, !scheduled,
              bounds.width > 0, bounds.height > 0 else { return }
        scheduled = true
        let token = visit
        DispatchQueue.main.async { [weak self] in
            guard let self, visit == token else { return }
            scheduled = false
            guard current.hasPage, !current.landed, !travelling,
                  bounds.width > 0, bounds.height > 0 else { return }
            current.layoutSubtreeIfNeeded()
            // Readiness may have queued before a resize. Reconcile its geometry
            // before entering travel, so resize settlement cannot publish input
            // and then fall through into installing another animation.
            layoutSeats()
            guard animated, let outgoing, bounds.height > 0 else { finish(); return }
            travelling = true
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            current.alphaValue = 1
            CATransaction.setCompletionBlock { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    guard let self, visit == token, travelling else { return }
                    finish()
                }
            }
            translate(outgoing, from: 0, to: -bounds.height)
            translate(current, from: bounds.height, to: 0)
            CATransaction.commit()
        }
    }

    private func translate(_ seat: NSView, from: CGFloat, to: CGFloat) {
        // Only paint moves. Offscreen model frames would let TextKit cull ink
        // before arrival and would reset the native reader's scroll geometry.
        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        animation.fromValue = from; animation.toValue = to
        animation.duration = NativeReadingPageTiming.duration
        animation.timingFunction = NativeReadingPageTiming.replacementTimingFunction
        animation.fillMode = .forwards; animation.isRemovedOnCompletion = false
        seat.layer?.add(animation, forKey: "report.execution.scroll")
    }

    private func finish() {
        discardOutgoing()
        current.setActive(true)
        layoutSeats()
        current.landed = true
        publishContent()
    }

    private func publishContent() {
        guard current.ready, current.landed, !current.published else { return }
        current.published = true
        let token = visit
        DispatchQueue.main.async { [weak self] in
            guard let self, visit == token else { return }
            onReady?()
        }
    }

    private func discardOutgoing() {
        scheduled = false; travelling = false
        current.layer?.removeAllAnimations()
        outgoing?.layer?.removeAllAnimations()
        outgoing?.removeFromSuperview(); outgoing = nil
    }
    override func hitTest(_ point: NSPoint) -> NSView? { outgoing == nil ? super.hitTest(point) : nil }
    override func accessibilityChildren() -> [Any]? { outgoing == nil ? super.accessibilityChildren() : [] }
    func retire() {
        visit = nil; onReady = nil
        discardOutgoing()
        current.host.rootView = AnyView(EmptyView())
    }
}

@MainActor private final class ReportExecutionScrollSeat: NSView {
    let host = NSHostingView(rootView: AnyView(EmptyView()))
    var ready = false
    var landed = false
    var published = false
    var hasPage: Bool { ready || connection != nil }
    var fades = true
    private var connection: NativeReportSidecardPresentation.Connection?
    private var content = AnyView(EmptyView())
    private var environment = EnvironmentValues()
    private var onReady: () -> Void = {}
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        host.sizingOptions = []; host.safeAreaRegions = []
        addSubview(host)
    }
    required init?(coder: NSCoder) { nil }
    func update(content: AnyView, environment: EnvironmentValues, connection: NativeReportSidecardPresentation.Connection?, active: Bool, onReady: @escaping () -> Void) {
        self.connection = connection; self.content = content; self.environment = environment; self.onReady = onReady
        setActive(active)
    }
    func setActive(_ active: Bool) {
        var environment = environment
        environment.nativeReadingInteractionActive = environment.nativeReadingInteractionActive && active
        host.rootView = AnyView(ZStack {
            NativeRelatedExecutionEntrance(fades: fades, onReady: onReady) { content }
                .opacity(connection == nil ? 1 : 0)
                .accessibilityHidden(connection != nil)
                .allowsHitTesting(connection == nil)
            if let connection {
                ReportConnectingPage(connection: connection)
            }
        }
            .allowsHitTesting(active).disabled(!active).accessibilityHidden(!active)
            .environment(\.self, environment))
    }
    override func layout() { super.layout(); host.frame = bounds }
}

/// Use the reader's own heading, author slot, margins and inline loading text.
private struct ReportConnectingPage: View {
    let connection: NativeReportSidecardPresentation.Connection
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 12) {
                NativeThreadHeading(title: connection.title.text ?? "", emoji: connection.title.emoji)
                ThreadAuthorLabel(author: nil, resolved: false)
                ThreadConnectionLabel(harness: connection.harness)
            }
            .frame(maxWidth: NativeGeometry.readingWidth, alignment: .leading)
            .nativeThreadDocumentMargins(standard: geometry.size.width <= 540 ? 18 : 32, viewportWidth: geometry.size.width)
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
        }
    }
}
