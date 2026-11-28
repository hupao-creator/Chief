import ChiefPluginUI
import SwiftUI

struct StartupSkilletEntrance {
    static let duration = 0.80
    let admittedAt = CACurrentMediaTime()
    let loadingSince: TimeInterval

    var progress: Double {
        min(1, max(0, (CACurrentMediaTime() - admittedAt) / Self.duration))
    }
}

extension EnvironmentValues {
    @Entry var startupSkilletEntrance: StartupSkilletEntrance?
}

struct StartupSkilletChrome: ViewModifier {
    @Environment(\.startupSkilletEntrance) private var entrance

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: entrance == nil)) { _ in
            content.opacity(smoothStep((entrance?.progress ?? 1) / 0.80))
        }
    }
}

public struct NativeOverviewStatusEmptyState: View {
    let title: String
    private let recent: NativeOverviewRecentThreadList?
    private let recentInsets: EdgeInsets
    private let recentInteractive: Bool
    static let markHeight: CGFloat = 182
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.startupSkilletEntrance) private var entrance
    private let palette = NativePalette.overview
    private let scale: CGFloat = 1.25
    @Namespace private var viewportSpace

    public init(title: String) {
        self.init(title: title, recent: nil, recentInsets: EdgeInsets(), recentInteractive: true)
    }

    init(title: String, recent: NativeOverviewRecentThreadList?, recentInsets: EdgeInsets, recentInteractive: Bool) {
        self.title = title
        self.recent = recent
        self.recentInsets = recentInsets
        self.recentInteractive = recentInteractive
    }

    public var body: some View {
        GeometryReader { viewport in
            let width = min(NativeOverviewRecentThreadList.idealWidth,
                            viewport.size.width - recentInsets.leading - recentInsets.trailing)
            let height = viewport.size.height - recentInsets.top - recentInsets.bottom
            let availableRows = max(0, Int((height - Self.markHeight - NativeOverviewRecentThreadList.verticalChrome)
                                            / NativeOverviewRecentThreadList.rowHeight))
            if let recent, !recent.threads.isEmpty, width >= NativeOverviewRecentThreadList.minimumWidth, availableRows > 0 {
                VStack(spacing: 0) {
                    mark(in: viewport.size).frame(height: Self.markHeight)
                    NativeOverviewRecentThreadList(title: recent.title,
                        threads: Array(recent.threads.prefix(availableRows)),
                        usesTintedGlass: recent.usesTintedGlass, open: recent.open)
                        .frame(width: width)
                        .modifier(StartupSkilletChrome())
                        .nativeCanvasNavigationRegion()
                        .disabled(!recentInteractive)
                        .allowsHitTesting(recentInteractive)
                        .accessibilityHidden(!recentInteractive)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, recentInsets.top)
                .padding(.bottom, recentInsets.bottom)
                .coordinateSpace(name: viewportSpace)
            } else {
                mark(in: viewport.size).coordinateSpace(name: viewportSpace)
            }
        }
    }

    private func mark(in size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let progress = reduceMotion ? 1 : entrance?.progress ?? 1
            let sleep = smoothStep((progress - 0.45) / 0.50)
            let phase = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 3.6) * 2 * .pi / 3.6
            VStack(spacing: 8) {
                skillet(phase: phase, sleep: sleep, progress: progress, viewport: size)
                Text(title)
                    .font(NativeTypography.inter(size: 15, weight: 650))
                    .foregroundStyle(palette.ink.swiftUI)
                    .background {
                        Capsule().fill(palette.surface.swiftUI)
                            .padding(.horizontal, -8)
                            .padding(.vertical, -3)
                    }
                    .opacity(sleep)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityIdentifier("overview.status.empty")
        .allowsHitTesting(false)
    }

    private func skillet(phase: Double, sleep: Double, progress: Double, viewport: CGSize) -> some View {
        // The bowl is centered at x ≈ 232 in the 624 × 272 artwork. Reserve
        // 160 transparent pixels on the left so its axis bisects the layout.
        Color.clear
            .aspectRatio(784.0 / 272.0, contentMode: .fit)
            .overlay(alignment: .trailing) {
                NativeOverviewIdleMark(identifier: "overview.status.empty.logo", scale: scale)
                    .offset(y: sleep * scale * 1.6 * sin(phase))
                    .opacity(progress == 1 ? 1 : 0)
            }
            .overlay {
                GeometryReader { geometry in
                    let unit = geometry.size.width / 196
                    ForEach(0..<3) { index in
                        let step = CGFloat(index)
                        let drift = reduceMotion ? 0 : sin(phase - step * 0.7)
                        Text(verbatim: "z")
                            .font(.system(size: (11 + 2 * step) * unit, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.ink.swiftUI)
                            .shadow(color: palette.surface.swiftUI, radius: unit)
                            .rotationEffect(.degrees(-9))
                            .position(x: (125 + step * 11 + drift) * unit,
                                      y: (-1 - step * 6 - 2 * drift) * unit)
                    }
                    .opacity(sleep)
                    if progress < 1, let entrance {
                        settlingSkillet(entrance, phase: phase, geometry: geometry, viewport: viewport,
                                        progress: progress, sleep: sleep)
                    }
                }
            }
            .frame(maxWidth: 196 * scale, maxHeight: 68 * scale)
            .padding(.top, 25 * scale)
            .accessibilityHidden(true)
    }

    private func settlingSkillet(_ entrance: StartupSkilletEntrance, phase: Double, geometry: GeometryProxy, viewport: CGSize,
                                 progress: Double, sleep: Double) -> some View {
        let frame = geometry.frame(in: .named(viewportSpace))
        let source = CGPoint(x: viewport.width / 2 - frame.minX, y: viewport.height / 2 - frame.minY)
        let sourceScale = min(1, viewport.width / 250, viewport.height / 152)
        let targetScale = frame.width / 245
        // In the toss canvas, the common idle sprite is centered 22.5 pt
        // below its midpoint. Arrive at the live idle bob, including on resize.
        let target = CGPoint(x: frame.width / 2, y: frame.height / 2 - 22.5 * targetScale
            + sleep * scale * 1.6 * sin(phase))
        let travel = smoothStep(progress / 0.84)
        let size = sourceScale + (targetScale - sourceScale) * travel
        return NativeTossedSkillet(elapsed: CACurrentMediaTime() - entrance.loadingSince,
                                    motion: 1 - smoothStep(progress / 0.57),
                                    tuck: smoothStep((progress - 0.08) / 0.47), sleep: sleep)
            .frame(width: 250 * size, height: 152 * size)
            .position(x: source.x + (target.x - source.x) * travel,
                      y: source.y + (target.y - source.y) * travel)
    }
}

private func smoothStep(_ value: Double) -> Double {
    let t = min(1, max(0, value))
    return t * t * (3 - 2 * t)
}
