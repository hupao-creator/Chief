import Foundation
import ChiefPluginUI

public struct NativeOverviewMember: Equatable, Hashable, Codable, Sendable {
    public let id: String
    public let columns: Int
    public let rows: Int

    public init(id: String, columns: Int, rows: Int) {
        self.id = id
        self.columns = columns
        self.rows = rows
    }
}

public struct NativeOverviewPlacement: Equatable, Hashable, Codable, Sendable {
    public let member: NativeOverviewMember
    public let column: Int
    public let row: Int
    public var id: String { member.id }
    public var columns: Int { member.columns }
    public var rows: Int { member.rows }

    public init(member: NativeOverviewMember, column: Int, row: Int) {
        self.member = member
        self.column = column
        self.row = row
    }
}

/// The product grid. Card footprints remain the latest measured spans; this
/// metric only maps those spans to world points.
public struct NativeOverviewGridMetrics: Equatable, Sendable {
    public let columnWidth: Double
    public let rowHeight: Double
    public let gap: Double

    public init(columnWidth: Double, rowHeight: Double, gap: Double) {
        self.columnWidth = columnWidth
        self.rowHeight = rowHeight
        self.gap = gap
    }

    public var columnPitch: Double { columnWidth + gap }
    public var rowPitch: Double { rowHeight + gap }

    public static let standard = Self(columnWidth: Double(NativeGeometry.overviewCard.width),
                                      rowHeight: Double(NativeGeometry.overviewCard.height),
                                      gap: Double(NativeGeometry.overviewCardGap))

    public func width(columns: Int) -> Double {
        Double(columns) * columnWidth + Double(columns - 1) * gap
    }

    public func height(rows: Int) -> Double {
        Double(rows) * rowHeight + Double(rows - 1) * gap
    }
}

public struct NativeOverviewBounds: Equatable, Codable, Sendable {
    public let column: Int
    public let row: Int
    public let columns: Int
    public let rows: Int
    public let left: Double
    public let top: Double
    public let width: Double
    public let height: Double

    public var centerX: Double { left + width / 2 }
    public var centerY: Double { top + height / 2 }

    public init(column: Int, row: Int, columns: Int, rows: Int,
                left: Double, top: Double, width: Double, height: Double) {
        self.column = column
        self.row = row
        self.columns = columns
        self.rows = rows
        self.left = left
        self.top = top
        self.width = width
        self.height = height
    }

    public static let empty = Self(column: 0, row: 0, columns: 0, rows: 0,
                                   left: 0, top: 0, width: 0, height: 0)
}

public struct NativeOverviewGeometry: Equatable, Sendable {
    public let placements: [NativeOverviewPlacement]
    public let bounds: NativeOverviewBounds
    /// The view at the leading scroll boundary. Empty layouts have no projection.
    public let leadingTransform: NativeOverviewTransform?
    public let maximumScrollOffset: Double
}

public enum NativeOverviewLayoutError: LocalizedError, Equatable {
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message): message
        }
    }
}

/// Pure, history-free geometry. The same complete input always produces the
/// same placements, bounds and horizontal scroll range.
///
/// `members` order is product order (selection/catalog order): it owns card
/// identity order and deterministic tie-breaking. It is not a user-movable
/// position and no previous layout participates.
public enum NativeOverviewLayout {
    private static let maximumSafeInteger = 9_007_199_254_740_991

    public static var metrics: NativeOverviewGridMetrics { .standard }
    public static var columnWidth: Double { metrics.columnWidth }
    public static var rowHeight: Double { metrics.rowHeight }
    public static var gap: Double { metrics.gap }
    public static var columnPitch: Double { metrics.columnPitch }
    public static var rowPitch: Double { metrics.rowPitch }

    /// Packing keeps the preferred side margins. A grid that fits in the window
    /// with one card gap on either side can stay centered without scrolling.
    public static func solve(members: [NativeOverviewMember], windowSize: CGSize) throws -> NativeOverviewGeometry {
        let region = NativeOverviewCameraGeometry.framingRegion(.init(width: windowSize.width, height: windowSize.height))
        let sideClearance = min(region.left, gap)
        return try solve(members: members, usableViewport: region, metrics: .standard,
                         fittingWidth: windowSize.width - 2 * sideClearance)
    }

    public static func solve(members: [NativeOverviewMember],
                             usableViewport: NativeOverviewContentRect,
                             metrics: NativeOverviewGridMetrics = .standard) throws -> NativeOverviewGeometry {
        try solve(members: members, usableViewport: usableViewport, metrics: metrics, fittingWidth: usableViewport.width)
    }

