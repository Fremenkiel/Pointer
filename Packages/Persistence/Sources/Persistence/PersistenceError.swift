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
}
