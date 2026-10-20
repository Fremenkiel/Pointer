/// A uniform grid that finds the items whose bounds touch a rectangle (architecture.md 5.6).
///
/// Each cell holds the items whose bounds touch it. A query reports each item once, in the cell
/// where the overlap of the item bounds and the query starts.
public struct SpatialGrid<ID: Hashable & Sendable>: Sendable {
    /// One item in a cell.
    @usableFromInline
    struct Entry: Sendable {
        @usableFromInline let id: ID
        @usableFromInline let bounds: Rect

        @inlinable
        init(id: ID, bounds: Rect) {
            self.id = id
            self.bounds = bounds
        }
    }

    /// The side length of a cell, in canvas points.
    public let cellSize: Double
    /// The largest cell coordinate. Coordinates further out land in the edge cells.
    public static var maxCellCoordinate: Int { 1 << 30 }

    // The removal is inlinable, so that a caller in another module gets code for its own ID
    // type. Unspecialized, 2,000 removals took 72 ms on the Mac (M4 task 3.8).
    @usableFromInline var cells: [GridCell: [Entry]] = [:]
    @usableFromInline var boundsByID: [ID: Rect] = [:]

    /// Makes an empty grid.
    ///
    /// - Precondition: `cellSize` is greater than zero.
    public init(cellSize: Double) {
        precondition(
            cellSize > 0 && cellSize.isFinite,
            "Grid cell size must be positive, got \(cellSize)"
        )
        self.cellSize = cellSize
    }

    /// The number of items in the grid.
    public var count: Int { boundsByID.count }

    /// The number of cells that hold at least one item.
    public var occupiedCellCount: Int { cells.count }

    /// Returns the bounds of an item, or `nil` if the grid does not hold it.
    public func bounds(of id: ID) -> Rect? { boundsByID[id] }

    /// Adds an item.
    ///
    /// - Precondition: The grid does not hold `id`, and `bounds` is finite.
    @inlinable
    public mutating func insert(_ id: ID, bounds: Rect) {
        precondition(boundsByID[id] == nil, "Grid already holds \(id)")
        precondition(bounds.origin.isFinite, "Grid bounds of \(id) are not finite")
        boundsByID[id] = bounds
        let range = cellRange(for: bounds)
        assert(range.cellCount >= 1, "Bounds of \(id) cover no cell")
        for row in range.rows {
            for column in range.columns {
                cells[GridCell(column: column, row: row), default: []].append(
                    Entry(id: id, bounds: bounds)
                )
            }
        }
    }

    /// Removes an item. It does nothing if the grid does not hold `id`.
    ///
    /// - Returns: `true` if the grid held the item.
    @discardableResult  // The caller often removes an item that it knows is there.
    @inlinable
    public mutating func remove(_ id: ID) -> Bool {
        guard let bounds = boundsByID.removeValue(forKey: id) else { return false }
        let range = cellRange(for: bounds)
        for row in range.rows {
            for column in range.columns {
                removeEntry(id, from: GridCell(column: column, row: row))
            }
        }
        assert(boundsByID[id] == nil, "Grid still holds \(id) after the removal")
        return true
    }

    /// Calls `body` once for each item whose bounds touch `rect`.
    ///
    /// The work is bounded by the smaller of the number of cells in `rect` and the number of
    /// occupied cells.
    ///
    /// - Precondition: `rect` is finite.
    public func forEachItem(touching rect: Rect, _ body: (ID) -> Void) {
        precondition(rect.origin.isFinite, "Grid query \(rect) is not finite")
        precondition(
            rect.size.width.isFinite && rect.size.height.isFinite,
            "Grid query \(rect) is not finite"
        )
        let range = cellRange(for: rect)
        if range.cellCount <= cells.count {
            for row in range.rows {
                for column in range.columns {
                    let cell = GridCell(column: column, row: row)
                    report(cell, entries: cells[cell], query: rect, body)
                }
            }
        } else {
            for (cell, entries) in cells where range.contains(cell) {
                report(cell, entries: entries, query: rect, body)
            }
        }
    }

    /// Returns the cell that holds a canvas point.
    public func cell(containing point: Point) -> GridCell {
        GridCell(column: coordinate(point.x), row: coordinate(point.y))
    }

    private func report(_ cell: GridCell, entries: [Entry]?, query: Rect, _ body: (ID) -> Void) {
        guard let entries else { return }
        assert(!entries.isEmpty, "Grid keeps the empty cell \(cell)")
        for entry in entries where entry.bounds.intersects(query) {
            let start = Point(
                x: max(entry.bounds.minX, query.minX),
                y: max(entry.bounds.minY, query.minY)
            )
            if self.cell(containing: start) == cell {
                body(entry.id)
            }
        }
    }

    @inlinable
    mutating func removeEntry(_ id: ID, from cell: GridCell) {
        guard let index = cells[cell]?.firstIndex(where: { $0.id == id }) else {
            assertionFailure("Grid cell \(cell) does not hold \(id)")
            return
        }
        // The changes go through the optional chain, so the array changes in place. A copy into
        // a local `var` made each removal copy the whole cell (M4 task 3.8).
        let last = (cells[cell]?.count ?? 1) - 1
        cells[cell]?.swapAt(index, last)
        cells[cell]?.removeLast()
        if cells[cell]?.isEmpty == true {
            cells[cell] = nil
        }
        assert(cells[cell]?.contains { $0.id == id } != true, "Grid cell \(cell) still holds \(id)")
    }

    @inlinable
    func coordinate(_ value: Double) -> Int {
        let limit = Double(Self.maxCellCoordinate)
        let scaled = (value / cellSize).rounded(.down)
        return Int(min(max(scaled, -limit), limit))
    }

    @inlinable
    func cellRange(for rect: Rect) -> CellRange {
        CellRange(
            columns: coordinate(rect.minX)...coordinate(rect.maxX),
            rows: coordinate(rect.minY)...coordinate(rect.maxY)
        )
    }
}

/// A rectangle of grid cells.
@usableFromInline
struct CellRange {
    @usableFromInline let columns: ClosedRange<Int>
    @usableFromInline let rows: ClosedRange<Int>

    @inlinable
    init(columns: ClosedRange<Int>, rows: ClosedRange<Int>) {
        self.columns = columns
        self.rows = rows
    }

    @usableFromInline var cellCount: Int { columns.count * rows.count }

    func contains(_ cell: GridCell) -> Bool {
        columns.contains(cell.column) && rows.contains(cell.row)
    }
}
