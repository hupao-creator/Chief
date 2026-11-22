import Foundation
import Testing
import ChiefPluginAPI
@testable import ChiefUI

/// Independent layout contract. Every oracle below is computed from the input
/// and the published output; no expectation calls the production solver or its
/// fit helper.
private struct LayoutCase: Codable, Equatable {
    var seed: UInt64
    var members: [NativeOverviewMember]
    var usable: NativeOverviewContentRect
}

private let tolerance = 1e-9
private let metrics = NativeOverviewGridMetrics(columnWidth: 320, rowHeight: 196, gap: 16)

private func frame(of placement: NativeOverviewPlacement) -> CGRect {
    CGRect(x: Double(placement.column) * metrics.columnPitch,
           y: Double(placement.row) * metrics.rowPitch,
           width: metrics.width(columns: placement.columns),
           height: metrics.height(rows: placement.rows))
}

private func generate(seed: UInt64) -> LayoutCase {
    var random = SplitMix64(seed: seed)
    var members = [NativeOverviewMember]()
    if seed.isMultiple(of: 4) {
        // A six-tile rectangle with a known optimum, in different units and orders.
        let w = random.integer(1...3), h = random.integer(1...2)
        let spans = [(2 * w, h), (w, 2 * h), (w, h), (w, h)].shuffled(using: &random)
        members = spans.enumerated().map { index, span in
            .init(id: "card-\(index)", columns: span.0, rows: span.1)
        }
    } else {
        for index in 0..<random.integer(0...18) {
            members.append(.init(id: "card-\(index)",
                                 columns: random.integer(1...3), rows: random.integer(1...2)))
        }
    }
    let width = random.double(240...2600)
    let height = seed.isMultiple(of: 16) ? 60 : random.double(1...1600)
    let usable = NativeOverviewContentRect(left: random.double(-400...400),
                                           top: random.double(-200...200),
                                           width: width, height: height)
    return LayoutCase(seed: seed, members: members, usable: usable)
}

// At one row high the footprint widths determine the envelope independently
// of packing order. Exercise the window entry point on both sides of exact fit.
private func windowFitViolations(_ input: LayoutCase) throws -> [String] {
    let row = input.members.map { NativeOverviewMember(id: $0.id, columns: $0.columns, rows: 1) }
    guard !row.isEmpty else { return [] }
    let scale = input.seed.isMultiple(of: 2) ? 1.0 : 0.5
    let width = Double(row.reduce(0) { $0 + $1.columns } * 336 - 16) * scale
    for extra in [-0.5, 0, 0.5, 16] {
        let window = CGSize(width: width + 32 + extra, height: 196 * scale + 60)
        let result = try NativeOverviewLayout.solve(members: row, windowSize: window)
        guard let camera = result.leadingTransform, camera.scale == scale,
              result.placements.allSatisfy({ $0.row == 0 }) else { return ["single row changed scale or packing"] }
        if extra >= 0 {
            if result.maximumScrollOffset != 0 || camera.x != (window.width - width) / 2 {
                return ["fitting row has travel or is off center"]
            }
        } else {
            let inset = window.width <= 620 ? 32.0 : 64.0
            if result.maximumScrollOffset <= 0 || camera.x != inset
                || camera.x + width - result.maximumScrollOffset != window.width - inset {
                return ["overflow row misses a scroll boundary"]
            }
        }
    }
    return []
}

