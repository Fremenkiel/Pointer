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
    /// The most cells that one item can touch. It bounds the loops of `insert` and `remove`
    /// (FLOW-03, D-158).
    public let maxCellsPerItem: Int
    /// The largest cell coordinate. Coordinates further out land in the edge cells.
    public static var maxCellCoordinate: Int { GridCell.maxCoordinate }

    // The removal is inlinable, so that a caller in another module gets code for its own ID
    // type. Unspecialized, 2,000 removals took 72 ms on the Mac (M4 task 3.8).
    @usableFromInline var cells: [GridCell: [Entry]] = [:]
    @usableFromInline var boundsByID: [ID: Rect] = [:]

    /// Makes an empty grid.
    ///
    /// - Precondition: `cellSize` and `maxCellsPerItem` are greater than zero.
    public init(cellSize: Double, maxCellsPerItem: Int) {
        precondition(
            cellSize > 0 && cellSize.isFinite,
            "Grid cell size must be positive, got \(cellSize)"
        )
        precondition(maxCellsPerItem > 0, "A grid item touches a cell, got \(maxCellsPerItem)")
        self.cellSize = cellSize
        self.maxCellsPerItem = maxCellsPerItem
    }

    /// The number of items in the grid.
    public var count: Int { boundsByID.count }

    /// The bytes of the cell table, the cell lists, and the bounds table, from their
    /// capacities (D-167).
    public var storageByteCount: Int {
        let lists = cells.values.reduce(0) { $0 + $1.storageByteCount }
        assert(lists >= boundsByID.count * MemoryLayout<Entry>.stride, "Each item is in a cell")
        let bytes = cells.storageByteCount + lists + boundsByID.storageByteCount
        return bytes
    }

    /// The number of cells that hold at least one item.
    public var occupiedCellCount: Int { cells.count }

    /// Reserves room for `count` items, so that a load grows the item table once (PERF-01).
    ///
    /// - Precondition: `count` is not negative.
    public mutating func reserveCapacity(_ count: Int) {
        precondition(count >= 0, "A grid reserves no negative count, got \(count)")
        boundsByID.reserveCapacity(count)
    }

    /// Returns the bounds of an item, or `nil` if the grid does not hold it.
    public func bounds(of id: ID) -> Rect? { boundsByID[id] }

    /// Adds an item.
    ///
    /// - Precondition: The grid does not hold `id`, `bounds` is finite, and `bounds` touches
    ///   at most `maxCellsPerItem` cells.
    @inlinable
    public mutating func insert(_ id: ID, bounds: Rect) {
        precondition(boundsByID[id] == nil, "Grid already holds \(id)")
        precondition(bounds.origin.isFinite, "Grid bounds of \(id) are not finite")
        let range = cellRange(for: bounds)
        precondition(
            range.cellCount <= maxCellsPerItem,
            "Grid item \(id) touches \(range.cellCount) cells, more than \(maxCellsPerItem)"
        )
        boundsByID[id] = bounds
        let entry = Entry(id: id, bounds: bounds)
        for row in range.rows {
            for column in range.columns {
                // One lookup, and the cell changes in place (P-02).
                let cell = GridCell(column: column, row: row)
                if let index = cells.index(forKey: cell) {
                    cells.values[index].append(entry)
                } else {
                    cells[cell] = [entry]
                }
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
        precondition(range.cellCount <= maxCellsPerItem, "Grid item \(id) has too many cells")
        for row in range.rows {
            for column in range.columns {
                removeEntry(id, from: GridCell(column: column, row: row))
            }
        }
        return true
    }

    /// Calls `body` once for each item whose bounds touch `rect`.
    ///
    /// The work is bounded by the smaller of the number of cells in `rect` and the number of
    /// occupied cells.
    ///
    /// - Precondition: `rect` is finite.
    @inlinable
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
    @inlinable
    public func cell(containing point: Point) -> GridCell {
        GridCell(column: coordinate(point.x), row: coordinate(point.y))
    }

    @inlinable
    func report(_ cell: GridCell, entries: [Entry]?, query: Rect, _ body: (ID) -> Void) {
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
        // One lookup, and the cell changes in place through `values`. The optional chain of
        // before made 5 to 6 lookups and about 6 allocations per cell (P-02).
        // The search starts at the end: an undo or a redo removes the strokes that the step
        // before added, and those are the last entries of their cells.
        guard let slot = cells.index(forKey: cell),
            let index = cells.values[slot].lastIndex(where: { $0.id == id })
        else {
            assertionFailure("Grid cell \(cell) does not hold \(id)")
            return
        }
        let last = cells.values[slot].count - 1
        cells.values[slot].swapAt(index, last)
        cells.values[slot].removeLast()
        if cells.values[slot].isEmpty {
            cells.remove(at: slot)
        }
        assert(cells[cell]?.contains { $0.id == id } != true, "Grid cell \(cell) still holds \(id)")
    }

    @inlinable
    func coordinate(_ value: Double) -> Int {
        GridCell.coordinate(value, cellSize: cellSize)
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

    @inlinable
    func contains(_ cell: GridCell) -> Bool {
        columns.contains(cell.column) && rows.contains(cell.row)
    }
}
