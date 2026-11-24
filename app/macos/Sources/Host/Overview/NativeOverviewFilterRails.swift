import ChiefPluginUI
import SwiftUI

struct NativeOverviewTagRail: View {
    let parent: NativeOverviewFilter?
    let selectedID: String?
    let maximumWidth: CGFloat
    let strings: NativeOverviewChromeStrings
    let onTagChange: (NativeOverviewFilter?) -> Void
    var interactions: NativeOverviewChromeInteractions?
    @State private var recentID: String?
    @State private var hoveredID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            if let parent, !parent.children.isEmpty {
                VStack(alignment: .leading, spacing: OverviewTagMetrics.railSpacing) {
                    tagButton(parent, isParent: true)
                        .id(parent.id)
                    ForEach(parent.children) { child in
                        tagButton(child, isParent: false)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(strings.filter)
            }
        }
        // Observe actual selection changes, including swipes and directory navigation.
        // Mounting the rail for an already-selected scope starts in its compact state.
        .onChange(of: selectedID) { _, id in
            recentID = parent?.children.isEmpty == false ? id : nil
        }
        .task(id: recentID) {
            guard let id = recentID else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            if recentID == id { recentID = nil }
        }
    }

    private func tagButton(_ filter: NativeOverviewFilter, isParent: Bool) -> some View {
        let select = { onTagChange(filter) }
        let activity = filter.hasActiveTasks ? " · \(strings.containsActiveTasks)" : ""
        let expanded = hoveredID == filter.id || recentID == filter.id
        return OverviewSemanticRailButton(title: isParent ? strings.anyTag : filter.tag,
            emoji: isParent ? nil : (filter.emoji.flatMap { $0.isEmpty ? nil : $0 } ?? "🏷️"),
            hasActiveTasks: !isParent && filter.hasActiveTasks, selected: filter.id == selectedID,
            unreadCount: isParent ? 0 : filter.unreadCount, maximumWidth: maximumWidth,
            expansion: expanded ? 1 : 0, action: select)
            .overviewTagAnchor(filter.id)
            .onHover { inside in
                if inside { hoveredID = filter.id }
                else if hoveredID == filter.id { hoveredID = nil }
            }
            .onDisappear { if hoveredID == filter.id { hoveredID = nil } }
            .animation(reduceMotion ? nil : NativeMokuCapsuleLayout.overviewExpansionAnimation, value: expanded)
            .accessibilityIdentifier(isParent ? "overview-semantic-any" : filter.id)
            .accessibilityLabel(Text(isParent ? strings.anyTag : filter.displayTag))
            .accessibilityValue(Text("\(filter.count)\(activity)\(strings.unreadSuffix(filter.unreadCount))"))
            .modifier(NativeOverviewButtonRegistration(registry: interactions, group: .semantic, id: filter.id, action: select))
    }
}

private struct OverviewSemanticRailButton: View, @MainActor Animatable {
    let title: String
    let emoji: String?
    let hasActiveTasks: Bool
    let selected: Bool
    let unreadCount: Int
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
                OverviewSemanticLabelLayout(maximumWidth: maximumWidth, expansion: progress) {
                    glyph.accessibilityHidden(true)
                    OverviewTagTitle(title: title)
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

    @ViewBuilder private var glyph: some View {
        if let emoji {
            Text(verbatim: emoji).font(.system(size: 19)).fixedSize()
                .background { if hasActiveTasks { OverviewTagActivityIndicator(diameter: 36) } }
        } else {
            Image(systemName: "asterisk").font(.system(size: 17, weight: .semibold))
        }
    }
}

/// The title keeps its final wrapping proposal while the capsule reveals it.
/// Both its natural width and the truncation cap use the actual SwiftUI label.
private struct OverviewSemanticLabelLayout: Layout {
    let maximumWidth: CGFloat
    let expansion: CGFloat
    private let diameter = OverviewTagMetrics.chipHeight

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let title = subviews[1].sizeThatFits(.unspecified)
        let extra = min(max(0, maximumWidth - diameter), title.width + OverviewTagMetrics.labelInset)
        return CGSize(width: diameter + expansion * extra, height: diameter)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: CGPoint(x: bounds.minX + diameter / 2, y: bounds.midY),
                          anchor: .center, proposal: .unspecified)
        let titleWidth = max(0, maximumWidth - diameter - OverviewTagMetrics.labelInset)
        subviews[1].place(at: CGPoint(x: bounds.minX + diameter, y: bounds.midY),
                          anchor: .leading, proposal: .init(width: titleWidth, height: diameter))
    }
}

struct NativeOverviewStatusRail: View {
    let status: NativeOverviewStatusFilter
    let strings: NativeOverviewChromeStrings
    let onStatusChange: (NativeOverviewStatusFilter) -> Void
    var interactions: NativeOverviewChromeInteractions?

    var body: some View {
        GlassEffectContainer(spacing: OverviewTagMetrics.railSpacing) {
            VStack(spacing: OverviewTagMetrics.railSpacing) {
                statusButton(.running, emoji: "⏳", title: strings.runningOnly)
                statusButton(.all, emoji: "🗂️", title: strings.allStatuses)
                statusButton(.completed, emoji: "🏁", title: strings.completedOnly)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(strings.statusFilter)
    }

    private func statusButton(_ value: NativeOverviewStatusFilter, emoji: String, title: String) -> some View {
        let choose = { onStatusChange(value) }
        return Button(action: choose) {
            Text(verbatim: emoji).font(.system(size: 19)).fixedSize()
                .frame(width: OverviewTagMetrics.chipHeight, height: OverviewTagMetrics.chipHeight)
        }
        .buttonStyle(OverviewTagButtonStyle(glass: .clear, selected: status == value, emoji: emoji))
        .accessibilityAddTraits(status == value ? .isSelected : [])
        .overviewTagAnchor(value.rawValue)
        .accessibilityLabel(Text(title))
        .help(title)
        .accessibilityIdentifier("overview-status-" + value.rawValue)
        .modifier(NativeOverviewButtonRegistration(registry: interactions, group: .status, id: value.rawValue, action: choose))
    }
}
