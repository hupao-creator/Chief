import AppKit
import ChiefPluginUI
import SwiftUI

@MainActor final class NativeOverviewSwipeRegions {
    let bar = NativeCanvasInputRegions()
    let controls = NativeCanvasInputRegions()
}

struct NativeOverviewSwipeActions {
    let regions: NativeOverviewSwipeRegions
    let available: @MainActor () -> Bool
    let canFilter: @MainActor () -> Bool
    let canReturnWithWheel: @MainActor (Bool) -> Bool
    let openNoteFromBar: @MainActor () -> Bool
    let stepSemanticFilter: @MainActor (Bool) -> Void
    let stepStatusFilter: @MainActor (Bool) -> Void
}

extension EnvironmentValues {
    @Entry var overviewSwipeActions: NativeOverviewSwipeActions? = nil
}

/// Classify the starting surface before native scrolling. After recognition,
/// keep the rest of the contact and its momentum even if the surface changes.
struct NativeOverviewVerticalSwipe {
    enum Target {
        case semanticFilter, statusFilter
    }
    private enum Stage { case idle, possible(Target), claimed, awaitingMomentum(TimeInterval), momentum }
    private var stage = Stage.idle
    private var vertical: CGFloat = 0
    private var horizontal: CGFloat = 0

    @MainActor mutating func route(_ event: NSEvent, target: () -> Target?,
                                  canReturnWithWheel: (Bool) -> Bool, perform: (Target, Bool) -> Void) -> Bool {
        let phase = event.phase
        if !event.momentumPhase.isEmpty {
            if case .awaitingMomentum(let end) = stage, event.timestamp - end > 0.25 { stage = .idle }
            switch stage {
            case .awaitingMomentum, .claimed, .momentum:
                stage = event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) ? .idle : .momentum
                return true
            default:
                stage = .idle
                return false
            }
        }
        let deltaY = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        if phase.isEmpty && !event.hasPreciseScrollingDeltas {
            stage = .idle
            let up = deltaY > 0
            guard abs(deltaY) > abs(event.scrollingDeltaX) * 1.5, canReturnWithWheel(up),
                  target() == .statusFilter else { return false }
            perform(.statusFilter, up)
            return true
        }
        let starting = phase.contains(.began) || phase.contains(.mayBegin)
        if starting {
            stage = event.hasPreciseScrollingDeltas ? target().map(Stage.possible) ?? .idle : .idle
            vertical = 0
            horizontal = 0
        }
        let reserved: Bool = switch stage {
        case .claimed: true
        case .possible: vertical != 0
        default: false
        }
        if phase.contains(.ended) {
            stage = reserved ? .awaitingMomentum(event.timestamp) : .idle
            return reserved
        }
        if phase.isEmpty || phase.contains(.cancelled) {
            stage = .idle
            return !phase.isEmpty && reserved
        }
        if case .claimed = stage { return true }
        // Both halves are one filtering surface. Keep the half captured at
        // contact start even if the pointer crosses the midpoint before recognition.
        guard case .possible(let origin) = stage, starting || target() != nil else {
            stage = .idle
            return false
        }
        if phase.contains(.mayBegin) { return false }
        vertical += deltaY
        horizontal += abs(event.scrollingDeltaX)
        if vertical == 0 && horizontal == 0 { return false }
        guard abs(vertical) > horizontal * 1.5 else {
            stage = .idle
            return false
        }
        if abs(vertical) >= 24 {
            stage = .claimed
            perform(origin, vertical > 0)
        }
        return true
    }
}
