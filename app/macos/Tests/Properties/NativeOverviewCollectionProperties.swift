import Foundation
import Testing
import ChiefPluginAPI
@testable import ChiefUI

private struct CollectionCase: Codable {
    let seed: UInt64
    var fixedCards: Int
    var groups: [[Int]]
    let windowSize: CGSize

    init(seed: UInt64) {
        var random = SplitMix64(seed: seed)
        self.seed = seed
        fixedCards = random.integer(0...12)
        groups = (0..<random.integer(1...2)).map { _ in
            (0..<random.integer(0...10)).map { _ in random.integer(1...2) }
        }
        // Include the exact horizontal centering and vertical row boundaries.
        let delta = Double(Int(seed % 3) - 1) / 2
        windowSize = CGSize(width: Double(random.integer(1...7) * 336 + 16) + delta,
                            height: Double(random.integer(1...6) * 212 + 44) + delta)
    }

    func violation() throws -> String? {
        var random = SplitMix64(seed: seed)
        var cards = (0..<fixedCards).map { NativeOverviewMember(id: "task-\($0)",
            columns: random.integer(1...2), rows: random.integer(1...2)) }
        let plans = groups.enumerated().map { type, heights in
            let reports = heights.enumerated().map { NativeOverviewMember(id: "\(type)-\($0.offset)", columns: 1, rows: $0.element) }
            cards.append(contentsOf: reports)
            return NativeOverviewCollectionBudget(card: .init(id: "group-\(type)", columns: 1, rows: 2),
                rankedIDs: reports.map(\.id), idleCount: random.integer(0...reports.count))
        }
        cards.shuffle(using: &random)
        let actual = try NativeOverviewCollectionBudget.memberCounts(in: cards, groups: plans, windowSize: windowSize)
        var expected = plans.map { $0.idleCount >= 2 ? $0.idleCount : 0 }
        guard try NativeOverviewCollectionBudget.memberCounts(in: cards, groups: plans, windowSize: nil) == expected else {
            return "applied pressure before the window was measured"
        }
        for index in groups.indices {
            // Score every legal prefix against the shipping camera, independently
            // replacing the oldest product seat of each group in a copy of the grid.
            let options = try (expected[index]...groups[index].count).filter { $0 != 1 }.map { count in
                var counts = expected
                counts[index] = count
                var grid = cards
                for (plan, size) in zip(plans, counts) where size > 0 {
                    let ids = Set(plan.rankedIDs.prefix(size))
                    let seat = grid.firstIndex { ids.contains($0.id) }!
                    grid.removeAll { ids.contains($0.id) }
                    grid.insert(plan.card, at: seat)
                }
                let layout = try NativeOverviewLayout.solve(members: grid, windowSize: windowSize)
                return (travel: layout.maximumScrollOffset, count: count)
            }
            expected[index] = options.min { ($0.travel, $0.count) < ($1.travel, $1.count) }!.count
        }
        guard actual == expected else { return "selected \(actual) members, expected \(expected) at \(windowSize)" }
        // Split foreground reading across routes to the same owner, with paused
        // intervals between routes. The oracle only sums generated visible spans.
        let estimate = Double(random.integer(0...300))
        let threshold = max(5, min(45, estimate * 0.25))
        let now = 200_000.0
        let age = 1_800.0 + Double(Int(seed % 3) - 1)
        var evidence = ApplicationCollectionReading()
        var visit = NativeOverviewCollectionVisit(reference: .init(threadID: "report", typeID: "report.document"),
            openedAt: now, estimate: estimate, createdAt: now - age, evidence: &evidence)
        guard evidence.staysCollected == (age >= 1_800) else { return "incorrect unread age boundary" }
        let reading = max(0, threshold + Double(Int((seed / 3) % 3) - 1))
        visit.advance(visible: true, uptime: 0)
        visit.advance(visible: false, uptime: reading / 2)
        visit.advance(visible: true, uptime: 100)
        visit.advance(visible: false, uptime: 100 + reading / 2)
        guard visit.qualified == (reading >= threshold) else { return "foreground threshold or pause mismatch" }
        if visit.qualified { visit.promote(&evidence) }
        visit.close(at: now + 200, evidence: &evidence)
        let persistedIdle = evidence.isIdle(createdAt: 0, now: now + 201)
        guard persistedIdle == (age >= 1_800 && reading < threshold),
              (evidence.lastQualifiedAt != nil) == visit.qualified else { return "incorrect default on return" }
        let afterClose = evidence.isIdle(createdAt: 0, now: now + 200 + age)
        guard afterClose == (persistedIdle || age >= 1_800) else { return "incorrect age since close" }
        let revisitAge = 86_400.0 + Double(Int((seed / 9) % 3) - 1)
        let next = now + 200 + revisitAge
        var revisit = NativeOverviewCollectionVisit(reference: visit.reference, openedAt: next, estimate: estimate,
            createdAt: 0, evidence: &evidence)
        revisit.advance(visible: true, uptime: 500)
        guard !revisit.qualified else { return "unseen revisit qualified" }
        revisit.advance(visible: false, uptime: 501)
        guard revisit.qualified == (revisitAge < 86_400) else { return "incorrect short revisit window" }
        return nil
    }

    func reduced(within seconds: Int) throws -> Self {
        var best = self
        let deadline = ContinuousClock.now + .seconds(seconds)
        for index in groups.indices {
            for offset in groups[index].indices.reversed() {
                if ContinuousClock.now >= deadline { return best }
                var next = best
                next.groups[index].remove(at: offset)
                if try next.violation() != nil { best = next }
            }
        }
        for count in 0..<best.fixedCards {
            if ContinuousClock.now >= deadline { return best }
            var next = best
            next.fixedCards = count
            if try next.violation() != nil { return next }
        }
        return best
    }
}

@Suite(.serialized)
struct NativeOverviewCollectionProperties {
    @Test func oldestPrefixMinimizesOverflow() throws {
        let budget = try PropertyBudget(defaultCases: 480)
        let replay = try propertyReplay(CollectionCase.self)
        let inputs = replay.map { [$0] } ?? (0..<budget.cases).map { CollectionCase(seed: budget.seed &+ UInt64($0)) }
        for input in inputs {
            if let error = try input.violation() {
                try propertyEvidence(input, name: "original.json")
                let reduced = try input.reduced(within: budget.shrinkSeconds)
                try propertyEvidence(reduced, name: "reduced.json")
                Issue.record(Comment(rawValue: "PBT-OVERVIEW-COLLECTION seed=\(input.seed) \(error) reduced=\(reduced)"))
                return
            }
        }
        print("PBT PASS PBT-OVERVIEW-COLLECTION seed=\(budget.seed) cases=\(inputs.count) replay=\(replay != nil)")
    }
}
