import Foundation

/// Groups arrive in product type order. Each ranked prefix occupies the seat of
/// its first member in the complete, creation-ordered filter projection.
struct NativeOverviewCollectionBudget {
    let card: NativeOverviewMember
    let rankedIDs: [String]
    let idleCount: Int

    static func memberCounts(in members: [NativeOverviewMember], groups: [Self], windowSize: CGSize?) throws -> [Int] {
        var counts = groups.map { $0.idleCount >= 2 ? $0.idleCount : 0 }
        guard let windowSize, groups.indices.contains(where: {
            groups[$0].rankedIDs.count >= max(2, counts[$0] + 1)
        }) else { return counts }

        func layout() throws -> NativeOverviewGeometry {
            var replacements: [String: NativeOverviewMember] = [:]
            for (group, count) in zip(groups, counts) {
                for id in group.rankedIDs.prefix(count) { replacements[id] = group.card }
            }
            var placed = Set<String>()
            let trial = members.compactMap { member -> NativeOverviewMember? in
                guard let card = replacements[member.id] else { return member }
                return placed.insert(card.id).inserted ? card : nil
            }
            return try NativeOverviewLayout.solve(members: trial, windowSize: windowSize)
        }

        // Only default-idle members are grouped on the first trial. A resize
        // always starts here, independently of the camera offset or last result.
        var leastTravel = try layout().maximumScrollOffset
        guard leastTravel > 0 else { return counts }
        let area = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.columns * $0.rows) })
        let metrics = NativeOverviewLayout.metrics
        let region = NativeOverviewCameraGeometry.framingRegion(.init(width: windowSize.width, height: windowSize.height))
        let tallest = max(members.map(\.rows).max()!, groups.map(\.card.rows).max()!)
        let rows = max(Double(tallest), floor((region.height + metrics.gap) / metrics.rowPitch))
        let minimumScale = min(1, region.height / metrics.height(rows: tallest))
        for index in groups.indices {
            let ids = groups[index].rankedIDs
            let minimum = max(2, counts[index] + 1)
            guard minimum <= ids.count else { continue }
            var best = (travel: leastTravel, count: counts[index])
            counts[index] = ids.count
            let folded = try layout()
            if folded.maximumScrollOffset < best.travel { best = (folded.maximumScrollOffset, ids.count) }

            // Even a gap-free packing must fit the card cells into these rows
            // and columns to match the better endpoint. Use the full window
            // width and round columns up so this only rules out impossible fits.
            let columns = ceil(((windowSize.width + best.travel) / minimumScale + metrics.gap) / metrics.columnPitch)
            var cells = folded.placements.reduce(0) { $0 + $1.columns * $1.rows }
            var first = ids.count
            while first > minimum {
                cells += area[ids[first - 1]]!
                if Double(cells) > rows * columns { break }
                first -= 1
            }
            for count in first..<ids.count {
                counts[index] = count
                let travel = try layout().maximumScrollOffset
                if (travel, count) < best { best = (travel, count) }
                if travel == 0 { break }
            }
            // Mixed spans can pack differently at every prefix. Equal travel
            // keeps the smaller group, including when scrolling is unavoidable.
            counts[index] = best.count
            leastTravel = best.travel
            if leastTravel == 0 { break }
        }
        return counts
    }
}
