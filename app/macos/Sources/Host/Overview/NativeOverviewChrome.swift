import ChiefPluginUI
import SwiftUI

public enum NativeOverviewTagKind: String, Sendable { case directory, semantic }

public struct NativeOverviewFilter: Identifiable, Equatable, Sendable {
    public var tag: String
    public var displayTag: String
    public var emoji: String?
    public var scope: String
    public var count: Int
    public var hasActiveTasks: Bool
    public var unreadCount = 0
    public var aliases: [String]
    public var isDirectory: Bool
    public var selectionKey: String
    /// Directory and Inbox filters own the semantic tags in their scope.
    public var children: [NativeOverviewFilter]
    // Membership changes counts and selectionKey, not the identity of this control.
    public var id: String { "\(isDirectory ? "directory" : "semantic"):\(scope):\(Self.key(tag))" }

    public init(tag: String, displayTag: String? = nil, emoji: String? = nil, scope: String = "", count: Int, aliases: [String] = [],
                isDirectory: Bool = false, selectionKey: String = "", children: [NativeOverviewFilter] = [], hasActiveTasks: Bool = false) {
        self.tag = tag; self.displayTag = displayTag ?? tag; self.emoji = emoji
        self.scope = scope; self.count = count; self.aliases = aliases
        self.isDirectory = isDirectory; self.selectionKey = selectionKey; self.children = children
        self.hasActiveTasks = hasActiveTasks
    }

    public func matches(_ selectedTag: String, kind: NativeOverviewTagKind? = nil, scope: String? = nil) -> Bool {
        if let kind, isDirectory != (kind == .directory) { return false }
        if let scope, !scope.isEmpty, self.scope != scope { return false }
        let selected = Self.key(selectedTag)
        return Self.key(tag) == selected || aliases.contains { Self.key($0) == selected }
    }

    private static func key(_ text: String) -> String {
        NativeOverviewSelection.key(text)
    }
}

/// Floating Liquid Glass controls. The host owns collection filtering.
public struct NativeOverviewChrome: View {
    private let viewportHeight: CGFloat?
    public var filters: [NativeOverviewFilter]
    public var allHasActiveTasks: Bool
    public var selectedTag: String
    public var selectedScope: String
    public var selectedKind: NativeOverviewTagKind?
    public var onTagChange: (NativeOverviewFilter?) -> Void
    public var onSettings: (() -> Void)?
    /// Bounds use logical points from the top-left of the zoomable client viewport.
    public var onSettingsWithOrigin: ((CGRect) -> Void)?
    public var onSettingsFrameChange: ((CGRect?) -> Void)?
    public var onRestart: (() -> Void)?
    public var interactions: NativeOverviewChromeInteractions?
    public var strings: NativeOverviewChromeStrings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tagGlass
    @Namespace private var actionGlass
    @State private var presentedFilters: [NativeOverviewFilter]
    @State private var hasPresentedFilters: Bool
    @State private var settingsAnchor = OverviewSettingsAnchor()
    @State private var measuredAllWidth: CGFloat = 0
    @State private var measuredTagsWidth: CGFloat = 0
    @State private var interactionOwner = UUID()

    public init(filters: [NativeOverviewFilter], viewportHeight: CGFloat? = nil, selectedTag: String = "", selectedScope: String = "", selectedKind: NativeOverviewTagKind? = nil,
                allHasActiveTasks: Bool = false,
                strings: NativeOverviewChromeStrings = .init(),
                onTagChange: @escaping (NativeOverviewFilter?) -> Void,
                onSettings: (() -> Void)? = nil, onRestart: (() -> Void)? = nil,
                onSettingsWithOrigin: ((CGRect) -> Void)? = nil,
                onSettingsFrameChange: ((CGRect?) -> Void)? = nil,
                interactions: NativeOverviewChromeInteractions? = nil) {
        self.viewportHeight = viewportHeight
        self.filters = filters; self.selectedTag = selectedTag; self.selectedScope = selectedScope; self.selectedKind = selectedKind
        self.allHasActiveTasks = allHasActiveTasks
        _presentedFilters = State(initialValue: filters)
        _hasPresentedFilters = State(initialValue: !filters.isEmpty)
        self.strings = strings; self.onTagChange = onTagChange
        self.onSettings = onSettings; self.onRestart = onRestart
        self.interactions = interactions
        self.onSettingsWithOrigin = onSettingsWithOrigin; self.onSettingsFrameChange = onSettingsFrameChange
    }

