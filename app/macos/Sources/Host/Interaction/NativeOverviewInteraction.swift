import Foundation
import ChiefCore
import ChiefPluginAPI
import SwiftUI

/// Registrations are owned by mounted controls. A retiring control cannot remove
/// a replacement that has already registered the same ID.
@MainActor
public final class NativeOverviewChromeInteractions {
    private struct Button {
        let owner: UUID
        let activate: () -> Void
    }
    private var buttons: [NativeOverviewControlGroup: [String: Button]] = [:]
    private var scrolls: [UUID: (owner: UUID, ids: [String], enabled: Bool, action: (String) -> Void)] = [:]
    private var chromeOwner: UUID?

    func install(_ group: NativeOverviewControlGroup, id: String, owner: UUID, activate: @escaping () -> Void) {
        buttons[group, default: [:]][id] = Button(owner: owner, activate: activate)
    }
    func remove(_ group: NativeOverviewControlGroup, id: String, owner: UUID) {
        if buttons[group]?[id]?.owner == owner { buttons[group]?.removeValue(forKey: id) }
    }
    public func mountedIDs(in group: NativeOverviewControlGroup) -> [String] {
        buttons[group]?.keys.sorted() ?? []
    }
    public func activate(_ group: NativeOverviewControlGroup, id: String) throws {
        guard let button = buttons[group]?[id] else {
            throw NativeInteractionError("unavailable", "Filter control is not mounted and enabled")
        }
        button.activate()
    }
    var hasButtons: Bool { buttons.values.contains { !$0.isEmpty } }

    func installChrome(owner: UUID) { chromeOwner = owner }
    func removeChrome(owner: UUID) {
        scrolls.removeValue(forKey: owner)
        if chromeOwner == owner { chromeOwner = nil }
    }
    func installScroll(owner: UUID, root: UUID, ids: [String], enabled: Bool, action: @escaping (String) -> Void) {
        scrolls[root] = (owner, ids, enabled, action)
    }
    func removeScroll(owner: UUID, root: UUID) { if scrolls[root]?.owner == owner { scrolls.removeValue(forKey: root) } }
    var canScroll: Bool { chromeOwner.flatMap { scrolls[$0] }?.enabled == true }
    func scrollTo(_ id: String) throws {
        guard let root = chromeOwner, let scroll = scrolls[root], scroll.enabled else { throw NativeInteractionError("unavailable", "Filter bar is not mounted and enabled") }
        guard scroll.ids.contains(id) else { throw NativeInteractionError("not_found", "Top-level filter is unavailable") }
        scroll.action(id)
    }
}

struct NativeOverviewFilterScrollRegistration: ViewModifier {
    let registry: NativeOverviewChromeInteractions?
    let root: UUID
    let ids: [String]
    let enabled: Bool
    let scroll: (String) -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var owner = UUID()
    func body(content: Content) -> some View {
        content.onAppear(perform: install)
            .onChange(of: ids) { _, _ in install() }
            .onChange(of: enabled && isEnabled) { _, _ in install() }
            .onDisappear { registry?.removeScroll(owner: owner, root: root) }
    }
    private func install() { registry?.installScroll(owner: owner, root: root, ids: ids, enabled: enabled && isEnabled, action: scroll) }
}

struct NativeOverviewButtonRegistration: ViewModifier {
    let registry: NativeOverviewChromeInteractions?
    let group: NativeOverviewControlGroup
    let id: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    func body(content: Content) -> some View {
        content.background {
            if let registry, enabled {
                MountedButton(registry: registry, group: group, id: id, action: action)
                    .id(id).id(group).id(ObjectIdentifier(registry))
            }
        }
    }

    // Keep the registration token inside the identified lifetime. Retiring and
    // incoming controls can briefly occupy the same “Any tag” layout slot.
    private struct MountedButton: View {
        let registry: NativeOverviewChromeInteractions
        let group: NativeOverviewControlGroup
        let id: String
        let action: () -> Void
        @State private var owner = UUID()

        var body: some View {
            Color.clear.frame(width: 0, height: 0)
                .allowsHitTesting(false).accessibilityHidden(true)
                .onAppear { registry.install(group, id: id, owner: owner, activate: action) }
                .onDisappear { registry.remove(group, id: id, owner: owner) }
        }
    }
}

@MainActor
extension NativeWorkspacePresentation {
    var overviewInteractionActions: [String] {
        var result: [String] = []
        if interactionPage == "overview" {
            if !scene.interactionPaused, canvas.canScroll { result.append("overview.scroll") }
            if overview.error != nil || canvas.layoutError != nil { result.append("overview.retry") }
            if overview.chromeInteractions.hasButtons { result.append("overview.filters.activate") }
            if overview.chromeInteractions.canScroll { result.append("overview.filters.scroll") }
            if canToggleMokuNote { result.append("moku.note.toggle") }
        }
        if scene.dockRouteVisible, !scene.disabled, !scene.dockCovered { result.append("moku.input.toggle") }
        return result
    }

