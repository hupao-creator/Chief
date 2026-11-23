import ChiefPluginAPI

extension HarnessThread {
    var isOrdinaryAgent: Bool { moku != true && !mokuHistory }

    func canOpenReader(at target: HarnessReadingTarget?) -> Bool {
        isOrdinaryAgent && (target?.position.pinsExecution == true || !isHiddenFromUser)
    }

    /// Presentation only: keep the complete catalog and Moku's access intact.
    /// A successor execution makes the thread eligible for display again.
    var isHiddenFromUser: Bool {
        guard isOrdinaryAgent else { return true }
        switch observation.latestExecution?.status {
        case .failed: return true
        case .interrupted:
            return mokuInterruptedExecutionID == observation.latestExecution?.executionID
        default: return false
        }
    }
}
