import Foundation

/// The places of the files of the app (storage.md section 2).
struct AppFiles {
    /// `Library/Application Support/Pointer/library.sqlite`.
    let library: String
    /// `Library/Application Support/Pointer/device.sqlite`.
    let device: String
    /// `tmp/`, for the partial snapshot files.
    let temporary: URL
    /// `Documents/Backups/`, which the Files app shows (STO-02).
    let backups: URL
    /// `Library/Caches/Pointer/previews/`, the card previews (D-97). The first write makes it.
    let previews: URL

    /// Finds the folders and makes `Application Support/Pointer/` if it is missing.
    ///
    /// - Throws: The error of `FileManager` if a folder cannot be found or made.
    static func make(_ files: FileManager) throws -> AppFiles {
        let support = try files.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "Pointer", directoryHint: .isDirectory)
        try files.createDirectory(at: support, withIntermediateDirectories: true)
        let documents = try files.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let caches = try files.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return AppFiles(
            library: support.appending(path: "library.sqlite").path(percentEncoded: false),
            device: support.appending(path: "device.sqlite").path(percentEncoded: false),
            temporary: files.temporaryDirectory,
            backups: documents.appending(path: "Backups", directoryHint: .isDirectory),
            previews: caches.appending(path: "Pointer/previews", directoryHint: .isDirectory)
        )
    }
}
