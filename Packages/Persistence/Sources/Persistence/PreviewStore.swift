import Foundation
import Model
import os

/// The card previews in `Caches/Pointer/previews/<canvas-id>.png` (storage.md section 2, D-97).
///
/// The store reads, writes, and removes the files as `Data`. It does not decode them: `Rendering`
/// owns the PNG code (D-107). The actor runs on its own serial queue, so no file access runs on
/// the main actor or on the shared pool.
public actor PreviewStore {
    /// The largest file that a read takes. A larger file counts as damaged. A preview of 512 by
    /// 358 pixels took 9,202 bytes on the iPad (D-97), so the start value leaves room.
    public static let maxFileSize = 64 * 1024
    private static let fileExtension = "png"
    private static let partialExtension = "partial"

    private let folder: URL
    private let files = FileManager()
    private let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Persistence")
    private let queue = DispatchSerialQueue(label: "dk.saarikivi.pointer.previews")
    /// True after `close()`. A render that ends after the close of the composition must not
    /// write a preview of the old library into the cleared cache (D-157).
    private var isClosed = false

    /// The executor of the store: its own serial queue.
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// Makes a store for the files in `folder`. The first write makes the folder.
    ///
    /// - Precondition: `folder` is a file URL.
    public init(folder: URL) {
        precondition(folder.isFileURL, "The previews need a file URL, got \(folder)")
        self.folder = folder
    }

    /// Returns the stored preview of `canvas`.
    ///
    /// A file larger than `maxFileSize` or a file that does not read counts as damaged. The store
    /// removes it, logs the fault, and returns `nil`.
    ///
    /// - Returns: The bytes of the file, or `nil` if no valid file exists.
    public func read(_ canvas: CanvasID) -> Data? {
        let url = fileURL(of: canvas)
        guard files.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        guard let size, size <= Self.maxFileSize else {
            logger.error("Preview \(canvas.rawValue) of \(size ?? -1) bytes is damaged")
            removeDamaged(url)
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            assert(data.count <= Self.maxFileSize, "The read keeps the size limit")
            return data
        } catch {
            logger.error("Preview \(canvas.rawValue) does not read: \(error)")
            removeDamaged(url)
            return nil
        }
    }

    /// Writes the preview of `canvas`. The write goes to a temporary file in the same folder and
    /// then renames it, so a reader sees the old file or the new file, never a part.
    ///
    /// - Throws: `PersistenceError.fileFailed` if the data is empty or larger than
    ///   `maxFileSize`, or if the folder, the write, or the rename fails.
    public func write(_ data: Data, for canvas: CanvasID) throws(PersistenceError) {
        guard !isClosed else { throw .fileFailed(reason: "the preview store is closed") }
        guard !data.isEmpty, data.count <= Self.maxFileSize else {
            throw .fileFailed(reason: "preview of \(data.count) bytes is outside the limit")
        }
        let url = fileURL(of: canvas)
        let partial = url.appendingPathExtension(Self.partialExtension)
        do {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: partial)
        } catch {
            throw .fileFailed(reason: "cannot write preview \(canvas.rawValue): \(error)")
        }
        guard rename(partial.path(percentEncoded: false), url.path(percentEncoded: false)) == 0
        else {
            removeDamaged(partial)
            throw .fileFailed(reason: "cannot rename preview \(canvas.rawValue), errno \(errno)")
        }
        assert(files.fileExists(atPath: url.path(percentEncoded: false)), "The preview is in place")
    }

    /// Removes the preview of `canvas`. A missing file is no error.
    ///
    /// - Throws: `PersistenceError.fileFailed` if the file stays.
    public func remove(_ canvas: CanvasID) throws(PersistenceError) {
        let url = fileURL(of: canvas)
        guard files.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do {
            try files.removeItem(at: url)
        } catch {
            throw .fileFailed(reason: "cannot remove preview \(canvas.rawValue): \(error)")
        }
        assert(!files.fileExists(atPath: url.path(percentEncoded: false)), "The preview went")
    }

    /// Refuses each later write, for the close of the app composition before a restore. The
    /// writes that came before the close are done when it returns, because the store is an
    /// actor (D-157).
    public func close() {
        isClosed = true
    }

    /// Removes all previews, for the restore of M9 (storage.md section 7.5).
    ///
    /// - Throws: `PersistenceError.fileFailed` if the folder stays.
    public func removeAll() throws(PersistenceError) {
        guard files.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
        do {
            try files.removeItem(at: folder)
        } catch {
            throw .fileFailed(reason: "cannot remove the previews: \(error)")
        }
        assert(!files.fileExists(atPath: folder.path(percentEncoded: false)), "The folder went")
    }

    private func fileURL(of canvas: CanvasID) -> URL {
        folder.appending(path: canvas.rawValue.uuidString)
            .appendingPathExtension(Self.fileExtension)
    }

    /// Removes a damaged file or a partial file. A file that stays costs disk space only, and
    /// the next read or write tries again.
    private func removeDamaged(_ url: URL) {
        do {
            try files.removeItem(at: url)
        } catch {
            logger.error("A damaged or partial preview stays: \(error)")
        }
    }
}