    private static func solve(members: [NativeOverviewMember], usableViewport: NativeOverviewContentRect,
                              metrics: NativeOverviewGridMetrics, fittingWidth: Double) throws -> NativeOverviewGeometry {
        try validate(members: members, viewport: usableViewport, metrics: metrics)
        guard !members.isEmpty else {
            return NativeOverviewGeometry(placements: [], bounds: .empty, leadingTransform: nil, maximumScrollOffset: 0)
        }
        let chosen = choosePlacement(members: members, viewport: usableViewport, metrics: metrics)
        // Shelf candidates are size-sorted for packing. Return product order so
        // content-only reuse and callers see a stable, input-aligned sequence.
        let byID = Dictionary(uniqueKeysWithValues: chosen.map { ($0.id, $0) })
        let placements = members.compactMap { byID[$0.id] }
        guard placements.count == members.count else {
            throw NativeOverviewLayoutError.invalidInput("Overview solver lost a member")
        }
        let bounds = summarize(placements, metrics: metrics)
        guard usableViewport.width > 0, usableViewport.height > 0 else {
            return .init(placements: placements, bounds: bounds, leadingTransform: nil, maximumScrollOffset: 0)
        }
        // Only a card taller than the available height needs scaling. A wide
        // collection keeps its natural size and starts at the leading inset.
        let scale = min(1, usableViewport.height / bounds.height)
        let projectedWidth = bounds.width * scale
        let fits = projectedWidth <= fittingWidth
        let spareWidth = usableViewport.width - projectedWidth
        let leading = NativeOverviewTransform(scale: scale,
            x: usableViewport.left + (fits ? spareWidth / 2 : 0) - bounds.left * scale,
            y: usableViewport.top + (usableViewport.height - bounds.height * scale) / 2 - bounds.top * scale)
        return .init(placements: placements, bounds: bounds, leadingTransform: leading, maximumScrollOffset: fits ? 0 : -spareWidth)
    }

    // MARK: - Candidate selection

    private struct Score {
        let fitsHeight: Bool
        let fit: Double
        let area: Double
        let width: Double

        init(columns: Int, rows: Int, rowLimit: Int, viewport: NativeOverviewContentRect, metrics: NativeOverviewGridMetrics) {
            fitsHeight = rows <= rowLimit
            width = metrics.width(columns: columns)
            let height = metrics.height(rows: rows)
            fit = min(viewport.width / width, viewport.height / height)
            area = width * height
        }

        func improves(on other: Self) -> Bool {
            if fitsHeight != other.fitsHeight { return fitsHeight }
            if fit != other.fit { return fit > other.fit }
            if area != other.area { return area < other.area }
            return width < other.width
        }
    }

    private static func choosePlacement(members: [NativeOverviewMember],
                                        viewport: NativeOverviewContentRect,
                                        metrics: NativeOverviewGridMetrics) -> [NativeOverviewPlacement] {
        let maxColumns = members.map(\.columns).max()!
        let maxRows = members.map(\.rows).max()!
        let totalRows = members.reduce(0) { $0 + $1.rows }
        let availableRows = (viewport.height + metrics.gap) / metrics.rowPitch
        let rowLimit = max(maxRows, Int(min(Double(totalRows), availableRows)))
        func gridScore(_ across: Int) -> Score {
            Score(columns: across * maxColumns, rows: (1 + (members.count - 1) / across) * maxRows,
                  rowLimit: rowLimit, viewport: viewport, metrics: metrics)
        }

        // Score regular grids by dimensions alone. Packing each winning row to
        // its members' actual width and height can only improve its raw fit.
        var across = 1
        var bestScore = gridScore(1)
        for count in members.indices.dropFirst() {
            let score = gridScore(count + 1)
            if score.improves(on: bestScore) {
                across = count + 1
                bestScore = score
            }
        }
        var x = 0, y = 0, band = 0
        var best = members.enumerated().map { index, member in
            if index > 0 && index.isMultiple(of: across) {
                y += band
                x = 0
                band = 0
            }
            let placement = NativeOverviewPlacement(member: member, column: x, row: y)
            x += member.columns
            band = max(band, member.rows)
            return placement
        }
        func score(_ placements: [NativeOverviewPlacement]) -> Score {
            let bounds = summarize(placements, metrics: metrics)
            return Score(columns: bounds.columns, rows: bounds.rows, rowLimit: rowLimit, viewport: viewport, metrics: metrics)
        }
        bestScore = score(best)
        if bestScore.fit < 1 {
            // Fill successive columns in product order when space runs out.
            // Include the exact height limit even when shelf sampling is sparse.
            let columns = pack(members, target: rowLimit, vertical: true)
            let candidate = score(columns)
            if !bestScore.improves(on: candidate) {
                best = columns
                bestScore = candidate
            }
        }
        guard members.contains(where: { $0.columns != maxColumns || $0.rows != maxRows }) else { return best }

        // Prefer the product-order packing on ties, across both orientations.
        for sizeFirst in [false, true] {
            for vertical in [false, true] {
                var order = members
                if sizeFirst {
                    order.sort { a, b in
                        vertical ? (a.columns, a.rows) > (b.columns, b.rows) : (a.rows, a.columns) > (b.rows, b.columns)
                    }
                    if order == members { continue }
                }
                let minimum = vertical ? maxRows : maxColumns
                let total = members.reduce(0) { $0 + (vertical ? $1.rows : $1.columns) }
                for target in shelfTargets(minimum: minimum, maximum: total) {
                    let placements = pack(order, target: target, vertical: vertical)
                    let candidate = score(placements)
                    if candidate.improves(on: bestScore) {
                        best = placements
                        bestScore = candidate
                    }
                }
            }
        }
        return fillInteriorGaps(in: best)
    }

