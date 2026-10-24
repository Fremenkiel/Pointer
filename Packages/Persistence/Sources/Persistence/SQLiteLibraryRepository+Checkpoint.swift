import Foundation

extension SQLiteLibraryRepository {
    /// The WAL pages after which the checkpointer runs: the default of the automatic checkpoint
    /// of SQLite (SQLITE_DEFAULT_WAL_AUTOCHECKPOINT, <https://sqlite.org/wal.html>).
    static let checkpointPages = 1_000
    /// The WAL pages after which the write connection runs the checkpoint itself, in case the
    /// checkpointer falls behind (D-146).
    static let checkpointHardLimitPages = 8_000

    /// Starts a checkpoint after a commit if the WAL is large (D-146).
    ///
    /// At `checkpointPages`, the checkpointer runs one off the save path. At
    /// `checkpointHardLimitPages`, the write connection runs one now. A failure is only logged,
    /// because the commit already holds the rows.
    func checkpointIfNeeded() {
        guard let connection else { preconditionFailure("A checkpoint needs an open library") }
        let pages = connection.walPages
        guard pages < Self.checkpointHardLimitPages else {
            do {
                _ = try connection.checkpointPassive()
            } catch {
                logger.error("The checkpoint at the hard limit failed: \(error)")
            }
            return
        }
        guard pages >= Self.checkpointPages, checkpointRequest == nil, let checkpointer else {
            return
        }
        checkpointRequest = Task { [weak self] in
            await checkpointer.checkpoint()
            await self?.checkpointDidEnd()
        }
        assert(checkpointRequest != nil, "A large WAL starts one checkpoint")
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
