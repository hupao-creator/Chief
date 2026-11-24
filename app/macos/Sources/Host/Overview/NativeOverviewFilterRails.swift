import ChiefPluginUI
import SwiftUI

struct NativeOverviewTagRail: View {
    let parent: NativeOverviewFilter?
    let selectedID: String?
    let maximumWidth: CGFloat
    let strings: NativeOverviewChromeStrings
    let onTagChange: (NativeOverviewFilter?) -> Void
    var interactions: NativeOverviewChromeInteractions?

    var body: some View {
        let tags = parent?.children ?? []
        VStack(alignment: .leading, spacing: OverviewTagMetrics.railSpacing) {
            ForEach(tags) { tag in tagButton(tag) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(strings.filter)
        .accessibilityHidden(tags.isEmpty)
    }

    private func tagButton(_ filter: NativeOverviewFilter) -> some View {
        let select = { onTagChange(filter) }
        let activity = filter.hasActiveTasks ? " · \(strings.containsActiveTasks)" : ""
        let selected = filter.id == selectedID
        return OverviewRailButton(selected: selected) { expansion in
            OverviewRailCapsule(edge: .leading, title: filter.tag,
                emoji: filter.semanticEmoji,
                hasActiveTasks: filter.hasActiveTasks, selected: selected,
                unreadCount: filter.unreadCount, maximumWidth: maximumWidth,
                expansion: expansion, action: select)
        }
        .overviewTagAnchor(filter.id)
        .accessibilityIdentifier(filter.id)
        .accessibilityLabel(Text(filter.displayTag))
        .accessibilityValue(Text("\(filter.count)\(activity)\(strings.unreadSuffix(filter.unreadCount))"))
        .modifier(NativeOverviewButtonRegistration(registry: interactions, group: .semantic, id: filter.id, action: select))
    }
}

private struct OverviewRailButton: View {
    let selected: Bool
    let capsule: (CGFloat) -> OverviewRailCapsule
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let expanded = selected || hovered
        // Measure hover beyond the capsule, then restore its original layout and button bounds.
        capsule(expanded ? 1 : 0)
            .padding(.horizontal, OverviewTagMetrics.railHoverInset)
            .onHover { hovered = $0 }
            .padding(.horizontal, -OverviewTagMetrics.railHoverInset)
            .onDisappear { hovered = false }
            .animation(reduceMotion ? nil : NativeMokuCapsuleLayout.overviewExpansionAnimation, value: expanded)
    }
}

private struct OverviewRailCapsule: View, @MainActor Animatable {
    let edge: HorizontalEdge
    let title: String
    let emoji: String
    var hasActiveTasks = false
    let selected: Bool
    var unreadCount = 0
    let maximumWidth: CGFloat
    var expansion: CGFloat
    @Environment(\.pixelLength) var pixelLength
    let action: () -> Void

    var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }

    var body: some View {
        let progress = min(1, max(0, expansion))
        GlassEffectContainer {
            Button(action: action) {
                OverviewRailLabelLayout(edge: edge, maximumWidth: maximumWidth, expansion: progress, pixelLength: pixelLength) {
                    glyph.accessibilityHidden(true)
                    OverviewTagTitle(title: title)
                        .modifier(OverviewCanvasLabelEdge())
                        .opacity(progress)
                }
                .clipped()
            }
            .buttonStyle(OverviewTagButtonStyle(glass: .clear, selected: selected, emoji: emoji))
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        // The unread count follows the presented width while the title expands.
        .overlay(alignment: .topTrailing) {
            if unreadCount > 0 { OverviewTagUnreadBadge(count: unreadCount) }
        }
        .transaction { $0.animation = nil }
    }

    private var glyph: some View {
        Text(verbatim: emoji).font(.system(size: 19 * OverviewTagMetrics.tagScale)).fixedSize()
            .background { if hasActiveTasks { OverviewTagActivityIndicator(diameter: 36 * OverviewTagMetrics.tagScale) } }
    }
}

// Canvas labels can lie over white even in Dark Mode. Keep the edge centered
// on monochrome ink so there is no displaced copy of the glyph.
struct OverviewCanvasLabelEdge: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder func body(content: Content) -> some View {
        if scheme == .dark {
            content.shadow(color: .black.opacity(0.9), radius: 0.75)
        } else {
            content
        }
    }
}

/// The title keeps its final wrapping proposal while the capsule reveals it.
/// Both its natural width and the truncation cap use the actual SwiftUI label.
private struct OverviewRailLabelLayout: Layout {
    let edge: HorizontalEdge
    let maximumWidth: CGFloat
    let expansion: CGFloat
    let pixelLength: CGFloat
    private let diameter = OverviewTagMetrics.railDiameter

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let title = subviews[1].sizeThatFits(.unspecified)
        let extra = min(max(0, maximumWidth - diameter), title.width + OverviewTagMetrics.labelInset * OverviewTagMetrics.tagScale)
        // Snap the moving edge so rounding cannot shift the stationary glyph by a backing pixel.
        let width = ((diameter + expansion * extra) / pixelLength).rounded() * pixelLength
        return CGSize(width: width, height: diameter)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let leading = edge == .leading
        let glyphX = leading ? bounds.minX + diameter / 2 : bounds.maxX - diameter / 2
        subviews[0].place(at: CGPoint(x: glyphX, y: bounds.midY),
                          anchor: .center, proposal: .unspecified)
        let titleWidth = max(0, maximumWidth - diameter - OverviewTagMetrics.labelInset * OverviewTagMetrics.tagScale)
        let titleX = leading ? bounds.minX + diameter : bounds.maxX - diameter
        subviews[1].place(at: CGPoint(x: titleX, y: bounds.midY),
                          anchor: leading ? .leading : .trailing, proposal: .init(width: titleWidth, height: diameter))
    }
}

struct NativeOverviewStatusRail: View {
    let status: NativeOverviewStatusFilter
    let maximumWidth: CGFloat
    let strings: NativeOverviewChromeStrings
    let onStatusChange: (NativeOverviewStatusFilter) -> Void
    var interactions: NativeOverviewChromeInteractions?

    var body: some View {
        VStack(alignment: .trailing, spacing: OverviewTagMetrics.railSpacing) {
            statusButton(.running, emoji: "⏳", title: strings.runningOnly)
            statusButton(.all, emoji: "🗂️", title: strings.allStatuses)
            statusButton(.completed, emoji: "🏁", title: strings.completedOnly)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(strings.statusFilter)
    }

    private func statusButton(_ value: NativeOverviewStatusFilter, emoji: String, title: String) -> some View {
        let choose = { onStatusChange(value) }
        let selected = status == value
        return OverviewRailButton(selected: selected) { expansion in
            OverviewRailCapsule(edge: .trailing, title: title, emoji: emoji, selected: selected,
                maximumWidth: maximumWidth, expansion: expansion, action: choose)
        }
        .overviewTagAnchor(value.rawValue)
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier("overview-status-" + value.rawValue)
        .modifier(NativeOverviewButtonRegistration(registry: interactions, group: .status, id: value.rawValue, action: choose))
    }
}