    public var body: some View {
        let stackedFilterTop = OverviewTagMetrics.stackedFilterTop(viewportHeight: viewportHeight ?? .infinity)
        GeometryReader { geometry in
            let stacked = OverviewTagMetrics.stacksFilters(in: geometry.size.width)
            let inset: CGFloat = stacked ? 14 : 18
            let sideSeat = max(actionWidth + inset, NativeWindowNavigationGeometry.closedWidth) + 16
            let maximumFilterWidth = max(0, geometry.size.width - 2 * (stacked ? inset : sideSeat))
            ZStack(alignment: .top) {
                HStack {
                    Spacer(minLength: 0)
                    actions
                }
                .padding(.horizontal, inset)
                .padding(.top, stacked ? OverviewTagMetrics.compactActionTop : OverviewTagMetrics.singleRowTop)
                // Retain the scroll/container identities through an empty result so
                // outgoing surfaces can finish, while hiding the empty bar as before.
                filtersBar(maximumWidth: maximumFilterWidth)
                    .frame(width: min(naturalFilterWidth, maximumFilterWidth), height: OverviewTagMetrics.barHeight)
                    .padding(.top, stacked ? stackedFilterTop : OverviewTagMetrics.singleRowTop)
                    .opacity(presentedFilters.isEmpty ? 0 : 1)
                    .allowsHitTesting(!presentedFilters.isEmpty)
                    .disabled(presentedFilters.isEmpty)
                    .accessibilityHidden(presentedFilters.isEmpty)
            }
        }
        .frame(height: stackedFilterTop + OverviewTagMetrics.chipHeight)
        .onDisappear { interactions?.removeChrome(owner: interactionOwner) }
        .onChange(of: filters) { _, updated in presentFilters(updated, animated: hasPresentedFilters && !reduceMotion) }
        .onAppear {
            interactions?.installChrome(owner: interactionOwner)
            presentFilters(filters, animated: false)
        }
    }

    private var actionWidth: CGFloat {
        let count = (onRestart != nil ? 1 : 0)
            + (onSettings != nil || onSettingsWithOrigin != nil ? 1 : 0)
        return CGFloat(count) * OverviewTagMetrics.actionDiameter + CGFloat(max(0, count - 1)) * OverviewTagMetrics.spacing
    }

    private var actions: some View {
        // Match the layout gap so surfaces morph together during transitions
        // while retaining separate outlines at rest.
        GlassEffectContainer(spacing: OverviewTagMetrics.spacing) {
            HStack(spacing: OverviewTagMetrics.spacing) {
                if let onRestart { iconButton("RotateCcw", size: 15, title: strings.restart, action: onRestart) }
                if onSettings != nil || onSettingsWithOrigin != nil {
                    iconButton("Settings", size: 15, title: strings.settings,
                               settingsAnchor: settingsAnchor, onSettingsFrameChange: onSettingsFrameChange) {
                        if let rect = settingsAnchor.frame, let onSettingsWithOrigin { onSettingsWithOrigin(rect) }
                        else { onSettings?() }
                    }
                }
            }
            .frame(width: actionWidth, alignment: .trailing)
        }
        .modifier(OverviewToolbarEntry())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(strings.actions)
    }

