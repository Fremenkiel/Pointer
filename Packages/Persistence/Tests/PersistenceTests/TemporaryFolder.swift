import Foundation
import Testing

/// A new, empty folder for one test. It is removed when the value goes away (TEST-04).
final class TemporaryFolder {
    let url: URL
    private let files = FileManager()

    init() throws {
        url = files.temporaryDirectory.appending(
            path: "PersistenceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try files.createDirectory(at: url, withIntermediateDirectories: false)
    }

    deinit {
        // A folder that stays behind costs disk space only. No later test reads it, so the
        // failure is a note, not a failed test (SAFE-02).
        do {
            try files.removeItem(at: url)
        } catch {
            Issue.record("The test folder stays behind: \(error)", severity: .warning)
        }
    }

    /// Returns the path of a file in the folder.
    func path(_ name: String) -> String {
        url.appending(path: name).path(percentEncoded: false)
    }
}
