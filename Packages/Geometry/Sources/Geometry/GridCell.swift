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
}