    private func filtersBar(maximumWidth: CGFloat) -> some View {
        filterButtons(maximumWidth: maximumWidth)
            .clipShape(Capsule())
            .overlayPreferenceValue(OverviewTagBounds.self) { anchors in
                GeometryReader { reader in
                    if selectedTag.isEmpty, let all = anchors["__all__"] {
                        OverviewSelectionOutline(bounds: reader[all])
                    }
                    if let scroll = anchors["__scroll__"] {
                        let viewport = reader[scroll]
                        directoryDecorations(presentedFilters, anchors: anchors, reader: reader, viewport: viewport)
                        ForEach(presentedFilters) { filter in
                            if let anchor = anchors[filter.id], reader[anchor].intersects(viewport) {
                                Color.clear.frame(width: 0, height: 0)
                                    .modifier(NativeOverviewButtonRegistration(registry: interactions,
                                        group: .directory, id: filter.id, action: { onTagChange(filter) }))
                            }
                        }
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .modifier(OverviewToolbarEntry())
            .accessibilityElement(children: .contain)
            .accessibilityLabel(strings.filter)
    }

    // Draw the selection and unread ink after the glass pass and clip both at the scroll viewport.
    private func directoryDecorations(_ filters: [NativeOverviewFilter], anchors: [String: Anchor<CGRect>],
                                      reader: GeometryProxy, viewport: CGRect) -> some View {
        let clip = viewport.insetBy(dx: 0, dy: -4)
        return ZStack(alignment: .topLeading) {
            ForEach(filters) { filter in
                let count = filter.unreadCount
                let chip = anchors[filter.id].map { reader[$0] } ?? .zero
                let visible = count > 0 && !chip.isEmpty
                if isActive(filter), !chip.isEmpty {
                    OverviewSelectionOutline(bounds: chip.offsetBy(dx: -clip.minX, dy: -clip.minY))
                }
                ZStack {
                    if visible {
                        OverviewTagUnreadBadge(count: count)
                            .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity),
                                                    removal: .identity))
                    }
                }
                .animation(visible ? tagEntryAnimation : nil, value: visible)
                .frame(width: chip.width, height: chip.height, alignment: .topTrailing)
                .position(x: chip.midX - clip.minX, y: chip.midY - clip.minY)
            }
        }
        .frame(width: clip.width, height: clip.height, alignment: .topLeading)
        .clipped()
        .position(x: clip.midX, y: clip.midY)
    }

    private func isActive(_ filter: NativeOverviewFilter) -> Bool {
        (filter.isDirectory && selectedKind == .semantic && !selectedTag.isEmpty && selectedScope == filter.scope)
            || (!selectedTag.isEmpty && filter.matches(selectedTag, kind: selectedKind, scope: selectedScope))
    }

    private var tagEntryAnimation: Animation? { reduceMotion ? nil : .smooth(duration: 0.22, extraBounce: 0) }