private func violations(_ input: LayoutCase) -> [String] {
    // Exercise the window-to-solver boundary as well as arbitrary solver rectangles.
    let window = NativeOverviewViewport(width: input.usable.width, height: input.usable.height)
    let region = NativeOverviewCameraGeometry.framingRegion(window)
    let expectedInset = window.height > 60 ? 30.0 : 0.0
    let bottomInset = window.height - (region.top + region.height)
    if region.top != expectedInset || abs(bottomInset - expectedInset) > tolerance {
        return ["incorrect top or bottom window margin"]
    }
    var random = SplitMix64(seed: input.seed)
    let toolbar = random.double(1...max(1, window.height))
    let dock = random.double(1...max(1, window.height))
    for (top, bottom) in [(toolbar, 0), (0, dock), (toolbar, dock)] {
        var viewport = window
        viewport.toolbarBottom = top
        viewport.bottomReservedHeight = bottom
        if NativeOverviewCameraGeometry.framingRegion(viewport) != region {
            return ["bar heights changed the layout region"]
        }
    }
    let result: NativeOverviewGeometry
    do {
        let fitIssues = try windowFitViolations(input)
        if !fitIssues.isEmpty { return fitIssues }
        result = try NativeOverviewLayout.solve(
            members: input.members,
            usableViewport: input.usable)
    } catch {
        return ["solve threw: \(error)"]
    }
    var issues = [String]()
    let expectedIDs = input.members.map(\.id)
    let actualIDs = result.placements.map(\.id)
    if actualIDs != expectedIDs { issues.append("placements are not in product order") }
    if Set(actualIDs) != Set(expectedIDs) { issues.append("membership mismatch") }
    if actualIDs.sorted() != expectedIDs.sorted() { issues.append("duplicate or missing identity") }
    for placement in result.placements {
        guard let member = input.members.first(where: { $0.id == placement.id }) else {
            issues.append("unknown member \(placement.id)"); continue
        }
        if placement.member != member { issues.append("stale size for \(placement.id)") }
        let cardFrame = frame(of: placement)
        if ![cardFrame.minX, cardFrame.minY, cardFrame.width, cardFrame.height].allSatisfy(\.isFinite) {
            issues.append("non-finite frame for \(placement.id)")
        }
        if cardFrame.width <= 0 || cardFrame.height <= 0 { issues.append("non-positive frame for \(placement.id)") }
    }
    // Any two cards must have the declared world gap on at least one axis.
    for (index, a) in result.placements.enumerated() {
        for b in result.placements.dropFirst(index + 1) {
            let horizontal = frame(of: a).maxX <= frame(of: b).minX + tolerance
                || frame(of: b).maxX <= frame(of: a).minX + tolerance
            let vertical = frame(of: a).maxY <= frame(of: b).minY + tolerance
                || frame(of: b).maxY <= frame(of: a).minY + tolerance
            if !horizontal && !vertical { issues.append("overlap \(a.id)/\(b.id)") }
            if horizontal {
                let gap = max(frame(of: b).minX - frame(of: a).maxX, frame(of: a).minX - frame(of: b).maxX)
                if gap + tolerance < metrics.gap { issues.append("short horizontal gap \(a.id)/\(b.id)") }
            }
            if vertical {
                let gap = max(frame(of: b).minY - frame(of: a).maxY, frame(of: a).minY - frame(of: b).maxY)
                if gap + tolerance < metrics.gap { issues.append("short vertical gap \(a.id)/\(b.id)") }
            }
        }
    }
    // Declared bounds are exactly the card-frame union.
    if !result.placements.isEmpty {
        let frames = result.placements.map { frame(of: $0) }
        let left = frames.map(\.minX).min()!, top = frames.map(\.minY).min()!
        let right = frames.map(\.maxX).max()!, bottom = frames.map(\.maxY).max()!
        if abs(result.bounds.left - left) > tolerance || abs(result.bounds.top - top) > tolerance
            || abs(result.bounds.width - (right - left)) > tolerance
            || abs(result.bounds.height - (bottom - top)) > tolerance {
            issues.append("bounds do not equal frame union")
        }
        if result.bounds.width <= 0 || result.bounds.height <= 0 { issues.append("non-positive bounds") }
    }
    if input.members.isEmpty {
        if result.leadingTransform != nil { issues.append("empty collection produced a camera") }
        return issues
    }
    guard input.usable.width > 0, input.usable.height > 0 else {
        if result.leadingTransform != nil { issues.append("zero viewport produced a camera") }
        return issues
    }
    guard let camera = result.leadingTransform else {
        issues.append("valid nonempty input has no leading transform")
        return issues
    }
    if ![camera.scale, camera.x, camera.y].allSatisfy(\.isFinite) { issues.append("non-finite camera") }
    if camera.scale <= 0 { issues.append("non-positive scale") }
    let fit = min(input.usable.width / result.bounds.width, input.usable.height / result.bounds.height)
    let tallest = metrics.height(rows: input.members.map(\.rows).max()!)
    if result.bounds.height > max(tallest, input.usable.height) + tolerance {
        issues.append("packing added rows beyond the available height")
    }
    if abs(camera.scale - min(1, input.usable.height / tallest)) > tolerance {
        issues.append("scale differs from the tallest single card's height constraint")
    }
    var screenUnion = CGRect.null
    for placement in result.placements {
        let cardFrame = frame(of: placement)
        let screen = CGRect(x: camera.x + cardFrame.minX * camera.scale,
                            y: camera.y + cardFrame.minY * camera.scale,
                            width: cardFrame.width * camera.scale,
                            height: cardFrame.height * camera.scale)
        screenUnion = screenUnion.union(screen)
        let allowed = CGRect(x: input.usable.left, y: input.usable.top,
                             width: input.usable.width, height: input.usable.height)
        if screen.minY < allowed.minY - tolerance || screen.maxY > allowed.maxY + tolerance
            || screen.minX < allowed.minX - tolerance || screen.maxX - result.maximumScrollOffset > allowed.maxX + tolerance {
            issues.append("card \(placement.id) cannot be reached within the viewport")
        }
    }
    let spareWidth = input.usable.width - screenUnion.width
    if abs(screenUnion.minX - (input.usable.left + max(0, spareWidth) / 2)) > tolerance
        || abs(screenUnion.midY - (input.usable.top + input.usable.height / 2)) > tolerance
        || abs(result.maximumScrollOffset - max(0, -spareWidth)) > tolerance {
        issues.append("leading alignment or trailing scroll boundary differs")
    }
    // Independent regular-grid lower bound: max card size in every cell.
    let maxColumns = input.members.map(\.columns).max()!
    let maxRows = input.members.map(\.rows).max()!
    let cellWidth = metrics.width(columns: maxColumns)
    let cellHeight = metrics.height(rows: maxRows)
    var baseline = 0.0
    for columns in 1...input.members.count {
        let rows = (input.members.count + columns - 1) / columns
        let width = Double(columns) * cellWidth + Double(columns - 1) * metrics.gap
        let height = Double(rows) * cellHeight + Double(rows - 1) * metrics.gap
        if height <= max(tallest, input.usable.height) {
            baseline = max(baseline, min(input.usable.width / width, input.usable.height / height))
        }
    }
    let productionFit = min(input.usable.width / result.bounds.width,
                            input.usable.height / result.bounds.height)
    if productionFit + 1e-9 < baseline { issues.append("worse than the regular-grid baseline") }
    if input.members.count == 4, let w = input.members.map(\.columns).min(), let h = input.members.map(\.rows).min(),
       input.members.filter({ $0.columns == w && $0.rows == h }).count == 2,
       input.members.contains(where: { $0.columns == 2 * w && $0.rows == h }),
       input.members.contains(where: { $0.columns == w && $0.rows == 2 * h }) {
        // Both six-cell rectangles admit a tiling. Any wider or taller strip
        // still needs at least two rows and two columns for the two long cards.
        let landscape = min(input.usable.width / metrics.width(columns: 3 * w),
                            input.usable.height / metrics.height(rows: 2 * h))
        let portrait = min(input.usable.width / metrics.width(columns: 2 * w),
                           input.usable.height / metrics.height(rows: 3 * h))
        let fullRectangle = (result.bounds.columns, result.bounds.rows) == (3 * w, 2 * h)
            || (result.bounds.columns, result.bounds.rows) == (2 * w, 3 * h)
        let canUsePortrait = metrics.height(rows: 3 * h) <= max(tallest, input.usable.height)
        if !fullRectangle || fit + tolerance < (canUsePortrait ? max(landscape, portrait) : landscape) {
            issues.append("mixed four-card tiling wastes space or misses the better orientation")
        }
    }
    return issues
}

