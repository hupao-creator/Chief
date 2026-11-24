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
        let hasTags = parent?.children.isEmpty == false
        VStack(alignment: .leading, spacing: OverviewTagMetrics.railSpacing) {
            if let parent, hasTags {
                tagButton(parent, isParent: true)
                    .id(parent.id)
                ForEach(parent.children) { child in
                    tagButton(child, isParent: false)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(strings.filter)
        .accessibilityHidden(!hasTags)
    }

    private func tagButton(_ filter: NativeOverviewFilter, isParent: Bool) -> some View {
        let select = { onTagChange(filter) }
        let activity = filter.hasActiveTasks ? " · \(strings.containsActiveTasks)" : ""
        let selected = filter.id == selectedID
        return OverviewRailButton(selected: selected) { expansion in
            OverviewRailCapsule(edge: .leading, title: isParent ? strings.anyTag : filter.tag,
                emoji: isParent ? nil : filter.semanticEmoji,
                hasActiveTasks: !isParent && filter.hasActiveTasks, selected: selected,
                unreadCount: isParent ? 0 : filter.unreadCount, maximumWidth: maximumWidth,
                expansion: expansion, action: select)
        }
        .overviewTagAnchor(filter.id)
        .accessibilityIdentifier(isParent ? "overview-semantic-any" : filter.id)
        .accessibilityLabel(Text(isParent ? strings.anyTag : filter.displayTag))
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
        capsule(expanded ? 1 : 0)
            .onHover { hovered = $0 }
            .onDisappear { hovered = false }
            .animation(reduceMotion ? nil : NativeMokuCapsuleLayout.overviewExpansionAnimation, value: expanded)
    }
}

private struct OverviewRailCapsule: View, @MainActor Animatable {
    let edge: HorizontalEdge
    let title: String
    let emoji: String?
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
                    OverviewTagTitle(title: title, scale: OverviewTagMetrics.railScale)
                        .modifier(OverviewCanvasLabelEdge())
                        .opacity(progress)
                }
                .clipped()
            }
            .buttonStyle(OverviewTagButtonStyle(glass: .clear, selected: selected, emoji: emoji,
                                              solidAccentSelection: emoji == nil))
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        // The unread count follows the presented width while the title expands.
        .overlay(alignment: .topTrailing) {
            if unreadCount > 0 { OverviewTagUnreadBadge(count: unreadCount, scale: OverviewTagMetrics.railScale) }
        }
        .transaction { $0.animation = nil }
    }

    @ViewBuilder private var glyph: some View {
        if let emoji {
            Text(verbatim: emoji).font(.system(size: 19 * OverviewTagMetrics.railScale)).fixedSize()
                .background { if hasActiveTasks { OverviewTagActivityIndicator(diameter: 36 * OverviewTagMetrics.railScale) } }
        } else {
            OverviewAllTagGlyph(scale: OverviewTagMetrics.railScale)
                .modifier(OverviewCanvasLabelEdge())
        }
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
        let extra = min(max(0, maximumWidth - diameter), title.width + OverviewTagMetrics.labelInset * OverviewTagMetrics.railScale)
        // Snap the moving edge so rounding cannot shift the stationary glyph by a backing pixel.
        let width = ((diameter + expansion * extra) / pixelLength).rounded() * pixelLength
        return CGSize(width: width, height: diameter)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let leading = edge == .leading
        let glyphX = leading ? bounds.minX + diameter / 2 : bounds.maxX - diameter / 2
        subviews[0].place(at: CGPoint(x: glyphX, y: bounds.midY),
                          anchor: .center, proposal: .unspecified)
        let titleWidth = max(0, maximumWidth - diameter - OverviewTagMetrics.labelInset * OverviewTagMetrics.railScale)
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
