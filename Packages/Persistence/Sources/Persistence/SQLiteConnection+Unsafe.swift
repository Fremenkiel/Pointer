import SQLite3
import os

/// One SQLite connection with the settings of storage.md section 3.1.
///
/// It is not `Sendable`. One actor owns it and runs all of its calls on its serial executor
/// (architecture.md section 11). SQL text is a `StaticString`, so no value can become part of it
/// (SAFE-10). Each value goes through a bound parameter of a `SQLiteStatement`.
final class SQLiteConnection {
    /// How a connection opens its file.
    enum Mode {
        /// Read and write. Makes the file if it does not exist.
        case readWrite
        /// Read only. The file must exist.
        case readOnly
    }

    /// The page size of each library file (storage.md section 7.5).
    static let pageSize: Int64 = 4096
    /// The value of `PRAGMA auto_vacuum` for `INCREMENTAL`, from the SQLite documentation.
    static let incrementalVacuum: Int64 = 2

    /// Safe: `sqlite3_open_v2` gives the handle, and only `deinit` closes it. Each statement
    /// holds a strong reference to this connection, so the handle outlives all statements.
    let handle: OpaquePointer
    private let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Persistence")
    /// The pages of the WAL after the last commit of this connection, from the WAL hook.
    private let walCounter = WALCounter()

    /// Opens the database at `path` and applies the connection settings.
    ///
    /// A new file gets `PRAGMA page_size = 4096` and `PRAGMA auto_vacuum = INCREMENTAL` before
    /// any table exists. A read-only connection keeps the journal mode of the file.
    ///
    /// - Precondition: `path` is not empty.
    /// - Throws: `PersistenceError.sqlite` if the file does not open or a setting fails, and
    ///   `PersistenceError.settingRefused` if the file does not take the WAL journal mode.
    init(path: String, mode: Mode) throws(PersistenceError) {
        precondition(!path.isEmpty, "A database path must not be empty")
        var opened: OpaquePointer?
        let access =
            mode == .readWrite ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY
        let code = sqlite3_open_v2(path, &opened, access | SQLITE_OPEN_EXRESCODE, nil)
        guard code == SQLITE_OK, let opened else {
            let message =
                opened.map { String(cString: sqlite3_errmsg($0)) }
                ?? String(cString: sqlite3_errstr(code))
            // SQLite gives a handle also for a failed open, and the handle must be closed.
            sqlite3_close_v2(opened)
            throw .sqlite(code: code, message: message)
        }
        handle = opened
        try configure(mode)
    }

    deinit {
        let code = sqlite3_close_v2(handle)
        if code != SQLITE_OK {
            logger.fault("Closing the database failed with code \(code)")
        }
    }

    /// The pages of the WAL file after the last commit of this connection. It is 0 before
    /// `trackWALPages()` and after a commit that restarted the WAL.
    var walPages: Int { walCounter.pages }

    /// Counts the pages of the WAL after each commit, and so turns off the automatic checkpoint
    /// of SQLite (D-146).
    ///
    /// A connection has one WAL hook, and the automatic checkpoint is that hook
    /// (`sqlite3_wal_autocheckpoint`, <https://sqlite.org/c3ref/wal_hook.html>). The owner runs
    /// the checkpoints instead.
    ///
    /// - Precondition: The connection can write.
    func trackWALPages() {
        precondition(sqlite3_db_readonly(handle, "main") == 0, "Only a write connection has a WAL")
        assert(walCounter.pages == 0, "The WAL hook is set once")
        // Safe: the counter is a property of this connection, so it lives until `deinit` closes
        // the handle, and SQLite calls the hook only during a commit of this handle.
        sqlite3_wal_hook(
            handle,
            { context, _, _, pages in
                guard let context else { return SQLITE_OK }
                Unmanaged<WALCounter>.fromOpaque(context).takeUnretainedValue().pages = Int(pages)
                return SQLITE_OK
            },
            Unmanaged.passUnretained(walCounter).toOpaque()
        )
    }

    /// The outcome of a passive checkpoint.
    enum CheckpointOutcome: Equatable {
        /// The checkpoint copied all pages of the WAL.
        case complete
        /// The checkpoint copied some pages: a reader holds older pages, or new pages came.
        case partial
        /// Another connection runs a checkpoint, so this one did not run.
        case busy
    }

