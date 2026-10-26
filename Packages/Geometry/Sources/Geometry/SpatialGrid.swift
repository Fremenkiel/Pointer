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

    /// The entries of one cell. A cell of more than `indexedCellCount` entries also keeps the
    /// position of each entry, so that a removal finds it without a scan (m10-plan.md task 3.2).
    @usableFromInline
    struct Cell: Sendable {
        @usableFromInline var entries: [Entry]
        /// The position of each entry in `entries`, or `nil` in a small cell.
        @usableFromInline var positions: [ID: Int]?

        /// Makes a small cell with one entry and no position table.
        @inlinable
        init(entry: Entry) {
            entries = [entry]
            positions = nil
        }

        /// Appends an entry. The cell keeps the positions of its entries once it holds more
        /// than `indexedCellCount` entries.
        @inlinable
        mutating func append(_ entry: Entry) {
            entries.append(entry)
            if positions != nil {
                positions?[entry.id] = entries.count - 1
            } else if entries.count > SpatialGrid.indexedCellCount {
                var table: [ID: Int] = [:]
                table.reserveCapacity(entries.count * 2)
                for (position, old) in entries.enumerated() { table[old.id] = position }
                positions = table
            }
            assert(positions.map { $0.count == entries.count } ?? true, "Each entry has a position")
        }

        /// Removes the entry of `id`.
        ///
        /// - Returns: `false` if the cell does not hold `id`.
        @inlinable
        mutating func remove(_ id: ID) -> Bool {
            // A small cell scans from the end: an undo or a redo removes the strokes that the
            // step before added, and those are the last entries of their cells.
            guard let index = positions?[id] ?? entries.lastIndex(where: { $0.id == id }) else {
                return false  // contract: error value
            }
            let last = entries.count - 1
            if positions != nil {
                positions?[entries[last].id] = index
                positions?.removeValue(forKey: id)
            }
            entries.swapAt(index, last)
            entries.removeLast()
            assert(positions.map { $0.count == entries.count } ?? true, "Each entry has a position")
            return true
        }
    }

    /// The entries above which a cell keeps the positions of its entries. A scan costs about
    /// 0.6 ns per entry on the Mac. At 64, the cells of dense handwriting (about 330 entries)
    /// built tables, and a load of 200,000 items took 14 ms instead of 9 ms. At 1,024, only a
    /// crowded cell pays: 1,000 removals from a cell of 20,000 take 0.13 ms instead of 5.8 ms.
    @usableFromInline static var indexedCellCount: Int { 1_024 }

    /// The side length of a cell, in canvas points.
    public let cellSize: Double
    /// The most cells that one item can touch. It bounds the loops of `insert` and `remove`
    /// (FLOW-03, D-158).
    public let maxCellsPerItem: Int
    // Only the tests read it (SCOPE-01).
    // swiftlint:disable unused_declaration
    /// The largest cell coordinate. Coordinates further out land in the edge cells.
    static var maxCellCoordinate: Int { GridCell.maxCoordinate }
    // swiftlint:enable unused_declaration

    // The removal is inlinable, so that a caller in another module gets code for its own ID
    // type. Unspecialized, 2,000 removals took 72 ms on the Mac (M4 task 3.8).
    /// The entries of each occupied cell.
    /// The bounds of each item.
    @usableFromInline var cells: [GridCell: Cell] = [:]
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
        let lists = cells.values.reduce(0) {
            $0 + $1.entries.storageByteCount + ($1.positions?.storageByteCount ?? 0)
        }
        assert(lists >= boundsByID.count * MemoryLayout<Entry>.stride, "Each item is in a cell")
        let bytes = cells.storageByteCount + lists + boundsByID.storageByteCount
        return bytes
    }

    // Only the tests read it (SCOPE-01).
    // swiftlint:disable unused_declaration
    /// The number of cells that hold at least one item.
    var occupiedCellCount: Int { cells.count }
    // swiftlint:enable unused_declaration

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
                    cells[cell] = Cell(entry: entry)
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
                    report(cell, entries: cells[cell]?.entries, query: rect, body)
                }
            }
        } else {
            for (cell, content) in cells where range.contains(cell) {
                report(cell, entries: content.entries, query: rect, body)
            }
        }
    }

    /// Returns the cell that holds a canvas point.
    @inlinable
    public func cell(containing point: Point) -> GridCell {
        GridCell(column: coordinate(point.x), row: coordinate(point.y))
    }

    /// Calls `body` for each entry of a cell that touches `query` and starts in that cell.
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

    /// Removes the entry of an item from one cell, and the cell if it becomes empty.
    @inlinable
    mutating func removeEntry(_ id: ID, from cell: GridCell) {
        // One lookup, and the cell changes in place through `values`. The optional chain of
        // before made 5 to 6 lookups and about 6 allocations per cell (P-02).
        guard let slot = cells.index(forKey: cell), cells.values[slot].remove(id) else {
            assertionFailure("Grid cell \(cell) does not hold \(id)")
            return
        }
        if cells.values[slot].entries.isEmpty {
            cells.remove(at: slot)
        }
        assert(
            cells[cell]?.entries.contains { $0.id == id } != true,
            "Grid cell \(cell) still holds \(id)"
        )
    }

    /// Returns the cell coordinate of a canvas coordinate.
    @inlinable
    func coordinate(_ value: Double) -> Int {
        GridCell.coordinate(value, cellSize: cellSize)
    }

    /// Returns the cells that a rectangle touches.
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
    /// The column coordinates of the cells.
    /// The row coordinates of the cells.
    @usableFromInline let columns: ClosedRange<Int>
    @usableFromInline let rows: ClosedRange<Int>

    /// Makes the range from its columns and rows.
    @inlinable
    init(columns: ClosedRange<Int>, rows: ClosedRange<Int>) {
        self.columns = columns
        self.rows = rows
    }

    /// The number of cells in the range.
    @usableFromInline var cellCount: Int { columns.count * rows.count }

    /// Returns `true` if the range holds `cell`.
    @inlinable
    func contains(_ cell: GridCell) -> Bool {
        columns.contains(cell.column) && rows.contains(cell.row)
    }
}
