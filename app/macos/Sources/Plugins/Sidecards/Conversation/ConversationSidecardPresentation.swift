import Foundation
import Observation
import ChiefCore
import ChiefPluginAPI

/// One execution display per Thread/plugin session. It owns no input draft or
/// send capability; folding retains the Harness's mounted response forms.
@MainActor @Observable
public final class ConversationSidecardPresentation {
    public private(set) var context: SidecardContext
    private let executionState = ConversationExecutionState()
    private let lifetime: PluginLifetime
    @ObservationIgnored private var revealID: UUID?
    private struct Pending {
        let selection: Int
        let target: HarnessReadingTarget?
        let restore: (Int) -> Void
    }
    private var pending: Pending?
    @ObservationIgnored private var entered = false
    @ObservationIgnored private var entryTarget: HarnessReadingTarget?
    @ObservationIgnored private var entryExecution: JSONText?
    @ObservationIgnored private var entrySelection = 0

    public init(context: SidecardContext, lifetime: PluginLifetime) {
        self.context = context
        self.lifetime = lifetime
        update(context: context)
    }

    public var activeExecutionID: JSONText? { executionState.activeExecutionID(thread: context.thread) }
    public var pendingExecution: Bool { pending != nil }
    public var retainedMainExecutionID: JSONText? {
        guard !context.executionDisabled, context.executionHandoff == nil,
              let request = context.executionReveal, let source = request.previousExecutionID else { return nil }
        // Folding changes visibility. The source still owns main until the
        // receipt and observed conversation agree on where its successor belongs.
        guard let accepted = request.receipt?.executionID else { return activeExecutionID == source ? nil : source }
        guard accepted != source else { return nil }
        return sidecardExecutionID == accepted || !belongsInMain(accepted) ? source : nil
    }
    public var sidecardExecutionID: JSONText? {
        if let handoff = context.executionHandoff { return handoff }
        let active = executionState.sidecardExecutionID(thread: context.thread, index: context.conversationIndex)
        if pending != nil, let request = context.executionReveal {
            // Keep an already-running conversation readable. A new catalog row
            // alone cannot identify which execution accepted this input.
            let expected = request.receipt?.executionID ?? request.previousExecutionID
            return active == expected ? active : nil
        }
        return active
    }
    public var waiting: Bool { context.thread.observation.latestExecution?.status == .waitingForUser }

    public func update(context: SidecardContext) {
        guard !lifetime.isCancelled else { return }
        self.context = context
        let continuing = context.executionReveal?.continues(to: context.readingTarget) == true
        if !entered || entryTarget != context.readingTarget {
            entered = true; entryTarget = context.readingTarget
            // The local send already chose a card. Binding its exact result
            // must respect a fold or another card selected during admission.
            entryExecution = continuing ? nil : context.readingTarget?.executionID ?? activeExecutionID
            entrySelection = context.selectionRevision()
        }
        if let request = context.executionReveal, request.id != revealID {
            revealID = request.id
            entryExecution = nil
            // A second send can replace one whose receipt is still waiting for
            // the catalog. Keep the original rollback while we own its opening.
            let ownsOpening = pending?.selection == context.selectionRevision() && pending?.target == context.readingTarget
            // The first active execution already has its reader in main. Keep
            // it visible instead of opening an empty column for the same run.
            let staysInMain = activeExecutionID != nil && activeExecutionID == request.previousExecutionID &&
                executionState.sidecardExecutionID(thread: context.thread, index: context.conversationIndex) == nil
            if staysInMain {
                self.pending = nil
            } else if !context.executionDisabled, !ownsOpening {
                pending = Pending(selection: context.open(), target: context.readingTarget, restore: context.restoreSelection)
            }
        }
        if let pending {
            guard pending.selection == context.selectionRevision() else {
                self.pending = nil
                return
            }
            guard let request = context.executionReveal,
                  pending.target == context.readingTarget || continuing, !context.executionDisabled else {
                self.pending = nil
                pending.restore(pending.selection)
                return
            }
            guard let accepted = request.receipt?.executionID else { return }
            if sidecardExecutionID == accepted, activeExecutionID == accepted {
                self.pending = nil
                return
            }
            guard belongsInMain(accepted) else { return }
            self.pending = nil
            pending.restore(pending.selection)
            return
        }
        if context.executionHandoff == nil {
            executionState.update(thread: context.thread, index: context.conversationIndex,
                                  expanded: context.expanded, close: context.close)
        }
        if let execution = entryExecution {
            if context.selectionRevision() != entrySelection || context.executionDisabled {
                entryExecution = nil
            } else if sidecardExecutionID == execution {
                entryExecution = nil
                _ = context.open()
            } else if context.thread.observation.latestExecution?.executionID == execution, activeExecutionID == nil {
                entryExecution = nil
            }
        }
    }

    private func belongsInMain(_ accepted: JSONText) -> Bool {
        guard let latest = context.thread.observation.latestExecution?.executionID else { return false }
        if latest == accepted {
            // An active first run stays in main once the index identifies it.
            return activeExecutionID == nil || context.conversationIndex?.executionIDs.contains(accepted) == true
        }
        // Catalog delivery can skip a short accepted run. Only an ordered
        // history containing its successor distinguishes that from catalog lag.
        return context.conversationIndex?.contains(latest, after: accepted) == true
    }
}