    /// A shelf boundary can divide one usable opening, and moving a card
    /// into it need not improve the bounding box. Look at the actual cards
    /// once the grid has been chosen. Only pull cards from a lower row.
    private static func fillInteriorGaps(in placements: [NativeOverviewPlacement]) -> [NativeOverviewPlacement] {
        var result = placements
        let readingOrder = placements.indices.sorted {
            (placements[$0].row, placements[$0].column) < (placements[$1].row, placements[$1].column)
        }
        let heights = Set(placements.map(\.rows)).sorted(by: >)
        let lastRow = placements.map(\.row).max()!
        var row = 0
        while row < lastRow {
            for height in heights {
                let bottom = row + height
                let later = readingOrder.reversed().filter { result[$0].rows == height && result[$0].row >= bottom }
                guard !later.isEmpty else { continue }
                // Project every obstacle in this height band onto the x axis.
                // Overlapping projections form a single occupied run.
                let obstacles = result.filter { $0.row < bottom && $0.row + $0.rows > row }
                    .sorted { $0.column < $1.column }
                guard let first = obstacles.first else { continue }
                var available = Dictionary(grouping: later) { result[$0].columns }
                let widths = available.keys.sorted(by: >)
                var column = first.column + first.columns
                for obstacle in obstacles.dropFirst() {
                    while column < obstacle.column {
                        let room = obstacle.column - column
                        guard let width = widths.first(where: { $0 <= room && available[$0]?.isEmpty == false }),
                              let index = available[width]?.popLast() else { break }
                        let card = result[index]
                        result[index] = .init(member: card.member, column: column, row: row)
                        column += card.columns
                    }
                    column = max(column, obstacle.column + obstacle.columns)
                }
            }
            // New space can open below a moved card. Jump between edges so
            // work and storage are independent of the numerical grid spans.
            row = result.reduce(lastRow) { next, card in
                let bottom = card.row + card.rows
                if card.row > row { return min(next, card.row) }
                return bottom > row ? min(next, bottom) : next
            }
        }
        return result
    }

    private static func shelfTargets(minimum: Int, maximum: Int) -> [Int] {
        let count = maximum - minimum + 1
        guard count > 64 else { return Array(minimum...maximum) }
        let step = (count + 62) / 64
        var targets = Array(stride(from: minimum, through: maximum, by: step))
        if targets.last != maximum { targets.append(maximum) }
        return targets
    }

    private struct Opening {
        let x, y, width, height: Int
    }