private func shrink(_ input: LayoutCase, seconds: Int, while fails: (LayoutCase) -> Bool) -> LayoutCase {
    var best = input
    var changed = true
    let deadline = ContinuousClock.now + .seconds(seconds)
    while changed && ContinuousClock.now < deadline {
        changed = false
        var candidates = [LayoutCase]()
        for index in best.members.indices {
            var removed = best
            removed.members.remove(at: index)
            candidates.append(removed)
            if best.members[index].columns > 1 {
                var narrow = best
                narrow.members[index] = .init(id: narrow.members[index].id,
                                              columns: narrow.members[index].columns - 1,
                                              rows: narrow.members[index].rows)
                candidates.append(narrow)
            }
            if best.members[index].rows > 1 {
                var short = best
                short.members[index] = .init(id: short.members[index].id,
                                             columns: short.members[index].columns,
                                             rows: short.members[index].rows - 1)
                candidates.append(short)
            }
        }
        if best.usable.width > 1 {
            var narrow = best; narrow.usable.width = max(1, best.usable.width / 2); candidates.append(narrow)
        }
        if best.usable.height > 1 {
            var short = best; short.usable.height = max(1, best.usable.height / 2); candidates.append(short)
        }
        for candidate in candidates {
            if ContinuousClock.now >= deadline { return best }
            guard fails(candidate) else { continue }
            best = candidate
            changed = true
            break
        }
    }
    return best
}

// PBT-OVERVIEW-GEOMETRY: Sources/Host/Overview/README.md
@Suite(.serialized)
struct NativeOverviewGeometryProperties {
    @Test func generatedLayoutsSatisfyTheContract() throws {
        let budget = try PropertyBudget(defaultCases: 480)
        let replay = try propertyReplay(LayoutCase.self)
        let inputs = replay.map { [$0] } ?? (0..<budget.cases).map { generate(seed: budget.seed &+ UInt64($0)) }
        for input in inputs {
            let issues = violations(input)
            if let first = issues.first {
                try propertyEvidence(input, name: "original.json")
                print("PBT FAIL PBT-OVERVIEW-GEOMETRY seed=\(input.seed) issues=\(issues)")
                let reduced = shrink(input, seconds: budget.shrinkSeconds) { violations($0).contains(first) }
                try propertyEvidence(reduced, name: "reduced.json")
                let json = String(decoding: try JSONEncoder().encode(reduced), as: UTF8.self)
                Issue.record(Comment(rawValue: "PBT-OVERVIEW-GEOMETRY seed=\(input.seed) issues=\(issues) reduced=\(json)"))
                return
            }
        }
        print("PBT PASS PBT-OVERVIEW-GEOMETRY seed=\(budget.seed) cases=\(inputs.count) replay=\(replay != nil)")
    }
}