    /// Runs a passive checkpoint: it copies the pages of the WAL into the database without a wait
    /// for readers or writers, and syncs (<https://sqlite.org/c3ref/wal_checkpoint_v2.html>).
    /// SQLite gives `SQLITE_BUSY` at once if another connection holds the checkpoint lock, and
    /// calls no busy handler then.
    ///
    /// - Precondition: The connection can write.
    /// - Returns: Whether the checkpoint copied all pages, some pages, or did not run.
    /// - Throws: `PersistenceError.sqlite` if the checkpoint fails.
    func checkpointPassive() throws(PersistenceError) -> CheckpointOutcome {
        precondition(
            sqlite3_db_readonly(handle, "main") == 0,
            "Only a write connection checkpoints"
        )
        var logPages: Int32 = 0
        var copiedPages: Int32 = 0
        let code = sqlite3_wal_checkpoint_v2(
            handle,
            nil,
            SQLITE_CHECKPOINT_PASSIVE,
            &logPages,
            &copiedPages
        )
        guard code != SQLITE_BUSY else { return .busy }
        try check(code, expected: SQLITE_OK)
        assert(copiedPages <= logPages, "A checkpoint copies at most the WAL")
        return copiedPages == logPages ? .complete : .partial
    }

    /// Runs SQL without parameters and without result rows, for example a pragma or a schema.
    ///
    /// - Throws: `PersistenceError.sqlite` with the SQLite message if a statement fails.
    func execute(_ sql: StaticString) throws(PersistenceError) {
        try check(sqlite3_exec(handle, sql.description, nil, nil, nil), expected: SQLITE_OK)
    }

    /// Compiles one SQL statement for reuse.
    ///
    /// - Precondition: `sql` holds exactly one statement.
    /// - Throws: `PersistenceError.sqlite` with the SQLite message if the SQL does not compile.
    func prepare(_ sql: StaticString) throws(PersistenceError) -> SQLiteStatement {
        var statement: OpaquePointer?
        var rest = ""
        // The tail points into the C string of the SQL text, which lives only in this closure.
        let code = sql.description.withCString { text in
            var tail: UnsafePointer<CChar>?
            let flags = UInt32(SQLITE_PREPARE_PERSISTENT)
            let code = sqlite3_prepare_v3(handle, text, -1, flags, &statement, &tail)
            rest = tail.map { String(cString: $0) } ?? ""
            return code
        }
        try check(code, expected: SQLITE_OK)
        guard let statement else { preconditionFailure("SQL \(sql) holds no statement") }
        let compiled = SQLiteStatement(connection: self, handle: statement)
        precondition(rest.allSatisfy(\.isWhitespace), "SQL \(sql) holds more than one statement")
        return compiled
    }

    /// Returns the integer value of the first column of the first row of `sql`.
    ///
    /// - Throws: `PersistenceError.sqlite` if the statement fails or gives no row.
    func integer(_ sql: StaticString) throws(PersistenceError) -> Int64 {
        let statement = try prepare(sql)
        precondition(statement.columnCount == 1, "SQL \(sql) must give one column")
        guard try statement.step() else {
            throw .sqlite(code: SQLITE_DONE, message: "\(sql) gave no row")
        }
        return statement.int64(at: 0)
    }

    /// Returns the text value of the first column of the first row of `sql`.
    ///
    /// - Throws: `PersistenceError.sqlite` if the statement fails or gives no text.
    func text(_ sql: StaticString) throws(PersistenceError) -> String {
        let statement = try prepare(sql)
        precondition(statement.columnCount == 1, "SQL \(sql) must give one column")
        guard try statement.step(), let value = statement.string(at: 0) else {
            throw .sqlite(code: SQLITE_DONE, message: "\(sql) gave no text")
        }
        return value
    }

    /// Throws the SQLite message if `code` is not `expected` (SAFE-10).
    ///
    /// - Throws: `PersistenceError.sqlite` with `code` and the text of `sqlite3_errmsg`.
    func check(_ code: Int32, expected: Int32) throws(PersistenceError) {
        guard code == expected else {
            throw .sqlite(code: code, message: String(cString: sqlite3_errmsg(handle)))
        }
    }

    private func configure(_ mode: Mode) throws(PersistenceError) {
        guard mode == .readWrite else {
            try execute(
                "PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 2000;"
            )
            return
        }
        // The page size and the vacuum mode take effect only before the first table exists.
        // SQLite ignores a page size that it cannot use, so the values are read back.
        if try integer("PRAGMA page_count") == 0 {
            try execute("PRAGMA page_size = 4096; PRAGMA auto_vacuum = INCREMENTAL;")
            let pageSize = try integer("PRAGMA page_size")
            guard pageSize == Self.pageSize else {
                throw .settingRefused(name: "page_size", value: "\(pageSize)")
            }
            let vacuum = try integer("PRAGMA auto_vacuum")
            guard vacuum == Self.incrementalVacuum else {
                throw .settingRefused(name: "auto_vacuum", value: "\(vacuum)")
            }
        }
        let journal = try text("PRAGMA journal_mode = WAL")
        guard journal == "wal" else { throw .settingRefused(name: "journal_mode", value: journal) }
        try execute(
            """
            PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON;
            PRAGMA auto_vacuum = INCREMENTAL; PRAGMA busy_timeout = 2000;
            """
        )
    }
}

/// The page count of the WAL of one connection. Only the WAL hook writes it, during a commit on
/// the executor of the owner of the connection, and only that owner reads it.
private final class WALCounter {
    var pages = 0
}
