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

    /// Finds the folders and makes `Application Support/Pointer/` if it is missing. With the
    /// token of a UI test, it gives the folders of `uiTest(token:_:)` instead (D-178).
    ///
    /// - Throws: The error of `FileManager` if a folder cannot be found or made.
    static func make(_ files: FileManager, uiTestToken: String? = nil) throws -> AppFiles {
        if let uiTestToken { return try uiTest(token: uiTestToken, files) }
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

extension AppFiles {
    /// The launch argument of the UI tests: `-uiTestLibrary <token>` (D-178).
    static let uiTestKey = "uiTestLibrary"

    /// The start of the name of each folder of a UI test in `tmp/`.
    static let uiTestPrefix = "UITest-"

    /// Finds the folders of a UI test: one new folder `tmp/UITest-<token>/` holds all files, so
    /// that a UI test never touches the real library (D-178). It removes the folders of the
    /// earlier UI tests, because the test process cannot reach the container of the app.
    ///
    /// - Precondition: `token` has 1 to 64 letters, digits, and hyphens.
    /// - Throws: The error of `FileManager` if a folder cannot be read, removed, or made.
    static func uiTest(token: String, _ files: FileManager) throws -> AppFiles {
        precondition(
            (1...64).contains(token.count)
                && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") },
            "A UI test token has 1 to 64 letters, digits, and hyphens"
        )
        let name = uiTestPrefix + token
        try removeUITestFolders(except: name, files)
        let folder = files.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
        let temporary = folder.appending(path: "tmp", directoryHint: .isDirectory)
        try files.createDirectory(at: temporary, withIntermediateDirectories: true)
        return AppFiles(
            library: folder.appending(path: "library.sqlite").path(percentEncoded: false),
            device: folder.appending(path: "device.sqlite").path(percentEncoded: false),
            temporary: temporary,
            backups: folder.appending(path: "Backups", directoryHint: .isDirectory),
            previews: folder.appending(path: "previews", directoryHint: .isDirectory)
        )
    }

    /// Removes each folder `tmp/UITest-*` except the folder `kept`.
    ///
    /// - Throws: The error of `FileManager` if `tmp/` cannot be read or a folder not removed.
    private static func removeUITestFolders(except kept: String, _ files: FileManager) throws {
        let names = try files.contentsOfDirectory(atPath: files.temporaryDirectory.path())
        for name in names where name.hasPrefix(uiTestPrefix) && name != kept {
            try files.removeItem(at: files.temporaryDirectory.appending(path: name))
        }
    }
}
