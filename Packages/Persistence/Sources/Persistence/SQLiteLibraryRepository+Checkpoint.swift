import Foundation

extension SQLiteLibraryRepository {
    /// The WAL pages after which the checkpointer runs: the default of the automatic checkpoint
    /// of SQLite (SQLITE_DEFAULT_WAL_AUTOCHECKPOINT, <https://sqlite.org/wal.html>).
    static let checkpointPages = 1_000
    /// The WAL pages after which the write connection runs the checkpoint itself if the
    /// checkpointer is busy, because it falls behind (D-146, D-147).
    static let checkpointHardLimitPages = 8_000
    /// The wait between two tries of the write connection while the checkpointer holds the
    /// checkpoint lock, and the most tries: 2 s, the `busy_timeout` of storage.md section 3.1.
    static let checkpointRetryInterval = 0.010
    static let maxCheckpointRetries = 200

    /// Starts a checkpoint after a commit if the WAL is large (D-146, D-147).
    ///
    /// From `checkpointPages`, an idle checkpointer gets the checkpoint, also past the hard limit,
    /// so the save does not wait. The checkpointer falls behind if the WAL grows by
    /// `checkpointPages` or more while one of its checkpoints runs. Then, from
    /// `checkpointHardLimitPages`, the write connection waits for it and runs the checkpoint
    /// itself. A failure is only logged, because the commit already holds the rows.
    func checkpointIfNeeded() {
        guard let connection else { preconditionFailure("A checkpoint needs an open library") }
        let pages = connection.walPages
        guard pages >= Self.checkpointPages else { return }
        if let checkpointer, checkpointRequest == nil {
            checkpointStartPages = pages
            checkpointRequest = Task { [weak self] in
                await checkpointer.checkpoint()
                await self?.checkpointDidEnd()
            }
            return
        }
        let fallsBehind =
            checkpointer == nil || pages - checkpointStartPages >= Self.checkpointPages
        guard pages >= Self.checkpointHardLimitPages, fallsBehind else { return }
        checkpointOnWriteConnection(connection)
    }

    /// Runs a passive checkpoint on the write connection. While the checkpointer holds the
    /// checkpoint lock, SQLite gives `SQLITE_BUSY` at once, so the save waits and tries again.
    private func checkpointOnWriteConnection(_ connection: SQLiteConnection) {
        let before = writeConnectionCheckpoints
        defer { assert(writeConnectionCheckpoints <= before + 1, "One checkpoint per commit") }
        for _ in 0..<Self.maxCheckpointRetries {
            do {
                guard try connection.checkpointPassive() == .busy else {
                    writeConnectionCheckpoints += 1
                    return
                }
            } catch {
                logger.error("The checkpoint at the hard limit failed: \(error)")
                return
            }
            Thread.sleep(forTimeInterval: Self.checkpointRetryInterval)
        }
        logger.error("The checkpoint at the hard limit waited 2 s for the checkpointer")
    }

    /// Lets the next large WAL start a checkpoint.
    private func checkpointDidEnd() {
        checkpointRequest = nil
    }

    /// The pages of the WAL after the last commit. Tests use it.
    var walPageCount: Int { connection?.walPages ?? 0 }

    /// Waits until the running checkpoint of the checkpointer ends. Tests use it.
    func waitForCheckpoint() async {
        await checkpointRequest?.value
    }
}
