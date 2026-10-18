/// The errors of the Persistence package (SAFE-04).
public enum PersistenceError: Error, Equatable, Sendable {
    /// A SQLite call returned an unexpected result code. The message is `sqlite3_errmsg`
    /// (SAFE-10).
    case sqlite(code: Int32, message: String)
    /// A string or a blob has more bytes than one SQLite value can hold.
    case valueTooLarge(byteCount: Int)
    /// A connection setting did not take its value, for example the WAL journal mode.
    case settingRefused(name: String, value: String)
}
