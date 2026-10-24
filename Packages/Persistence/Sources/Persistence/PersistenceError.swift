/// The errors of the Persistence package (SAFE-04).
public enum PersistenceError: Error, Equatable, Sendable {
    /// A SQLite call returned an unexpected result code. The message is `sqlite3_errmsg`
    /// (SAFE-10).
    case sqlite(code: Int32, message: String)
    /// A string or a blob has more bytes than one SQLite value can hold.
    case valueTooLarge(byteCount: Int)
    /// A connection setting did not take its value, for example the WAL journal mode.
    case settingRefused(name: String, value: String)
    /// A stored value has the wrong length or form, for example a clock value of 27 bytes.
    case corruptValue(reason: String)
    /// A row of `table` cannot become a model value. The reason never holds user content.
    case corruptRow(table: String, reason: String)
    /// A database with schema version 0 already has tables, so it is not a Pointer library.
    case unknownSchema
    /// A file operation of a snapshot failed, for example the rename into `Backups/`.
    case fileFailed(reason: String)
    /// The disk has no room for the copy of a picked file or for a restore.
    case diskFull
    /// A picked file is not a SQLite database: it is too short, or its header lacks the magic
    /// text (D-162).
    case notADatabase
    /// A picked file has another page size than the 4,096 bytes of each library (storage.md
    /// section 7.5).
    case wrongPageSize(bytes: Int)
    /// A picked file is in WAL mode. A copy without its `-wal` file loses rows (D-162).
    case walMode
    /// A picked file has schema version 0 or less, so it is no Pointer library.
    case unknownVersion(Int64)
    /// A picked file comes from a newer version of Pointer (D-153).
    case newerSchema(version: Int64)
    /// The size of a picked file is not a whole number of pages, so the copy is incomplete.
    case incompleteFile(byteCount: Int)
    /// `PRAGMA integrity_check` found a fault in a picked file. The reason is its first row.
    case integrityFailed(reason: String)
    /// The app stopped a restore before its end, for example at the end of the extra time in
    /// the background. The library keeps its old content (D-164).
    case restoreStopped
    /// The tables, columns, indexes, views, or triggers of a picked file differ from the
    /// schema of its version (D-162, D-163). The reason names the first difference.
    case schemaMismatch(reason: String)
}
