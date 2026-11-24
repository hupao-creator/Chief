import ChiefPluginUI
import SwiftUI

struct NativeOverviewTagRail: View {
    let parent: NativeOverviewFilter
    let selectedTag: String
    let selectedKind: NativeOverviewTagKind?
    let strings: NativeOverviewChromeStrings
    let onTagChange: (NativeOverviewFilter?) -> Void
    var interactions: NativeOverviewChromeInteractions?

    var body: some View {
        OverviewFilterRail {
            let chooseParent = { onTagChange(parent) }
            OverviewRailButton(title: strings.anyTag, selected: selectedKind == .directory, action: chooseParent)
                .accessibilityIdentifier("overview-semantic-any")
                .modifier(NativeOverviewButtonRegistration(registry: interactions, group: .semantic,
                    id: parent.id, action: chooseParent))
            ForEach(parent.children) { child in
                let chooseChild = { onTagChange(child) }
                let selected = selectedKind == .semantic && child.matches(selectedTag, kind: .semantic, scope: parent.scope)
                let activity = child.hasActiveTasks ? " · \(strings.containsActiveTasks)" : ""
                OverviewRailButton(title: child.emoji == nil ? child.displayTag : child.tag,
                    emoji: child.emoji, hasActiveTasks: child.hasActiveTasks, selected: selected, action: chooseChild)
                    .overviewTagAnchor(child.id)
                    .accessibilityIdentifier(child.id)
                    .accessibilityLabel(Text(child.displayTag))
                    .accessibilityValue(Text("\(child.count)\(activity)\(strings.unreadSuffix(child.unreadCount))"))
                    .modifier(NativeOverviewButtonRegistration(registry: interactions, group: .semantic,
                        id: child.id, action: chooseChild))
            }
        }
        // The badge ink must sit above the composed glass, including when the list changes.
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

struct NativeOverviewStatusRail: View {
    let status: NativeOverviewStatusFilter
    let strings: NativeOverviewChromeStrings
    let onStatusChange: (NativeOverviewStatusFilter) -> Void
    var interactions: NativeOverviewChromeInteractions?

    var body: some View {
        OverviewFilterRail {
            statusButton(.running, title: strings.runningOnly)
            statusButton(.all, title: strings.allStatuses)
            statusButton(.completed, title: strings.completedOnly)
        }
        .accessibilityLabel(strings.statusFilter)
    }

    private func statusButton(_ value: NativeOverviewStatusFilter, title: String) -> some View {
        let choose = { onStatusChange(value) }
        return OverviewRailButton(title: title, selected: status == value, action: choose)
            .accessibilityIdentifier("overview-status-" + value.rawValue)
            .modifier(NativeOverviewButtonRegistration(registry: interactions, group: .status, id: value.rawValue, action: choose))
    }
}

private struct OverviewFilterRail<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: OverviewTagMetrics.railSpacing) {
            VStack(spacing: OverviewTagMetrics.railSpacing, content: content)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct OverviewRailButton: View {
    let title: String
    var emoji: String?
    var hasActiveTasks = false
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: OverviewTagMetrics.chipContentSpacing) {
                if let emoji {
                    OverviewTagPrefix(emoji: emoji, selected: selected)
                } else {
                    NativeIcon(name: "Check", size: OverviewTagMetrics.folderIcon, strokeWidth: 2)
                        .opacity(selected ? 1 : 0)
                        .accessibilityHidden(true)
                }
                OverviewTagTitle(title: title)
                if hasActiveTasks { OverviewTagActivityIndicator(hasActiveTasks: true) }
            }
            .padding(.horizontal, OverviewTagMetrics.labelInset)
            .frame(maxWidth: .infinity)
            .frame(height: OverviewTagMetrics.chipHeight)
        }
        .buttonStyle(OverviewTagButtonStyle(active: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
