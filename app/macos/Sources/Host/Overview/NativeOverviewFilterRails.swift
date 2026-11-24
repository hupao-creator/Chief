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
        OverviewFilterRail(edge: .leading, selectedID: selectedID, hasChoices: hasTags) { recentID in
            if let parent, hasTags {
                tagButton(parent, isParent: true, recentID: recentID)
                    .id(parent.id)
                ForEach(parent.children) { child in
                    tagButton(child, isParent: false, recentID: recentID)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(strings.filter)
        .accessibilityHidden(!hasTags)
    }

    private func tagButton(_ filter: NativeOverviewFilter, isParent: Bool, recentID: String?) -> some View {
        let select = { onTagChange(filter) }
        let activity = filter.hasActiveTasks ? " · \(strings.containsActiveTasks)" : ""
        return OverviewRailButton(recentlySelected: recentID == filter.id) { expansion in
            OverviewRailCapsule(edge: .leading, title: isParent ? strings.anyTag : filter.tag,
                emoji: isParent ? nil : filter.semanticEmoji,
                hasActiveTasks: !isParent && filter.hasActiveTasks, selected: filter.id == selectedID,
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

private struct OverviewFilterRail<Content: View>: View {
    let edge: HorizontalEdge
    let selectedID: String?
    var hasChoices = true
    @ViewBuilder var buttons: (String?) -> Content
    @State private var recentID: String?

    var body: some View {
        VStack(alignment: edge == .leading ? .leading : .trailing, spacing: OverviewTagMetrics.railSpacing) {
            buttons(recentID)
        }
        // Clicks and swipes share the selection timer. Initial selection stays compact.
        .onChange(of: selectedID) { _, id in recentID = hasChoices ? id : nil }
        .task(id: recentID) {
            guard let id = recentID else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            if recentID == id { recentID = nil }
        }
    }
}

private struct OverviewRailButton: View {
    let recentlySelected: Bool
    let capsule: (CGFloat) -> OverviewRailCapsule
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let expanded = hovered || recentlySelected
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
    let action: () -> Void

    var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }

    var body: some View {
        let progress = min(1, max(0, expansion))
        GlassEffectContainer {
            Button(action: action) {
                OverviewRailLabelLayout(edge: edge, maximumWidth: maximumWidth, expansion: progress) {
                    glyph.accessibilityHidden(true)
                    OverviewTagTitle(title: title)
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
            if unreadCount > 0 { OverviewTagUnreadBadge(count: unreadCount) }
        }
        .transaction { $0.animation = nil }
    }

    @ViewBuilder private var glyph: some View {
        if let emoji {
            Text(verbatim: emoji).font(.system(size: 19)).fixedSize()
                .background { if hasActiveTasks { OverviewTagActivityIndicator(diameter: 36) } }
        } else {
            OverviewAllTagGlyph()
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
    private let diameter = OverviewTagMetrics.chipHeight

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let title = subviews[1].sizeThatFits(.unspecified)
        let extra = min(max(0, maximumWidth - diameter), title.width + OverviewTagMetrics.labelInset)
        return CGSize(width: diameter + expansion * extra, height: diameter)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let leading = edge == .leading
        let glyphX = leading ? bounds.minX + diameter / 2 : bounds.maxX - diameter / 2
        subviews[0].place(at: CGPoint(x: glyphX, y: bounds.midY),
                          anchor: .center, proposal: .unspecified)
        let titleWidth = max(0, maximumWidth - diameter - OverviewTagMetrics.labelInset)
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
        OverviewFilterRail(edge: .trailing, selectedID: status.rawValue) { recentID in
            statusButton(.running, emoji: "⏳", title: strings.runningOnly, recentID: recentID)
            statusButton(.all, emoji: "🗂️", title: strings.allStatuses, recentID: recentID)
            statusButton(.completed, emoji: "🏁", title: strings.completedOnly, recentID: recentID)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(strings.statusFilter)
    }

    private func statusButton(_ value: NativeOverviewStatusFilter, emoji: String, title: String, recentID: String?) -> some View {
        let choose = { onStatusChange(value) }
        return OverviewRailButton(recentlySelected: value.rawValue == recentID) { expansion in
            OverviewRailCapsule(edge: .trailing, title: title, emoji: emoji, selected: status == value,
                maximumWidth: maximumWidth, expansion: expansion, action: choose)
        }
        .overviewTagAnchor(value.rawValue)
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier("overview-status-" + value.rawValue)
        .modifier(NativeOverviewButtonRegistration(registry: interactions, group: .status, id: value.rawValue, action: choose))
    }
}
