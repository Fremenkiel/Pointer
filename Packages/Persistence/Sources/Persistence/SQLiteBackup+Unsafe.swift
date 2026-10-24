import SQLite3

/// One run of the SQLite online backup API, from a checked snapshot into the live library
/// (storage.md section 7.5, D-148, <https://www.sqlite.org/c3ref/backup_finish.html>).
///
/// It is not `Sendable`. The repository owns it for the time of one restore, on its executor.
final class SQLiteBackup {
    /// The result of one step.
    enum StepOutcome: Equatable {
        /// The step copied its pages, and more pages wait.
        case more
        /// The copy is complete.
        case done
        /// Another connection holds a lock. The step can run again.
        case busy
    }

    /// The low 8 bits of an extended result code hold the primary code
    /// (<https://www.sqlite.org/rescode.html>).
    private static let primaryCodeMask: Int32 = 0xFF

    /// Keeps both connections open while the backup exists.
    private let source: SQLiteConnection
    private let destination: SQLiteConnection
    /// Safe: `sqlite3_backup_init` gives the handle, and only `finish()` or `deinit` frees it,
    /// once. Both connections outlive it, because the backup holds them.
    private var handle: OpaquePointer?

    /// Starts a backup of the `main` database of `source` into the `main` database of
    /// `destination`.
    ///
    /// - Precondition: The two connections differ.
    /// - Throws: `PersistenceError.sqlite` with the message of the destination, for example
    ///   "destination database is in use" while a statement of the destination holds a read.
    init(from source: SQLiteConnection, to destination: SQLiteConnection) throws(PersistenceError) {
        precondition(source !== destination, "A backup needs two connections")
        self.source = source
        self.destination = destination
        handle = sqlite3_backup_init(destination.handle, "main", source.handle, "main")
        guard handle != nil else {
            let code = sqlite3_errcode(destination.handle)
            throw .sqlite(code: code, message: String(cString: sqlite3_errmsg(destination.handle)))
        }
    }

    deinit {
        // A backup that did not finish rolls back here, and the error is the one of the step.
        if let handle { sqlite3_backup_finish(handle) }
    }

    /// Copies the next `pages` pages.
    ///
    /// - Precondition: `pages` is positive, and the backup did not finish.
    /// - Returns: Whether more pages wait, the copy is complete, or a lock stopped the step.
    /// - Throws: `PersistenceError.diskFull` for `SQLITE_FULL`, and `PersistenceError.sqlite`
    ///   for another error. The copy then cannot go on, and `finish()` rolls it back.
    func step(pages: Int32) throws(PersistenceError) -> StepOutcome {
        precondition(pages > 0, "A step copies at least one page, got \(pages)")
        guard let handle else { preconditionFailure("The backup finished already") }
        let code = sqlite3_backup_step(handle, pages)
        switch code & Self.primaryCodeMask {
        case SQLITE_OK: return .more
        case SQLITE_DONE: return .done
        case SQLITE_BUSY, SQLITE_LOCKED: return .busy
        case SQLITE_FULL: throw .diskFull
        default:
            throw .sqlite(code: code, message: String(cString: sqlite3_errstr(code)))
        }
    }

    /// Ends the backup. Before `.done`, the end rolls the copy back, so the destination keeps
    /// its old content (D-164).
    ///
    /// - Precondition: The backup did not finish yet.
    /// - Throws: `PersistenceError.sqlite` if the end reports an error of the copy.
    func finish() throws(PersistenceError) {
        guard let handle else { preconditionFailure("The backup finished already") }
        self.handle = nil
        try destination.check(sqlite3_backup_finish(handle), expected: SQLITE_OK)
    }
}