    func overviewInteractionSnapshot() -> JSONValue {
        func filter(_ item: NativeOverviewFilter) -> JSONValue {
            .object(["id": .text(item.id), "label": .text(item.displayTag), "tag": .text(item.tag),
                "kind": .text(item.isDirectory ? "directory" : "semantic"), "scope": .text(item.scope),
                "count": .integer(item.count), "unreadCount": .integer(item.unreadCount), "aliases": .array(item.aliases.map(JSONValue.text)),
                "children": .array(item.children.filter { $0.count > 0 }.map(filter))])
        }
        let camera = canvas.camera
        let transform = camera.transform
        let viewport: JSONValue = camera.viewport.map {
            .object(["width": .number($0.width), "height": .number($0.height),
                     "toolbarBottom": .number($0.toolbarBottom), "bottomReservedHeight": .number($0.bottomReservedHeight)])
        } ?? .null
        let cameraState: JSONValue = .object([
            "initialized": .bool(camera.isInitialized), "viewport": viewport,
            "scale": .number(transform.scale), "x": .number(transform.x), "y": .number(transform.y),
            "scrollOffset": .number(camera.scrollOffset), "maximumOffset": .number(camera.maximumOffset),
            "interactionPauseReasons": .array(canvas.interactionPauseReasons.map(JSONValue.text))
        ])
        let placements: [JSONValue] = canvas.presentedPlacements.map {
            .object(["id": .text($0.id), "column": .integer($0.column), "row": .integer($0.row),
                     "columns": .integer($0.columns), "rows": .integer($0.rows)])
        }
        let cards: [JSONValue] = overview.items.map { item in
            var value: [JSONText: JSONValue] = ["id": .text(item.id), "columns": .integer(item.columns),
                "rows": .integer(item.rows), "activatable": .bool(canvas.allowsActivation(cardID: item.id))]
            switch overview.snapshot(for: item) {
            case .harness(let snapshot):
                let thread = snapshot.input.thread
                value["ref"] = ApplicationThreadRef(threadID: thread.id, typeID: "agent").json
                value["title"] = .string(thread.title)
                value["cwd"] = .string(thread.cwd)
                value["scope"] = .string(thread.directoryScope)
                value["directoryLabel"] = .string(thread.directoryTag)
                value["tags"] = .array(thread.tags.map(JSONValue.string))
            case .application(_, let snapshot):
                value["ref"] = snapshot.entry.ref.json
                value["title"] = .string(snapshot.entry.title)
                value["collectionEligibility"] = overview.collectionEligibility(snapshot.entry.ref)
            case .collection(_, let members):
                value["members"] = .array(members.map { $0.entry.ref.json })
                value["memberEligibility"] = .array(members.map { member in
                    .object(["ref": member.entry.ref.json,
                             "eligibility": overview.collectionEligibility(member.entry.ref) ?? .null])
                })
                if let selected = overview.selectedCollectionMember(for: item),
                   let member = members.first(where: { $0.entry.ref == selected }) {
                    value["ref"] = selected.json
                    value["title"] = .string(member.entry.title)
                }
            case nil: break
            }
            return .object(value)
        }
        return .object([
            "sceneKey": .text(overview.sceneKey), "layingOut": .bool(canvas.isLayingOut),
            "stage": canvas.motionStages.activeOwner.map(JSONValue.text) ?? .null,
            "filters": .array(overview.visibleFilters.map(filter)), "cards": .array(cards),
            "mountedCardIds": .array(canvas.mountedCardIDs.sorted().map(JSONValue.text)),
            "placements": .array(placements), "camera": cameraState,
            "controls": .object(Dictionary(uniqueKeysWithValues: NativeOverviewControlGroup.allCases.map { group in
                (JSONText(group.rawValue), .array(overview.chromeInteractions.mountedIDs(in: group).map(JSONValue.text)))
            })),
            "status": .text(overview.statusFilter.rawValue),
            "dock": .object(["inputOpen": .bool(scene.inputOpen), "inputLeaving": .bool(scene.inputLeaving),
                "noteExecutionPhase": scene.noteReadingOrigin.map { .text($0.phase.rawValue) } ?? .null,
                "noteOpen": .bool(scene.notePanelOpen), "covered": .bool(scene.dockCovered)])
        ])
    }

    func performOverviewInteraction(_ action: NativeWorkspaceAction) throws {
        switch action {
        case .overviewScroll(let distance): canvas.camera.scroll(by: distance)
        case .overviewRetry: overview.refresh(); canvas.retryLayout()
        case .overviewActivateFilter(let group, let id): try overview.chromeInteractions.activate(group, id: id)
        case .overviewScrollFilter(let id): try overview.chromeInteractions.scrollTo(id)
        case .toggleMokuInput: scene.toggleInput(focusOnOpening: true)
        case .toggleMokuNote: toggleMokuNote()
        default: throw NativeInteractionError("invalid_request", "Not an Overview action")
        }
    }
}
