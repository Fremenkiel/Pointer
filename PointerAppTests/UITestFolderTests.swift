import Foundation
import Testing

@testable import Pointer

/// The folders of the UI tests (D-178). The test process of `PointerUITests` cannot reach the
/// container of the app, and the old code left one folder `tmp/UITest-<token>/` per launch.
@Suite("UI test folders")
struct UITestFolderTests {
    @Test("A launch with a new token removes the folders of the earlier UI tests")
    func launchRemovesOldFolders() throws {
        // swiftlint:disable:next arch_04_file_system
        let files = FileManager()
        let old = files.temporaryDirectory.appending(
            path: "UITest-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try files.createDirectory(
            at: old.appending(path: "tmp", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        let other = files.temporaryDirectory.appending(path: "Other-\(UUID().uuidString)")
        try Data([1]).write(to: other)
        defer { try? files.removeItem(at: other) }

        let token = UUID().uuidString
        let launched = try AppFiles.uiTest(token: token, files)
        let folder = files.temporaryDirectory.appending(path: "UITest-\(token)")
        defer { try? files.removeItem(at: folder) }

        #expect(!files.fileExists(atPath: old.path()), "The old folder is gone")
        #expect(files.fileExists(atPath: launched.temporary.path()), "The new folder stays")
        #expect(files.fileExists(atPath: other.path()), "Other files in tmp stay")
    }
}
