import ChiefPluginUI
import SwiftUI

enum NativeOverviewRailChoice: Identifiable, Equatable {
    case tag(NativeOverviewFilter)
    case status(NativeOverviewStatusFilter)

    var id: String {
        switch self {
        case .tag(let filter): filter.id
        case .status(let status): status.rawValue
        }
    }
}

struct NativeOverviewTagRail: View {
    let choices: [NativeOverviewRailChoice]
    let selectedID: String?
    let maximumWidth: CGFloat
    let strings: NativeOverviewChromeStrings
    let onSelect: (NativeOverviewRailChoice) -> Void
    let onClearUnread: (String) -> Void
    var interactions: NativeOverviewChromeInteractions?

    var body: some View {
        ViewThatFits(in: .vertical) {
            buttons.fixedSize(horizontal: false, vertical: true)
            ScrollView(.vertical) { buttons.padding(.vertical, 4) }
                .scrollIndicators(.automatic)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(choices.contains { if case .tag = $0 { true } else { false } } ? strings.filter : strings.statusFilter)
        .accessibilityHidden(choices.isEmpty)
    }

    private var buttons: some View {
        VStack(alignment: .leading, spacing: OverviewTagMetrics.railSpacing) {
            ForEach(choices) { choice in
                switch choice {
                case .tag(let filter):
                    let activity = filter.hasActiveTasks ? " · \(strings.containsActiveTasks)" : ""
                    let clear = { onClearUnread(filter.id) }
                    button(choice, title: filter.tag, emoji: filter.semanticEmoji, group: .semantic,
                           hasActiveTasks: filter.hasActiveTasks, unreadCount: filter.unreadCount, onHold: clear)
                        .accessibilityLabel(Text(filter.displayTag))
                        .accessibilityValue(Text("\(filter.count)\(activity)\(strings.unreadSuffix(filter.unreadCount))"))
                        .accessibilityActions {
                            if filter.unreadCount > 0 {
                                Button(strings.clearUnread, action: clear)
                            }
                        }
                case .status(let status):
                    let (title, emoji) = switch status {
                    case .running: (strings.runningOnly, "⏳")
                    case .unread: (strings.unreadOnly, "🔖")
                    case .all: (strings.allStatuses, "🗂️")
                    case .completed: (strings.completedOnly, "🏁")
                    }
                    button(choice, title: title, emoji: emoji, group: .status)
                        .accessibilityLabel(Text(title))
                }
            }
        }
    }

    private func button(_ choice: NativeOverviewRailChoice, title: String, emoji: String,
                        group: NativeOverviewControlGroup, hasActiveTasks: Bool = false, unreadCount: Int = 0,
                        onHold: (() -> Void)? = nil) -> some View {
        let select = { onSelect(choice) }
        let selected = choice.id == selectedID
        return OverviewRailButton(selected: selected) { expansion in
            OverviewRailCapsule(title: title, emoji: emoji, hasActiveTasks: hasActiveTasks, selected: selected,
                unreadCount: unreadCount, maximumWidth: maximumWidth, expansion: expansion, action: select, onHold: onHold)
        }
        .overviewTagAnchor(choice.id)
        .accessibilityIdentifier(group == .status ? "overview-status-" + choice.id : choice.id)
        .modifier(NativeOverviewButtonRegistration(registry: interactions, group: group, id: choice.id, action: select))
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
    let title: String
    let emoji: String
    var hasActiveTasks = false
    let selected: Bool
    var unreadCount = 0
    let maximumWidth: CGFloat
    var expansion: CGFloat
    @Environment(\.pixelLength) var pixelLength
    let action: () -> Void
    let onHold: (() -> Void)?

    var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }

    var body: some View {
        let progress = min(1, max(0, expansion))
        GlassEffectContainer {
            Button(action: action) {
                OverviewRailLabelLayout(maximumWidth: maximumWidth, expansion: progress, pixelLength: pixelLength) {
                    glyph.accessibilityHidden(true)
                    OverviewTagTitle(title: title)
                        .modifier(OverviewCanvasLabelEdge())
                        .opacity(progress)
                }
                .clipped()
            }
            .buttonStyle(OverviewTagButtonStyle(glass: .clear, selected: selected, emoji: emoji))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .overlay {
                if let onHold {
                    OverviewTagPointerPress(onClick: action, onHold: onHold)
                        .accessibilityHidden(true)
                }
            }
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
        let glyphX = bounds.minX + diameter / 2
        subviews[0].place(at: CGPoint(x: glyphX, y: bounds.midY),
                          anchor: .center, proposal: .unspecified)
        let titleWidth = max(0, maximumWidth - diameter - OverviewTagMetrics.labelInset * OverviewTagMetrics.tagScale)
        let titleX = bounds.minX + diameter
        subviews[1].place(at: CGPoint(x: titleX, y: bounds.midY),
                          anchor: .leading, proposal: .init(width: titleWidth, height: diameter))
    }
}
