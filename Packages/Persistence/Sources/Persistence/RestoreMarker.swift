import Foundation
import os

/// The mark of a restore in progress, a file next to the library that names the pre-restore
/// snapshot (D-180, storage.md section 7.5).
///
/// The restore writes it after the pre-restore snapshot exists and before the copy starts. A
/// launch that finds it and a library that does not open restores that snapshot. A good open
/// of the library removes it. The way back of D-20 thus also works after a stop of the process.
public struct RestoreMarker: Sendable {
    /// The path of the marker file.
    public let path: String
    /// The folder of the snapshots.
    public let backupsFolder: URL

    private static let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Persistence")

    /// Makes the marker of the library at `libraryPath`, whose snapshots lie in `backupsFolder`.
    ///
    /// - Precondition: `libraryPath` is not empty.
    public init(libraryPath: String, backupsFolder: URL) {
        precondition(!libraryPath.isEmpty, "A library has a path")
        path = libraryPath + ".restoring"
        self.backupsFolder = backupsFolder
    }

    /// Writes the name of the pre-restore snapshot and flushes it to the disk with `fsync`, so
    /// that a stop of the process or of the device right after it keeps the marker.
    ///
    /// - Precondition: `snapshot` has the name of a pre-restore snapshot.
    /// - Throws: `PersistenceError.fileFailed` if the file does not write.
    public func write(snapshot: URL) throws(PersistenceError) {
        let name = snapshot.lastPathComponent
        precondition(SnapshotFiles.isPreRestore(name), "\(name) is no pre-restore snapshot")
        let url = URL(filePath: path)
        do {
            try Data(name.utf8).write(to: url)
            let handle = try FileHandle(forWritingTo: url)
            // `synchronize()` calls `fsync`, which flushes the file to the disk.
            try handle.synchronize()
            try handle.close()
        } catch {
            throw .fileFailed(reason: "cannot write the restore marker: \(error)")
        }
    }

    /// Returns the pre-restore snapshot that the marker names, or `nil` without a marker. A
    /// marker that does not name a pre-restore snapshot, or names one that is gone, is damaged:
    /// it gives `nil`, and the log has the fault.
    public func snapshot() -> URL? {
        guard let data = FileManager().contents(atPath: path) else { return nil }
        let name = String(bytes: data, encoding: .utf8) ?? ""
        let url = backupsFolder.appending(path: name)
        guard SnapshotFiles.isPreRestore(name),
            FileManager().fileExists(atPath: url.path(percentEncoded: false))
        else {
            Self.logger.fault("The restore marker names no pre-restore snapshot: \(name)")
            return nil
        }
        return url
    }

    /// Removes the marker. A missing marker is no error.
    ///
    /// - Throws: `PersistenceError.fileFailed` if the marker stays.
    public func remove() throws(PersistenceError) {
        guard FileManager().fileExists(atPath: path) else { return }
        do {
            try FileManager().removeItem(atPath: path)
        } catch {
            throw .fileFailed(reason: "cannot remove the restore marker: \(error)")
        }
    }
}
