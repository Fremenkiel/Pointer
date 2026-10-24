/// The integer coordinates of one cell of a `SpatialGrid`.
public struct GridCell: Hashable, Sendable {
    /// The column. Column 0 starts at x = 0.
    public let column: Int
    /// The row. Row 0 starts at y = 0.
    public let row: Int

    /// Makes a cell coordinate.
    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }

    /// The largest cell coordinate. Coordinates further out land in the edge cells.
    public static var maxCoordinate: Int { 1 << 30 }

    /// Returns the cell coordinate of `value` in a grid of cells of `cellSize` points, clamped
    /// to the edge cells.
    @inlinable
    public static func coordinate(_ value: Double, cellSize: Double) -> Int {
        let limit = Double(maxCoordinate)
        let scaled = (value / cellSize).rounded(.down)
        return Int(min(max(scaled, -limit), limit))
    }

    /// Returns the number of cells of `cellSize` points that `bounds` touches, as
    /// `SpatialGrid.insert` visits them. A load checks it against its bound before an insert
    /// (D-158).
    ///
    /// - Precondition: `cellSize` is positive, and `bounds` is finite.
    public static func count(covering bounds: Rect, cellSize: Double) -> Int {
        precondition(cellSize > 0 && cellSize.isFinite, "Cell size \(cellSize)")
        precondition(bounds.origin.isFinite, "The bounds \(bounds) are not finite")
        let cell = { (value: Double) in coordinate(value, cellSize: cellSize) }
        let columns = cell(bounds.maxX) - cell(bounds.minX)
        let rows = cell(bounds.maxY) - cell(bounds.minY)
        // Each coordinate is at most 2^30 from 0, so the product stays far below Int.max.
        return (columns + 1) * (rows + 1)
    }
}
