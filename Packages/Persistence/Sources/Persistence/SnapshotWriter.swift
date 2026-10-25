import Foundation
import Model
import os

/// Writes the snapshots of the library: complete, consistent copies in `Documents/Backups/`
/// (storage.md section 7, D-32).
///
/// The actor runs on its own serial queue and opens its own read-only connection for each
/// snapshot. In WAL mode, the read does not block the writer, so saves continue while a snapshot
/// runs.
public actor SnapshotWriter {
    /// The files and the clock of the writer.
    public struct Configuration: Sendable {
        /// The path of `library.sqlite`.
        public let databasePath: String
        /// The folder of the partial files, `tmp/` of the app.
        public let temporaryFolder: URL
        /// The folder that the Files app shows, `Documents/Backups/`.
        public let backupsFolder: URL
        /// The wall clock for the names and the age of the snapshots.
        public let wallClock: any WallClock
        /// The time zone of the snapshot names. The app gives the zone of the device.
        public let timeZone: TimeZone

        /// Makes a configuration.
        public init(
            databasePath: String,
            temporaryFolder: URL,
            backupsFolder: URL,
            wallClock: any WallClock,
            timeZone: TimeZone
        ) {
            self.databasePath = databasePath
            self.temporaryFolder = temporaryFolder
            self.backupsFolder = backupsFolder
            self.wallClock = wallClock
            self.timeZone = timeZone
        }
    }

    private static let millisPerSecond = 1000.0

    private let configuration: Configuration
    private let files: SnapshotFiles
    /// A test hook that runs after `VACUUM INTO` and before the rename (storage.md section 9).
    private let beforeRename: (@Sendable () throws(PersistenceError) -> Void)?
    private let signposter = OSSignposter(
        subsystem: "dk.saarikivi.pointer",
        category: "Persistence"
    )
    private let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Persistence")
    private let queue = DispatchSerialQueue(label: "dk.saarikivi.pointer.snapshot")

    /// The executor of the writer: its own serial queue.
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// Makes a writer. It touches no file until a snapshot starts.
    public init(configuration: Configuration) {
        self.init(configuration: configuration, beforeRename: nil)
    }

    /// Makes a writer with a test hook before the rename.
    init(
        configuration: Configuration,
        beforeRename: (@Sendable () throws(PersistenceError) -> Void)?
    ) {
        precondition(!configuration.databasePath.isEmpty, "The writer needs a library path")
        precondition(configuration.backupsFolder.isFileURL, "Backups must be a file URL")
        self.configuration = configuration
        files = SnapshotFiles(
            backups: configuration.backupsFolder,
            temporary: configuration.temporaryFolder,
            timeZone: configuration.timeZone
        )
        self.beforeRename = beforeRename
    }

    /// Takes the idle signal of the app: 5 seconds without input and no pending rows
    /// (storage.md section 7.2). Makes a daily snapshot if the newest one is older than 24 hours.
    ///
    /// - Returns: The new snapshot, or `nil` if none is due.
    /// - Throws: `PersistenceError` if the snapshot fails. The next idle signal tries again.
    @discardableResult  // The app needs only the error. Tests read the URL.
    public func appIsIdle() throws(PersistenceError) -> URL? {
        guard try isDailySnapshotDue() else { return nil }
        return try writeSnapshotNow()
    }

    /// Returns true if no daily snapshot exists or the newest one is older than 24 hours.
    ///
    /// - Throws: `PersistenceError.fileFailed` if `Backups/` does not list.
    public func isDailySnapshotDue() throws(PersistenceError) -> Bool {
        guard let newest = try files.dailySnapshots().first else { return true }
        return now().timeIntervalSince(newest.date) >= SnapshotFiles.interval
    }

    /// Writes a daily snapshot now and keeps the newest 7 (D-21), for the idle signal and for
    /// "Back up now" (D-155). If the name of this second exists, a counter joins it:
    /// `Pointer-<stamp>-2.sqlite`.
    ///
    /// - Returns: The snapshot in `Backups/`. A failed delete of an old snapshot is only logged,
    ///   because the new snapshot exists, and the next snapshot deletes it.
    /// - Throws: `PersistenceError.sqlite` if `VACUUM INTO` fails, and
    ///   `PersistenceError.fileFailed` if the rename fails. `Backups/` then holds no new file,
    ///   and `tmp/` holds no partial file.
    public func writeSnapshotNow() throws(PersistenceError) -> URL {
        let date = now()
        let url = try write(as: files.freeDailyName(at: date), at: date)
        do {
            try files.removeOldSnapshots()
        } catch {
            logger.error("An old snapshot stays: \(error)")
        }
        assert(files.exists(url.lastPathComponent), "The new snapshot is missing")
        return url
    }

    /// Writes the snapshot before a restore, `Pointer-pre-restore-<stamp>.sqlite`, and then
    /// deletes the older pre-restore snapshots (D-154). The daily rotation does not count it.
    ///
    /// - Returns: The snapshot in `Backups/`. A failed delete of an older pre-restore snapshot
    ///   is only logged, because the new snapshot exists.
    /// - Throws: `PersistenceError` if the snapshot fails. The older snapshots then stay.
    public func writePreRestoreSnapshot() throws(PersistenceError) -> URL {
        let date = now()
        let url = try write(as: files.freePreRestoreName(at: date), at: date)
        do {
            try files.removePreRestoreSnapshots(except: url.lastPathComponent)
        } catch {
            logger.error("An older pre-restore snapshot stays: \(error)")
        }
        assert(SnapshotFiles.isPreRestore(url.lastPathComponent), "Not a pre-restore name")
        return url
    }

    /// Writes the snapshot before a migration from `oldVersion` (storage.md section 6). If a
    /// snapshot of that version exists from an earlier failed migration, it stays, because it
    /// holds the state before the first try.
    ///
    /// - Precondition: `oldVersion` is positive.
    /// - Throws: `PersistenceError` if the snapshot fails. The migration then does not run.
    public func writePreMigrationSnapshot(oldVersion: Int64) throws(PersistenceError) {
        precondition(oldVersion > 0, "Version \(oldVersion) has no data to save")
        let name = SnapshotFiles.preMigrationName(oldVersion: oldVersion)
        guard !files.exists(name) else { return }
        _ = try write(as: name, at: now())
    }

    /// Runs `VACUUM INTO` into a partial file in `tmp/`, then renames it into `Backups/`.
    private func write(as name: String, at date: Date) throws(PersistenceError) -> URL {
        precondition(name.hasSuffix(".sqlite"), "A snapshot name ends with .sqlite, got \(name)")
        let interval = signposter.beginInterval("Snapshot")
        defer { signposter.endInterval("Snapshot", interval) }
        let partial = configuration.temporaryFolder.appending(
            path: name + SnapshotFiles.partialExtension
        )
        let url: URL
        do {
            try vacuum(into: partial)
            try beforeRename?()
            url = try files.publish(partial, as: name, at: date)
        } catch {
            // A full disk leaves a file of 0 bytes, and a second run with its name fails
            // (<https://www.sqlite.org/lang_vacuum.html#vacuuminto>, D-155).
            removePartial(partial)
            throw error.isDiskFull ? .diskFull : error
        }
        logger.info("Wrote a snapshot")
        assert(url.lastPathComponent == name, "The snapshot has another name than \(name)")
        return url
    }

    private func vacuum(into partial: URL) throws(PersistenceError) {
        let connection = try SQLiteConnection(path: configuration.databasePath, mode: .readOnly)
        let vacuum = try connection.prepare("VACUUM INTO ?")
        try vacuum.bind(partial.path(percentEncoded: false), at: 1)
        try LibraryStatements.run(vacuum)
    }

    /// Deletes the partial file of a failed snapshot. A failed delete is only logged, because
    /// the error of the snapshot is the one to report, and the launch deletes the file later.
    private func removePartial(_ partial: URL) {
        do {
            try files.removePartial(partial)
        } catch {
            logger.error("The partial file of a failed snapshot stays: \(error)")
        }
    }

    private func now() -> Date {
        Date(
            timeIntervalSince1970: Double(configuration.wallClock.nowMillis())
                / Self.millisPerSecond
        )
    }
}
