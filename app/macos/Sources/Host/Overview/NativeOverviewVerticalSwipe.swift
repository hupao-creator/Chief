import AppKit
import ChiefPluginUI
import SwiftUI

@MainActor final class NativeOverviewSwipeRegions {
    let bar = NativeCanvasInputRegions()
    let controls = NativeCanvasInputRegions()
    weak var pressedTag: OverviewTagPointerPress.PressView?
}

struct NativeOverviewSwipeActions {
    let regions: NativeOverviewSwipeRegions
    let available: @MainActor () -> Bool
    let canFilter: @MainActor () -> Bool
    let openConversation: @MainActor () -> Bool
    let stepRail: @MainActor (Bool) -> Bool
}

extension EnvironmentValues {
    @Entry var overviewSwipeActions: NativeOverviewSwipeActions? = nil
}

/// Classify the starting surface before native scrolling. After recognition,
/// keep the rest of the contact and its momentum even if the surface changes.
struct NativeOverviewVerticalSwipe {
    private enum Stage { case idle, possible, claimed, awaitingMomentum(TimeInterval), momentum }
    private var stage = Stage.idle
    private var vertical: CGFloat = 0
    private var horizontal: CGFloat = 0

    @MainActor mutating func route(_ event: NSEvent, canFilter: () -> Bool,
                                  perform: (Bool) -> Bool, requestFeedback: () -> Void = {
                                      NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                                  }) -> Bool {
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
            guard abs(deltaY) > abs(event.scrollingDeltaX) * 1.5, canFilter() else { return false }
            _ = perform(up)
            return true
        }
        let starting = phase.contains(.began) || phase.contains(.mayBegin)
        if starting {
            stage = event.hasPreciseScrollingDeltas && canFilter() ? .possible : .idle
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
        guard case .possible = stage, canFilter() else {
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
            if perform(vertical > 0), event.hasPreciseScrollingDeltas { requestFeedback() }
        }
        return true
    }
}
