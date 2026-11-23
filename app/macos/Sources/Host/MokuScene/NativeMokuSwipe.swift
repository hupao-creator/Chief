import AppKit
import SwiftUI

/// The workspace supplies the user entry point to its Overview scroll router.
struct NativeOverviewNoteAction {
    let available: @MainActor () -> Bool
    let open: @MainActor () -> Void
}

extension EnvironmentValues {
    @Entry var overviewNoteAction: NativeOverviewNoteAction? = nil
}

/// Reserve upward travel before it moves the camera or a native scroller.
/// Once another direction takes the gesture, leave its reversal and inertia
/// with that owner. Only a fresh contact can open the Note again.
struct NativeMokuSwipeSequence {
    private enum Stage { case idle, possible, opened, awaitingMomentum(TimeInterval), momentum }
    private var stage = Stage.idle
    private var upward: CGFloat = 0
    private var horizontal: CGFloat = 0

    @MainActor mutating func route(_ event: NSEvent, eligible: @autoclosure () -> Bool, open: () -> Void) -> Bool {
        let phase = event.phase
        if !event.momentumPhase.isEmpty {
            if case .awaitingMomentum(let end) = stage, event.timestamp - end > 0.25 { stage = .idle }
            switch stage {
            case .awaitingMomentum, .opened, .momentum:
                stage = event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) ? .idle : .momentum
                return true
            default:
                stage = .idle
                return false
            }
        }
        if phase.contains(.began) || phase.contains(.mayBegin) {
            stage = .possible
            upward = 0
            horizontal = 0
        }
        let reserved: Bool
        switch stage {
        case .opened: reserved = true
        case .possible: reserved = upward > 0
        default: reserved = false
        }
        if phase.contains(.ended) {
            stage = reserved ? .awaitingMomentum(event.timestamp) : .idle
            return reserved
        }
        if phase.isEmpty || phase.contains(.cancelled) {
            stage = .idle
            return !phase.isEmpty && reserved
        }
        if case .opened = stage { return true }
        guard case .possible = stage, event.hasPreciseScrollingDeltas, eligible() else {
            stage = .idle
            return false
        }
        if phase.contains(.mayBegin) { return false }
        upward += event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        horizontal += abs(event.scrollingDeltaX)
        if upward == 0 && horizontal == 0 { return false }
        guard upward > horizontal * 1.5 else {
            stage = .idle
            return false
        }
        if upward >= 24 {
            stage = .opened
            open()
        }
        return true
    }
}
