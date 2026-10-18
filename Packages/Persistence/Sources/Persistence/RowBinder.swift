import Foundation
import Model

/// Binds the values of one row to the parameters of a statement in order, from parameter 1.
struct RowBinder {
    private let statement: SQLiteStatement
    private var index: Int32 = 1

    /// Resets `statement` and starts at its first parameter.
    ///
    /// - Throws: `PersistenceError.sqlite` if the reset fails.
    init(_ statement: SQLiteStatement) throws(PersistenceError) {
        try statement.reset()
        self.statement = statement
    }

    /// The number of bound parameters.
    var count: Int32 { index - 1 }

    /// Binds an integer.
    mutating func bind(_ value: Int64) throws(PersistenceError) {
        try statement.bind(value, at: index)
        index += 1
    }

    /// Binds a floating-point number.
    mutating func bind(_ value: Double) throws(PersistenceError) {
        try statement.bind(value, at: index)
        index += 1
    }

    /// Binds text, or NULL for `nil`.
    mutating func bind(_ value: String?) throws(PersistenceError) {
        defer { index += 1 }
        guard let value else { return try statement.bindNull(at: index) }
        try statement.bind(value, at: index)
    }

    /// Binds a flag as 0 or 1.
    mutating func bind(_ value: Bool) throws(PersistenceError) {
        try bind(Int64(value ? 1 : 0))
    }

    /// Binds the 28-byte form of a clock value.
    mutating func bind(_ value: HybridTimestamp) throws(PersistenceError) {
        try statement.bind(ValueCodec.data(value), at: index)
        index += 1
    }

    /// Binds the 16-byte form of an ID.
    mutating func bind(_ value: some EntityIdentifier) throws(PersistenceError) {
        try statement.bind(ValueCodec.data(value), at: index)
        index += 1
    }

    /// Binds the `created`, `modified`, and `is_deleted` columns of a record.
    mutating func bind(_ meta: RecordMeta) throws(PersistenceError) {
        try bind(meta.created)
        try bind(meta.modified)
        try bind(meta.isDeleted)
    }

    /// Binds the point BLOB of a stroke.
    mutating func bind(_ value: InkPoints) throws(PersistenceError) {
        try statement.bind(value, at: index)
        index += 1
    }
}