    private func filterButtons(maximumWidth: CGFloat) -> some View {
        HStack(spacing: OverviewTagMetrics.spacing) {
            Button {
                onTagChange(nil)
            } label: {
                HStack(spacing: OverviewTagMetrics.chipContentSpacing) {
                    OverviewTagTitle(title: strings.all)
                }
                .padding(.horizontal, OverviewTagMetrics.chipLabelInset)
                .frame(height: OverviewTagMetrics.chipHeight)
            }
            .buttonStyle(OverviewTagButtonStyle())
            .overviewTagAnchor("__all__")
            .accessibilityIdentifier("overview-directory-all")
            .modifier(NativeOverviewButtonRegistration(registry: interactions, group: .directory, id: "all", action: { onTagChange(nil) }))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measuredAllWidth = $0 }
            .accessibilityAddTraits(selectedTag.isEmpty ? .isSelected : [])
            .accessibilityValue(Text(allHasActiveTasks ? strings.containsActiveTasks : ""))
            OverviewHorizontalScroll(interactions: interactions, owner: interactionOwner, ids: presentedFilters.map(\.id)) {
                // Keep the effect container inside the scroll viewport. A
                // container outside it can draw captured labels beyond its clip.
                GlassEffectContainer(spacing: OverviewTagMetrics.spacing) {
                    scrollingTagButtons(maximumButtonWidth: max(0, maximumWidth - measuredAllWidth
                        - OverviewTagMetrics.barInset * 2 - OverviewTagMetrics.spacing))
                }
            }
            .frame(height: OverviewTagMetrics.chipHeight)
            .overviewTagAnchor("__scroll__")
        }
        .padding(.horizontal, OverviewTagMetrics.barInset)
    }

    private func scrollingTagButtons(maximumButtonWidth: CGFloat) -> some View {
        HStack(spacing: OverviewTagMetrics.spacing) {
            ForEach(presentedFilters) { filter in
                let active = isActive(filter)
                let activitySuffix = filter.hasActiveTasks ? " · \(strings.containsActiveTasks)" : ""
                Button {
                    onTagChange(filter)
                } label: {
                    HStack(spacing: OverviewTagMetrics.chipContentSpacing) {
                        if filter.isDirectory || filter.emoji != nil {
                            OverviewTagPrefix(emoji: filter.isDirectory ? nil : filter.emoji)
                                .background {
                                    if filter.hasActiveTasks {
                                        OverviewTagActivityIndicator(diameter: 26)
                                    }
                                }
                        } else if filter.hasActiveTasks {
                            OverviewTagActivityIndicator(diameter: 26)
                        }
                        OverviewTagTitle(title: !filter.isDirectory && filter.emoji != nil ? filter.tag : filter.displayTag)
                    }
                    .padding(.horizontal, OverviewTagMetrics.chipLabelInset)
                    .frame(height: OverviewTagMetrics.chipHeight)
                    .frame(maxWidth: maximumButtonWidth)
                }
                .buttonStyle(OverviewTagButtonStyle())
                .glassEffectID(filter.id, in: tagGlass)
                .glassEffectTransition(.matchedGeometry)
                .overviewTagAnchor(filter.id)
                .accessibilityIdentifier(filter.id)
                .accessibilityLabel(Text(filter.displayTag))
                .accessibilityAddTraits(active ? .isSelected : [])
                .accessibilityValue(Text("\(filter.displayTag) · \(filter.count)\(activitySuffix)\(strings.unreadSuffix(filter.unreadCount))"))
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            // The scroll viewport is sized from this measurement in a later
            // update; carry the resize animation across that layout boundary.
            withAnimation(measuredTagsWidth == 0 || reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                measuredTagsWidth = width
            }
        }
    }

    private var naturalFilterWidth: CGFloat {
        measuredAllWidth > 0 && measuredTagsWidth > 0
            ? measuredAllWidth + measuredTagsWidth + OverviewTagMetrics.barInset * 2 + OverviewTagMetrics.spacing : 10000
    }

    private func iconButton(_ name: String, size: CGFloat = 16, title: String, active: Bool = false,
                            settingsAnchor: OverviewSettingsAnchor? = nil,
                            onSettingsFrameChange: ((CGRect?) -> Void)? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NativeIcon(name: name, size: size)
                .frame(width: OverviewTagMetrics.iconButtonSize, height: OverviewTagMetrics.iconButtonSize)
                .frame(width: OverviewTagMetrics.actionDiameter, height: OverviewTagMetrics.actionDiameter)
        }
        .buttonStyle(OverviewChromeIconStyle(active: active, settingsAnchor: settingsAnchor,
                                            onSettingsFrameChange: onSettingsFrameChange))
        .glassEffectID(name, in: actionGlass)
        .glassEffectTransition(.matchedGeometry)
        .help(title).accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func presentFilters(_ updated: [NativeOverviewFilter], animated: Bool) {
        // A local presentation transaction keeps card/camera/settings updates out
        // of this animation. Initial hydration is immediate.
        var transaction = Transaction(animation: animated ? .smooth(duration: 0.48, extraBounce: 0) : nil)
        transaction.disablesAnimations = !animated
        withTransaction(transaction) {
            presentedFilters = updated
            if !updated.isEmpty && !hasPresentedFilters { hasPresentedFilters = true }
        }
    }
}

struct OverviewTagUnreadBadge: View {
    let count: Int

    var body: some View {
        Text(verbatim: String(count))
            .font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 15)
            .background(Color(nsColor: .systemRed), in: Capsule())
            .fixedSize()
            .padding(.trailing, 5).offset(y: -3.5)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct OverviewTagTitle: View {
    let title: String
    var body: some View {
        Text(title)
            .font(NativeTypography.inter(size: OverviewTagMetrics.chipFont, weight: 620))
            .lineLimit(1)
            .truncationMode(.tail)
            .modifier(OverviewTagInk())
    }
}

// Clear glass can reveal a backdrop of either brightness in either appearance.
// The contrasting edge belongs only to monochrome ink, including the Any glyph.
struct OverviewTagInk: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let edge: Color = scheme == .dark ? .black : .white
        content
            .foregroundStyle(.primary)
            .shadow(color: edge.opacity(0.9), radius: 0.7, y: 0.5)
            .shadow(color: edge.opacity(0.8), radius: 1)
    }
}

