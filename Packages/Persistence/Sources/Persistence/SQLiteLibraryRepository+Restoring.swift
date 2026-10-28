import Foundation
import Model
import SQLite3

extension SQLiteLibraryRepository {
    /// The pages of one step of the backup: 4 MB (task 1.4 of the M9 plan). The stop flag
    /// is read between two steps.
    static let restorePagesPerStep: Int32 = 1_024
    /// The tries of a step while another connection holds a lock, and the wait between two
    /// tries: 2 s, the `busy_timeout` of storage.md section 3.1 (FLOW-03).
    static let maxRestoreRetries = 200
    private static let restoreRetryInterval = 0.010

    /// Replaces the content of the library with a checked snapshot, and closes the library
    /// (storage.md section 7.5, D-148).
    ///
    /// The restore waits for the running checkpoint and drops all statements, so that no read
    /// is open. Then it copies the snapshot with the backup API in steps of
    /// `restorePagesPerStep` pages and reads `stop` between two steps. After the copy, a
    /// `TRUNCATE` checkpoint empties the WAL, because the backup does not call the WAL hook.
    /// The library is closed after the call, also after a failure. The app opens it again in a
    /// new composition, which runs the migrations of an older snapshot.
    ///
    /// A closed library takes a restore too, for example after an open that failed on the
    /// restored file: the restore then opens its own connection (task 2.2, item 4). A read-only
    /// library of a newer schema takes it with a connection that writes (D-168).
    ///
    /// - Precondition: No row waits for a save.
    /// - Throws: `PersistenceError.restoreStopped` after a stop, `.diskFull` for a full disk,
    ///   and `.sqlite` for another fault. A stop and a fault before the end of the copy roll it
    ///   back, so the library keeps its old content. After the end of the copy, the library
    ///   holds the snapshot, and a failed checkpoint is only logged.
    public func restore(
        from snapshot: CheckedSnapshot,
        stop: RestoreStop
    ) async throws(PersistenceError) {
        precondition(pending.isEmpty, "A restore drops \(pending.count) pending rows")
        scheduledSave?.cancel()
        scheduledSave = nil
        // The backup refuses a destination with an open read, and a send during the wait for
        // the checkpoint must fail. Statements of the old schema must not stay either.
        statements = nil
        await checkpointRequest?.value
        // The connection of a newer schema opens read-only, so the copy needs its own (D-168).
        if isReadOnly { connection = nil }
        defer { dropConnection() }
        let destination = try openDestination()
        let source = try SQLiteConnection(
            path: snapshot.file.path(percentEncoded: false),
            mode: .untrustedReadOnly
        )
        let interval = signposter.beginInterval("Restore")
        defer { signposter.endInterval("Restore", interval) }
        try copy(from: source, to: destination, steps: try maxSteps(of: snapshot), stop: stop)
        do {
            try destination.checkpointTruncate()
        } catch {
            // The copy is in the WAL, so the library holds the snapshot. A reader can hold the
            // checkpoint for the 2 s of `busy_timeout`, and the next open copies the WAL back.
            logger.error("The checkpoint after the restore failed: \(error)")
        }
        assert(statements == nil, "No statement of the old library stays")
    }

    /// Returns the connection of the open library, or a new one to the file of a closed one.
    private func openDestination() throws(PersistenceError) -> SQLiteConnection {
        if let connection { return connection }
        return try SQLiteConnection(path: configuration.databasePath, mode: .readWrite)
    }

    /// Returns the most steps of the copy of `snapshot`: its pages over the pages of one step.
    private func maxSteps(of snapshot: CheckedSnapshot) throws(PersistenceError) -> Int {
        let path = snapshot.file.path(percentEncoded: false)
        guard let size = try? FileManager().attributesOfItem(atPath: path)[.size] as? Int else {
            throw .fileFailed(reason: "cannot read the size of the snapshot")
        }
        let stepBytes = Int(Self.restorePagesPerStep) * Int(SQLiteConnection.pageSize)
        return size / stepBytes + 1
    }

    /// Copies `source` into `destination` in steps. A stop or a fault finishes the backup
    /// before its end, which rolls the copy back (D-164).
    private func copy(
        from source: SQLiteConnection,
        to destination: SQLiteConnection,
        steps: Int,
        stop: RestoreStop
    ) throws(PersistenceError) {
        precondition(steps > 0, "A copy takes at least one step")
        let backup = try SQLiteBackup(from: source, to: destination)
        var retries = 0
        for _ in 0..<(steps + Self.maxRestoreRetries) {
            guard !stop.isStopped else {
                try backup.finish()
                throw .restoreStopped
            }
            let outcome = try backup.step(pages: Self.restorePagesPerStep)
            if outcome == .done { return try backup.finish() }
            if outcome == .busy {
                retries += 1
                guard retries <= Self.maxRestoreRetries else { break }
                Thread.sleep(forTimeInterval: Self.restoreRetryInterval)
            }
        }
        logger.error("The restore did not end after \(steps) steps and \(retries) retries")
        throw .sqlite(code: SQLITE_BUSY, message: "the restore did not end")
    }
}