    /// Work in strip coordinates and transpose the result for vertical bands.
    /// Each opening is disjoint. Splitting it retains both reusable pieces,
    /// including the space directly underneath a shorter card.
    private static func pack(_ members: [NativeOverviewMember], target: Int,
                             vertical: Bool) -> [NativeOverviewPlacement] {
        var openings = [Opening]()
        var end = 0
        var placements = [NativeOverviewPlacement]()
        placements.reserveCapacity(members.count)
        for member in members {
            let width = vertical ? member.rows : member.columns
            let height = vertical ? member.columns : member.rows
            let slot: Opening
            if let index = openings.firstIndex(where: { width <= $0.width && height <= $0.height }) {
                slot = openings.remove(at: index)
            } else {
                slot = Opening(x: 0, y: end, width: target, height: height)
                end += height
            }
            placements.append(.init(member: member, column: vertical ? slot.y : slot.x,
                                    row: vertical ? slot.x : slot.y))
            if width < slot.width {
                openings.append(.init(x: slot.x + width, y: slot.y,
                                      width: slot.width - width, height: slot.height))
            }
            if height < slot.height {
                openings.append(.init(x: slot.x, y: slot.y + height,
                                      width: width, height: slot.height - height))
            }
            // Bound search cost even when every span is distinct. Forgetting
            // an opening leaves it empty and can never admit an overlap.
            if openings.count > 64 { openings.removeFirst(openings.count - 64) }
        }
        return placements
    }

    private static func summarize(_ placements: [NativeOverviewPlacement],
                                  metrics: NativeOverviewGridMetrics) -> NativeOverviewBounds {
        guard let first = placements.first else { return .empty }
        var left = first.column, top = first.row
        var right = first.column + first.columns, bottom = first.row + first.rows
        for placement in placements.dropFirst() {
            left = min(left, placement.column)
            top = min(top, placement.row)
            right = max(right, placement.column + placement.columns)
            bottom = max(bottom, placement.row + placement.rows)
        }
        let columns = right - left, rows = bottom - top
        return .init(column: left, row: top, columns: columns, rows: rows,
                     left: Double(left) * metrics.columnPitch,
                     top: Double(top) * metrics.rowPitch,
                     width: metrics.width(columns: columns),
                     height: metrics.height(rows: rows))
    }

    // MARK: - Validation

    private static func validate(members: [NativeOverviewMember],
                                 viewport: NativeOverviewContentRect,
                                 metrics: NativeOverviewGridMetrics) throws {
        guard metrics.columnWidth.isFinite, metrics.columnWidth > 0,
              metrics.rowHeight.isFinite, metrics.rowHeight > 0,
              metrics.gap.isFinite, metrics.gap >= 0 else {
            throw NativeOverviewLayoutError.invalidInput("Overview grid metrics must be finite and positive")
        }
        for value in [viewport.left, viewport.top, viewport.width, viewport.height] {
            guard value.isFinite else {
                throw NativeOverviewLayoutError.invalidInput("Overview viewport must be finite")
            }
        }
        guard viewport.width >= 0, viewport.height >= 0 else {
            throw NativeOverviewLayoutError.invalidInput("Overview viewport must be nonnegative")
        }
        var ids = Set<String>()
        var columnSum = 0, rowSum = 0
        for member in members {
            guard !member.id.isEmpty, member.columns > 0, member.rows > 0,
                  member.columns <= maximumSafeInteger, member.rows <= maximumSafeInteger else {
                throw NativeOverviewLayoutError.invalidInput("Overview footprints must be positive integer grid spans")
            }
            guard member.columns <= maximumSafeInteger - columnSum,
                  member.rows <= maximumSafeInteger - rowSum else {
                throw NativeOverviewLayoutError.invalidInput("Overview aggregate grid size exceeds safe integers")
            }
            columnSum += member.columns
            rowSum += member.rows
            guard ids.insert(member.id).inserted else {
                throw NativeOverviewLayoutError.invalidInput("Overview member IDs must be unique")
            }
        }
        guard metrics.width(columns: columnSum).isFinite,
              metrics.height(rows: rowSum).isFinite else {
            throw NativeOverviewLayoutError.invalidInput("Overview world bounds cannot be represented")
        }
        if members.count > 1 {
            let maxColumns = members.map(\.columns).max()!
            let maxRows = members.map(\.rows).max()!
            let factor = members.count - 1
            guard maxColumns <= maximumSafeInteger / factor,
                  maxRows <= maximumSafeInteger / factor else {
                throw NativeOverviewLayoutError.invalidInput("Overview grid multiplication exceeds safe integers")
            }
        }
    }
}

public extension NativeOverviewBounds {
    var contentRect: NativeOverviewContentRect {
        .init(left: left, top: top, width: width, height: height)
    }
}

public extension NativeOverviewPlacement {
    func cardFrame(using metrics: NativeOverviewGridMetrics) -> CGRect {
        CGRect(x: Double(column) * metrics.columnPitch,
               y: Double(row) * metrics.rowPitch,
               width: metrics.width(columns: columns),
               height: metrics.height(rows: rows))
    }
}
