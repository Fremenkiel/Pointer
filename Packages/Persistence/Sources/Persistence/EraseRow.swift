import Model

/// The SQL and the codec of the `stroke_erase` table (storage.md section 3.3, D-30).
enum EraseRow {
    /// The number of parameters of the write statement.
    static let parameterCount: Int32 = 4
    /// The number of columns of the read statement.
    static let columnCount: Int32 = 4

    /// Writes an erase record. An undo changes `modified` and `is_deleted` of the same row.
    static let upsert: StaticString = """
        INSERT INTO stroke_erase (stroke_id, erased, modified, is_deleted) VALUES (?, ?, ?, ?)
        ON CONFLICT (stroke_id) DO UPDATE SET modified = excluded.modified,
            is_deleted = excluded.is_deleted
        """

    // Only the tests read it (SCOPE-01).
    // swiftlint:disable unused_declaration
    /// Reads one erase record by stroke ID. The live load of a canvas never reads erase records
    /// (review A-07). Tests and the later change upload read them.
    static let selectByStroke: StaticString = """
        SELECT stroke_id, erased, modified, is_deleted FROM stroke_erase WHERE stroke_id = ?
        """
    // swiftlint:enable unused_declaration

    /// Binds `record` to the parameters of `upsert`.
    ///
    /// - Throws: `PersistenceError.sqlite` if a bind fails.
    static func bind(
        _ record: EraseRecord,
        to statement: SQLiteStatement
    ) throws(PersistenceError) {
        precondition(statement.parameterCount == parameterCount, "Not a erase record write")
        var binder = try RowBinder(statement)
        try binder.bind(record.strokeID)
        try binder.bind(record.erased)
        try binder.bind(record.modified)
        try binder.bind(record.isDeleted)
        assert(binder.count == statement.parameterCount, "Erase record binds all parameters")
    }

    // Only the tests read it (SCOPE-01).
    // swiftlint:disable unused_declaration
    /// Reads the current row of `selectByStroke`.
    ///
    /// - Throws: `PersistenceError.corruptRow` if a column does not give a valid record.
    static func read(from statement: SQLiteStatement) throws(PersistenceError) -> EraseRecord {
        // swiftlint:enable unused_declaration
        precondition(statement.columnCount == columnCount, "Not a erase record read")
        var reader = RowReader(statement, table: "stroke_erase")
        let strokeID: StrokeID = try reader.identifier()
        let erased = try reader.timestamp()
        let modified = try reader.timestamp()
        let isDeleted = try reader.flag()
        return EraseRecord(
            strokeID: strokeID,
            erased: erased,
            modified: modified,
            isDeleted: isDeleted
        )
    }
}
