import Foundation
import os

/// Runs the passive checkpoints of the library on a second connection, so that a save never
/// waits for the sync of a checkpoint (D-146, storage.md section 4).
///
/// The actor runs on its own serial queue. The SQLite documentation advises to "disable
/// automatic checkpointing and run the periodic checkpoints in a separate thread"
/// (<https://sqlite.org/wal.html>).
actor WALCheckpointer {
    private let queue = DispatchSerialQueue(
        label: "dk.saarikivi.pointer.checkpoint",
        qos: .utility
    )
    private let connection: SQLiteConnection
    private let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Persistence")
    /// The checkpoints that ran without an error.
    private(set) var completed = 0
    /// A test hook that runs before each checkpoint.
    private let beforeCheckpoint: (@Sendable () -> Void)?

    /// The executor of the checkpointer: its own serial queue.
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// Opens the second connection to the library at `path`.
    ///
    /// - Precondition: `path` is not empty.
    /// - Throws: `PersistenceError` if the file does not open.
    init(
        path: String,
        beforeCheckpoint: (@Sendable () -> Void)? = nil
    ) throws(PersistenceError) {
        precondition(!path.isEmpty, "The checkpointer needs a file path")
        connection = try SQLiteConnection(path: path, mode: .readWrite)
        self.beforeCheckpoint = beforeCheckpoint
    }

    /// Runs one passive checkpoint. A failure is only logged: the next save asks again, and the
    /// hard limit of the repository bounds the WAL (D-146).
    func checkpoint() {
        beforeCheckpoint?()
        do {
            _ = try connection.checkpointPassive()
            completed += 1
        } catch {
            logger.error("A checkpoint failed: \(error)")
        }
    }
}
