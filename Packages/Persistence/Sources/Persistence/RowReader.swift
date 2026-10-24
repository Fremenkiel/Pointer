import Foundation
import Geometry
import Model

/// Reads the columns of the current row of a statement in order, from column 0.
///
/// Each read checks the stored form. A bad value throws `PersistenceError.corruptRow` with the
/// table name and never with user content.
struct RowReader {
    private let statement: SQLiteStatement
    private let table: String
    private var column: Int32 = 0

    /// Starts at the first column of the current row of `statement`.
    init(_ statement: SQLiteStatement, table: String) {
        self.statement = statement
        self.table = table
    }

    /// Reads an integer.
    ///
    /// - Throws: `PersistenceError.corruptRow` for NULL.
    mutating func int64() throws(PersistenceError) -> Int64 {
        defer { column += 1 }
        guard !statement.isNull(at: column) else { throw corrupt("NULL integer") }
        return statement.int64(at: column)
    }

    /// Reads a finite floating-point number.
    ///
    /// - Throws: `PersistenceError.corruptRow` for NULL or a value that is not finite.
    mutating func double() throws(PersistenceError) -> Double {
        defer { column += 1 }
        let value = statement.double(at: column)
        guard !statement.isNull(at: column), value.isFinite else { throw corrupt("bad number") }
        return value
    }

    /// Reads text, or `nil` for NULL.
    ///
    /// - Throws: `PersistenceError.corruptRow` for bytes that are not UTF-8.
    mutating func optionalString() throws(PersistenceError) -> String? {
        defer { column += 1 }
        guard !statement.isNull(at: column) else { return nil }
        guard let value = statement.string(at: column) else { throw corrupt("text is not UTF-8") }
        return value
    }

    /// Reads text.
    ///
    /// - Throws: `PersistenceError.corruptRow` for NULL or bytes that are not UTF-8.
    mutating func string() throws(PersistenceError) -> String {
        guard let value = try optionalString() else { throw corrupt("NULL text") }
        return value
    }

    /// Reads a flag that is stored as 0 or 1.
    ///
    /// - Throws: `PersistenceError.corruptRow` for another value.
    mutating func flag() throws(PersistenceError) -> Bool {
        let value = try int64()
        guard value == 0 || value == 1 else { throw corrupt("flag \(value)") }
        return value == 1
    }

    /// Reads a clock value.
    ///
    /// - Throws: `PersistenceError.corruptRow` for NULL or a length other than 28 bytes.
    mutating func timestamp() throws(PersistenceError) -> HybridTimestamp {
        try decode { (statement, column) throws(PersistenceError) in
            try statement.timestamp(at: column)
        }
    }

    /// Reads an ID.
    ///
    /// - Throws: `PersistenceError.corruptRow` for NULL or a length other than 16 bytes.
    mutating func identifier<ID: EntityIdentifier>(
        _ type: ID.Type = ID.self
    ) throws(PersistenceError) -> ID {
        ID(
            rawValue: try decode { (statement, column) throws(PersistenceError) in
                try statement.uuid(at: column)
            }
        )
    }

    /// Reads the `created`, `modified`, and `is_deleted` columns of a record.
    ///
    /// - Throws: `PersistenceError.corruptRow` for a bad clock value or flag.
    mutating func meta() throws(PersistenceError) -> RecordMeta {
        let created = try timestamp()
        let modified = try timestamp()
        return RecordMeta(created: created, modified: modified, isDeleted: try flag())
    }

    /// Reads a sort key.
    ///
    /// - Throws: `PersistenceError.corruptRow` for NULL or a key that is not valid.
    mutating func sortKey() throws(PersistenceError) -> FractionalIndex {
        let rawValue = try string()
        return try make { () throws(ModelError) in try FractionalIndex(rawValue: rawValue) }
    }

    /// Returns the model value that `make` builds, or a corrupt row if a limit check fails.
    ///
    /// - Throws: `PersistenceError.corruptRow` with the `ModelError` of `make`.
    func make<Value>(_ make: () throws(ModelError) -> Value) throws(PersistenceError) -> Value {
        do {
            return try make()
        } catch {
            throw corrupt("\(error)")
        }
    }

    /// Reads a point BLOB of `count` points.
    ///
    /// - Throws: `PersistenceError.corruptRow` for a count or a length that does not match, or
    ///   for a point that is not finite.
    mutating func inkPoints(count: Int) throws(PersistenceError) -> InkPoints {
        defer { column += 1 }
        let points: [InkPoint]
        do {
            points = try statement.inkPoints(at: column, count: count)
        } catch {
            throw corrupt("\(error)")
        }
        assert(points.count == count, "The BLOB gave \(points.count) of \(count) points")
        // A point that is not finite breaks the bounds of the stroke and the renderer.
        let isFinite = points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
        guard isFinite else { throw corrupt("point is not finite") }
        return InkPoints(points)
    }

    /// Refuses an item whose bounds are not finite or touch more than
    /// `Limits.maxGridCellsPerItem` grid cells, as a damaged row (D-158). Without the check, an
    /// item 10,000,000 points wide made the grid of the renderer visit 381 million cells.
    ///
    /// - Throws: `PersistenceError.corruptRow` for bounds past the limit.
    func checkGridBound(_ bounds: Rect) throws(PersistenceError) {
        let size = bounds.size
        guard bounds.origin.isFinite, size.width.isFinite, size.height.isFinite else {
            throw corrupt("bounds are not finite")
        }
        let cells = GridCell.count(covering: bounds, cellSize: Limits.gridCellSize)
        guard cells <= Limits.maxGridCellsPerItem else {
            throw corrupt("bounds touch \(cells) grid cells")
        }
    }

    /// Returns the error for a row of this table.
    func corrupt(_ reason: String) -> PersistenceError {
        .corruptRow(table: table, reason: reason)
    }

    /// Reads a value in place: `read` returns `nil` for NULL and throws for a bad form.
    private mutating func decode<Value>(
        _ read: (SQLiteStatement, Int32) throws(PersistenceError) -> Value?
    ) throws(PersistenceError) -> Value {
        precondition(column < statement.columnCount, "Column \(column) of \(table) is past the end")
        defer { column += 1 }
        let value: Value?
        do {
            value = try read(statement, column)
        } catch {
            throw corrupt("\(error)")
        }
        guard let value else { throw corrupt("NULL BLOB") }
        return value
    }
}
