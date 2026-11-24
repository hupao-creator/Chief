import ChiefPluginUI
import SwiftUI

struct NativeOverviewTagRail: View {
    let parent: NativeOverviewFilter?
    let selectedID: String?
    let expandedWidth: CGFloat
    let strings: NativeOverviewChromeStrings
    let onTagChange: (NativeOverviewFilter?) -> Void
    var interactions: NativeOverviewChromeInteractions?
    @State private var recentID: String?

    var body: some View {
        ZStack(alignment: .leading) {
            if let parent, !parent.children.isEmpty {
                OverviewFilterRail(selectedID: selectedID) {
                    tagButton(parent, isParent: true)
                        .id(parent.id)
                    ForEach(parent.children) { child in
                        tagButton(child, isParent: false)
                    }
                }
                // Unread ink belongs above the composed glass and follows the chip as it expands.
                .overlayPreferenceValue(OverviewTagBounds.self) { anchors in
                    GeometryReader { reader in
                        ForEach(parent.children) { child in
                            if child.unreadCount > 0, let anchor = anchors[child.id] {
                                let bounds = reader[anchor]
                                OverviewTagUnreadBadge(count: child.unreadCount)
                                    .frame(width: bounds.width, height: bounds.height, alignment: .topTrailing)
                                    .position(x: bounds.midX, y: bounds.midY)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
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
        return OverviewSemanticRailButton(title: isParent ? strings.anyTag : filter.tag,
            emoji: isParent ? nil : (filter.emoji.flatMap { $0.isEmpty ? nil : $0 } ?? "🏷️"),
            hasActiveTasks: !isParent && filter.hasActiveTasks, selected: filter.id == selectedID,
            recent: filter.id == recentID, expandedWidth: expandedWidth, action: select)
            .overviewTagAnchor(filter.id)
            .accessibilityIdentifier(isParent ? "overview-semantic-any" : filter.id)
            .accessibilityLabel(Text(isParent ? strings.anyTag : filter.displayTag))
            .accessibilityValue(Text("\(filter.count)\(activity)\(strings.unreadSuffix(filter.unreadCount))"))
            .modifier(NativeOverviewButtonRegistration(registry: interactions, group: .semantic, id: filter.id, action: select))
    }
}

private struct OverviewSemanticRailButton: View {
    let title: String
    let emoji: String?
    let hasActiveTasks: Bool
    let selected: Bool
    let recent: Bool
    let expandedWidth: CGFloat
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let expanded = hovered || recent
        OverviewRailButton(title: title, titleWidth: expanded ? expandedWidth : nil,
                           selected: selected, action: action) {
            if let emoji {
                Text(verbatim: emoji).font(.system(size: 19)).fixedSize()
                    .background {
                        if hasActiveTasks { OverviewTagActivityIndicator(diameter: 36) }
                    }
            } else {
                Image(systemName: "asterisk").font(.system(size: 17, weight: .semibold))
            }
        }
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: expanded)
    }
}

struct NativeOverviewStatusRail: View {
    let status: NativeOverviewStatusFilter
    let strings: NativeOverviewChromeStrings
    let onStatusChange: (NativeOverviewStatusFilter) -> Void
    var interactions: NativeOverviewChromeInteractions?

    var body: some View {
        OverviewFilterRail(selectedID: status.rawValue) {
            statusButton(.running, emoji: "⏳", title: strings.runningOnly)
            statusButton(.all, emoji: "🗂️", title: strings.allStatuses)
            statusButton(.completed, emoji: "🏁", title: strings.completedOnly)
        }
        .accessibilityLabel(strings.statusFilter)
    }

    private func statusButton(_ value: NativeOverviewStatusFilter, emoji: String, title: String) -> some View {
        let choose = { onStatusChange(value) }
        return OverviewRailButton(title: title, selected: status == value, action: choose) {
            Text(verbatim: emoji).font(.system(size: 19)).fixedSize()
        }
        .overviewTagAnchor(value.rawValue)
        .accessibilityLabel(Text(title))
        .help(title)
        .accessibilityIdentifier("overview-status-" + value.rawValue)
        .modifier(NativeOverviewButtonRegistration(registry: interactions, group: .status, id: value.rawValue, action: choose))
    }
}

private struct OverviewFilterRail<Content: View>: View {
    let selectedID: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: OverviewTagMetrics.railSpacing) {
            VStack(alignment: .leading, spacing: OverviewTagMetrics.railSpacing, content: content)
        }
        .overlayPreferenceValue(OverviewTagBounds.self) { anchors in
            GeometryReader { reader in
                if let selectedID, let anchor = anchors[selectedID] {
                    OverviewSelectionOutline(bounds: reader[anchor])
                }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct OverviewRailButton<Glyph: View>: View {
    let title: String
    var titleWidth: CGFloat?
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let glyph: () -> Glyph

    var body: some View {
        let diameter = OverviewTagMetrics.chipHeight
        Button(action: action) {
            HStack(spacing: 0) {
                glyph()
                    .frame(width: diameter, height: diameter)
                    .accessibilityHidden(true)
                if titleWidth != nil {
                    OverviewTagTitle(title: title)
                        .padding(.trailing, OverviewTagMetrics.labelInset)
                        .transition(.opacity)
                }
            }
            .frame(width: titleWidth ?? diameter, height: diameter, alignment: .leading)
        }
        .buttonStyle(OverviewTagButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
