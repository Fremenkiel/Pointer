import Foundation
import os

/// The file steps of `SnapshotImport`: the copy of a picked file and the read of its header.
enum SnapshotCopy {
    /// The POSIX code of a full disk.
    private static let noSpace = Int(ENOSPC)
    private static let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Persistence")

    /// Copies `picked` to `copy` inside its security scope, with a coordinated read (D-156).
    ///
    /// The coordinated read downloads a file of a provider, for example iCloud Drive, before it
    /// gives the URL (<https://developer.apple.com/documentation/foundation/nsfilecoordinator>).
    ///
    /// - Precondition: `copy` does not exist yet.
    /// - Throws: `PersistenceError.diskFull` if the disk has no room, and
    ///   `PersistenceError.fileFailed` for another fault of the read or the copy.
    static func copy(_ picked: URL, to copy: URL) throws(PersistenceError) {
        let files = FileManager()
        precondition(copy.path.hasSuffix(LibraryMaintenance.partialSuffix), "Not a copy: \(copy)")
        precondition(!files.fileExists(atPath: copy.path(percentEncoded: false)), "\(copy)")
        // A URL of the document picker needs its scope. A URL of the own container has none,
        // and the call then returns false.
        let isScoped = picked.startAccessingSecurityScopedResource()
        defer { if isScoped { picked.stopAccessingSecurityScopedResource() } }
        var coordination: NSError?
        var failure: (any Error)?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: picked,
            options: [.withoutChanges],
            error: &coordination
        ) { readable in
            do {
                try files.copyItem(at: readable, to: copy)
            } catch {
                failure = error
            }
        }
        guard let error = failure ?? coordination else { return }
        throw isDiskFull(error) ? .diskFull : .fileFailed(reason: "cannot copy the file: \(error)")
    }

    /// Returns the first `SnapshotHeader.length` bytes of `file`, or fewer for a short file.
    ///
    /// - Throws: `PersistenceError.fileFailed` if the file does not read.
    static func header(of file: URL) throws(PersistenceError) -> Data {
        precondition(file.isFileURL, "The header of a file, got \(file)")
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { close(handle) }
            let bytes = try handle.read(upToCount: SnapshotHeader.length) ?? Data()
            assert(bytes.count <= SnapshotHeader.length, "The read keeps the header length")
            return bytes
        } catch {
            throw .fileFailed(reason: "cannot read the header: \(error)")
        }
    }

    /// Returns true if `error` or its underlying error says that the disk is full.
    static func isDiskFull(_ error: any Error) -> Bool {
        let error = error as NSError
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        return (error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError)
            || [error, underlying].contains {
                $0?.domain == NSPOSIXErrorDomain && $0?.code == noSpace
            }
    }

    /// Closes a read handle. A failed close loses no data, so it is only logged.
    private static func close(_ handle: FileHandle) {
        do {
            try handle.close()
        } catch {
            logger.error("The header read did not close: \(error)")
        }
    }
}
