import AppKit
import QuartzCore
import SwiftUI

struct HistoryPageTravel: Equatable {
    let generation: Int
    let closing: Bool
    let duration: TimeInterval
    let emphasized: Bool
}

/// Keep both documents at their real viewport size. Only the two carriers move.
struct NativeHistoryPageViewport<Current: View, History: View>: View {
    let current: Current
    let history: History
    let progress: CGFloat
    let direction: CGFloat
    let stationaryParent: Bool
    let open: Bool
    let travel: HistoryPageTravel?
    let onCompletion: (HistoryPageTravel) -> Void

    // The conversation rail consumes document margins and the outer reader consumes
    // content readiness. Forward both across the two native hosting boundaries.
    @State private var currentMargin: CGFloat?
    @State private var historyMargin: CGFloat?
    @State private var currentStatus = NativeReadingContentStatus()
    @State private var historyStatus = NativeReadingContentStatus()

    var body: some View {
        HistoryPageHosts(current: current
            .onPreferenceChange(ThreadDocumentLeadingMargin.self) { currentMargin = $0 }
            .onPreferenceChange(NativeReadingContentStatusKey.self) { currentStatus = $0 },
            history: history
                .onPreferenceChange(ThreadDocumentLeadingMargin.self) { historyMargin = $0 }
                .onPreferenceChange(NativeReadingContentStatusKey.self) { historyStatus = $0 },
            progress: progress, direction: direction, stationaryParent: stationaryParent,
            open: open, travel: travel, onCompletion: onCompletion)
            .preference(key: ThreadDocumentLeadingMargin.self,
                        value: [currentMargin, open ? historyMargin : nil].compactMap { $0 }.min())
            .preference(key: NativeReadingContentStatusKey.self, value: open ? historyStatus : currentStatus)
    }
}

private struct HistoryPageHosts<Current: View, History: View>: NSViewRepresentable {
    let current: Current
    let history: History
    let progress: CGFloat
    let direction: CGFloat
    let stationaryParent: Bool
    let open: Bool
    let travel: HistoryPageTravel?
    let onCompletion: (HistoryPageTravel) -> Void

    func makeNSView(context: Context) -> HistoryPageHostView { HistoryPageHostView() }
    func updateNSView(_ view: HistoryPageHostView, context: Context) {
        view.current.page.content = AnyView(current.environment(\.self, context.environment))
        view.history.page.content = AnyView(history.environment(\.self, context.environment))
        view.configure(progress: progress, direction: direction, stationaryParent: stationaryParent,
                       open: open, travel: travel, onCompletion: onCompletion)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HistoryPageHostView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
    static func dismantleNSView(_ view: HistoryPageHostView, coordinator: ()) { view.retire() }
}

@Observable private final class HistoryPageContent {
    var content = AnyView(EmptyView())
}

private struct HostedHistoryContent: View {
    let page: HistoryPageContent
    var body: some View { page.content }
}

private final class HistoryPageSeat: NSView {
    let page = HistoryPageContent()
    private lazy var host = NSHostingView(rootView: HostedHistoryContent(page: page))
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        host.sizingOptions = []
        host.safeAreaRegions = []
        addSubview(host)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); host.frame = bounds }
}

private final class HistoryPageHostView: NSView {
    let current = HistoryPageSeat()
    let history = HistoryPageSeat()
    private var progress: CGFloat = 0
    private var direction: CGFloat = 1
    private var stationaryParent = false
    private var open = false
    private var travel: HistoryPageTravel?
    private var submitted: HistoryPageTravel?
    private var onCompletion: ((HistoryPageTravel) -> Void)?
    private let animationKey = "history.page.travel"

    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(current)
        addSubview(history)
    }
    required init?(coder: NSCoder) { nil }

    func configure(progress: CGFloat, direction: CGFloat, stationaryParent: Bool,
                   open: Bool, travel: HistoryPageTravel?, onCompletion: @escaping (HistoryPageTravel) -> Void) {
        self.progress = progress
        self.direction = direction
        self.stationaryParent = stationaryParent
        self.open = open
        self.travel = travel
        self.onCompletion = onCompletion
        positionPages()
    }

    override func layout() { super.layout(); positionPages() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); positionPages() }

    private func positionPages() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for seat in [current, history] where seat.frame.size != bounds.size {
            seat.frame.size = bounds.size
        }
        guard let currentLayer = current.layer, let historyLayer = history.layer else { return }
        let distance = bounds.height * direction
        let target = travel.map { $0.closing ? CGFloat.zero : 1 } ?? progress
        let historyY = distance * (1 - target)
        let currentY = stationaryParent ? 0 : -distance * target
        guard let travel else {
            submitted = nil
            currentLayer.removeAnimation(forKey: animationKey)
            historyLayer.removeAnimation(forKey: animationKey)
            currentLayer.setAffineTransform(.init(translationX: 0, y: currentY))
            historyLayer.setAffineTransform(.init(translationX: 0, y: historyY))
            return
        }
        guard travel != submitted, window != nil, bounds.width > 0, bounds.height > 0 else { return }
        // Reversal samples a single edge for both pages, even if AppKit has
        // already adopted their target frames. This keeps their seam closed.
        let startY = submitted != nil
            ? (historyLayer.presentation() ?? historyLayer).affineTransform().ty
            : distance * (1 - progress)
        submitted = travel
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, submitted == travel else { return }
                onCompletion?(travel)
            }
        }
        let timing = travel.emphasized ? NativeReadingPageTiming.emphasizedOpening
            : NativeReadingPageTiming.replacementTimingFunction
        for (layer, from, to) in [(currentLayer, stationaryParent ? 0 : startY - distance, currentY),
                                  (historyLayer, startY, historyY)] {
            layer.setAffineTransform(.init(translationX: 0, y: to))
            let animation = CABasicAnimation(keyPath: "transform.translation.y")
            animation.fromValue = from
            animation.toValue = to
            animation.duration = travel.duration
            animation.timingFunction = timing
            layer.add(animation, forKey: animationKey)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard travel == nil else { return nil }
        let seat = open ? history : current
        return seat.hitTest(convert(point, from: superview))
    }

    override func accessibilityChildren() -> [Any]? {
        travel == nil ? [open ? history : current] : []
    }

    func retire() {
        travel = nil
        submitted = nil
        onCompletion = nil
        current.layer?.removeAnimation(forKey: animationKey)
        history.layer?.removeAnimation(forKey: animationKey)
    }
}