struct OverviewTagPrefix: View {
    var emoji: String?
    var body: some View {
        Group {
            if let emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: OverviewTagMetrics.folderIcon))
            } else {
                NativeIcon(name: "Folder", size: OverviewTagMetrics.folderIcon)
                    .modifier(OverviewTagInk())
            }
        }
        .fixedSize()
        .frame(minWidth: OverviewTagMetrics.folderIcon)
        .accessibilityHidden(true)
    }
}

public struct NativeOverviewChromeStrings: Sendable {
    public var all = "全部"
    public var settings = "设置"
    public var restart = "重启开发应用"
    public var actions = "俯瞰视图操作"
    public var filter = "按标签筛选"
    public var anyTag = "不限标签"
    public var runningOnly = "仅运行中"
    public var allStatuses = "全部状态"
    public var completedOnly = "仅已完成"
    public var statusFilter = "按状态筛选"
    public var containsActiveTasks = "包含活跃任务"
    public var unread = "条未读"
    func unreadSuffix(_ count: Int) -> String {
        count > 0 ? " · \(count) \(unread)" : ""
    }
    public init() {}
}

/// Noninteractive empty-state guidance for the current Overview filter.
public struct NativeOverviewEmptyState: View {
    public var title: String
    public var detail: String
    public init(title: String = "还没有会话", detail: String = "切换视图或标签筛选以查看其他 Thread。") {
        self.title = title; self.detail = detail
    }
    public var body: some View {
        VStack(spacing: 5) {
            Text(title).font(NativeTypography.inter(size: 14, weight: 590))
            Text(detail).font(NativeTypography.inter(size: 12))
        }
        .foregroundStyle(NativePalette.overview.ink.swiftUI)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(NativePalette.overview.surface.swiftUI, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

public struct NativeOverviewAttentionIndicator: View {
    public var text: String
    public init(text: String) { self.text = text }
    public var body: some View {
        HStack(spacing: 6) {
            NativeIcon(name: "CircleAlert", size: 13)
            Text(text).font(NativeTypography.inter(size: 12, weight: 620))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .foregroundStyle(NativePalette.overview.ink.swiftUI)
        .background(NativePalette.overview.surfaceSoft.swiftUI, in: Capsule())
        .overlay(Capsule().stroke(NativePalette.overview.line.swiftUI, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 13, y: 10)
        .allowsHitTesting(false)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

enum OverviewTagMetrics {
    static func selectionTintOpacity(contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? 0.34 : 0.22
    }
    static let iconButtonSize: CGFloat = 30
    static let barInset: CGFloat = 6
    static let labelInset: CGFloat = 12
    static let spacing: CGFloat = 4
    static let railSpacing: CGFloat = 10
    /// Enlarge tag ink while keeping all top-level chrome at the same height.
    static let enlargement: CGFloat = 1.1
    static let chipScale: CGFloat = 1.125 * enlargement
    static let chipFont = 10.5 * chipScale
    static let folderIcon = 11 * chipScale
    static let chipContentSpacing = 6 * chipScale
    static let chipLabelInset = labelInset * chipScale
    static let chipHeight = NativeWindowNavigationGeometry.height
    /// Tag filters, traffic-light capsules and circular actions share one height.
    static let actionDiameter = NativeWindowNavigationGeometry.height
    static let barHeight = chipHeight
    static let singleRowTop: CGFloat = 16
    static let compactActionTop: CGFloat = 10
    private static let preferredStackedFilterTop: CGFloat = 76
    private static let headerClearance: CGFloat = 2
    private static let minimumCanvasStrip: CGFloat = 8

    /// Keep the preferred filter position when there is room for both rows and canvas input.
    static func stackedFilterTop(viewportHeight: CGFloat) -> CGFloat {
        let latestTop = viewportHeight - chipHeight - headerClearance - minimumCanvasStrip
        return max(compactActionTop + actionDiameter, min(preferredStackedFilterTop, latestTop))
    }
    static func stacksFilters(in width: CGFloat) -> Bool {
        width <= CGFloat(NativeOverviewCameraGeometry.compactViewportWidth)
    }

    static func headerBottom(in size: CGSize, hasFilters: Bool) -> CGFloat {
        guard hasFilters, stacksFilters(in: size.width) else { return singleRowTop + chipHeight + headerClearance }
        return stackedFilterTop(viewportHeight: size.height) + chipHeight + headerClearance
    }
    /// Persistent header extents reported by the workspace visibility probe.
    static let wideToolbarClearance = 18 + chipHeight
    static let narrowToolbarClearance: CGFloat = 120
}

struct OverviewTagButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if reduceTransparency { Capsule().fill(Color(white: scheme == .dark ? 0.16 : 0.94)) }
            }
            .contentShape(Capsule())
            .glassEffect(.clear.interactive(), in: Capsule())
    }
}

/// GlassEffectContainer composites its surfaces above their contents. Draw
/// the selected chip's outline in the container overlay at its presented bounds.
struct OverviewSelectionOutline: View {
    let bounds: CGRect
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Capsule().strokeBorder(NativePalette.overview.accent.swiftUI, lineWidth: contrast == .increased ? 3 : 2)
            .frame(width: bounds.width, height: bounds.height)
            .position(x: bounds.midX, y: bounds.midY)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Settings and restart keep a frosted face beneath their interactive glass.
private struct OverviewActionGlassSurface<S: Shape>: ViewModifier {
    let active: Bool
    let shape: S
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content
            .foregroundStyle(scheme == .dark ? .white : NativePalette.overview.ink.swiftUI)
            .background {
                if reduceTransparency {
                    shape.fill(Color(white: scheme == .dark ? 0.16 : 0.94))
                } else {
                    shape.fill(.thinMaterial)
                }
            }
            .contentShape(shape)
            .glassEffect(.clear.tint(active ? selectionTint : nil).interactive(), in: shape)
            .animation(.easeInOut(duration: 0.18), value: active)
    }

    private var selectionTint: Color {
        NativePalette.overview.accent.swiftUI
            .opacity(OverviewTagMetrics.selectionTintOpacity(contrast: contrast))
    }
}

private struct OverviewChromeIconStyle: ButtonStyle {
    let active: Bool
    var settingsAnchor: OverviewSettingsAnchor?
    var onSettingsFrameChange: ((CGRect?) -> Void)?
    func makeBody(configuration: Configuration) -> some View {
        OverviewChromeIconBody(configuration: configuration, active: active,
                               settingsAnchor: settingsAnchor, onSettingsFrameChange: onSettingsFrameChange)
    }
}

private struct OverviewChromeIconBody: View {
    let configuration: ButtonStyleConfiguration
    let active: Bool
    var settingsAnchor: OverviewSettingsAnchor?
    var onSettingsFrameChange: ((CGRect?) -> Void)?
    var body: some View {
        configuration.label.modifier(OverviewActionGlassSurface(active: active, shape: Capsule()))
            .background {
                if let settingsAnchor {
                    OverviewSettingsFrameReader(anchor: settingsAnchor, onChange: onSettingsFrameChange)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

/// The top-level bar retains its scroll identity through filter revisions.
private struct OverviewHorizontalScroll<Content: View>: View {
    let interactions: NativeOverviewChromeInteractions?
    let owner: UUID
    let ids: [String]
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollViewReader { proxy in
            NativeScrollView(.horizontal) {
                content()
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .modifier(NativeOverviewFilterScrollRegistration(registry: interactions, root: owner, ids: ids, enabled: true,
                scroll: { id in proxy.scrollTo(id, anchor: .center) }))
        }
    }
}

@MainActor private final class OverviewSettingsAnchor {
    var frame: CGRect?
}

private struct OverviewSettingsFrameReader: View {
    let anchor: OverviewSettingsAnchor
    var onChange: ((CGRect?) -> Void)?
    var body: some View {
        Color.clear
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("workspace")) } action: { frame in
                anchor.frame = frame
                onChange?(frame)
            }
            .onDisappear { anchor.frame = nil; onChange?(nil) }
            .allowsHitTesting(false)
    }
}

private struct OverviewToolbarEntry: ViewModifier {
    @State private var entered = false
    func body(content: Content) -> some View {
        content.opacity(entered ? 1 : 0).offset(y: entered ? 0 : -6).scaleEffect(entered ? 1 : 0.98)
            .onAppear {
                withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.32)) { entered = true }
            }
    }
}
