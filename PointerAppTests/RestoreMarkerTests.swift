import BackupFeature
import Foundation
import Model
import Testing

@testable import Persistence
@testable import Pointer

/// A launch after a stop of the process during a restore (D-180). The restored library does
/// not open, and the way back of D-20 lived only in memory, so the old code showed
/// "libraryFailed" without a selector. The marker now names the pre-restore snapshot.
///
/// A stop during the copy leaves the old library, because the copy switches only at its end
/// (`RestoreCrashTests`). The case here is a stop after the copy and before the way back.
@MainActor
@Suite("Restore marker")
struct RestoreMarkerTests {
    @Test("A launch with a marker and a library that does not open takes the way back")
    func launchTakesTheWayBack() async throws {
        var workspace: Workspace?
        let harness = try await AppHarness.start { files in
            // The pre-restore snapshot of a library with one workspace.
            let other = files.temporary.appending(path: "Before", directoryHint: .isDirectory)
            // swiftlint:disable:next arch_04_file_system
            try FileManager().createDirectory(at: other, withIntermediateDirectories: true)
            let path = other.appending(path: "library.sqlite").path(percentEncoded: false)
            let wallClock = StoppedWallClock(millis: 1_800_000_000_000)
            workspace = try await AppHarness.fillLibrary(
                at: path,
                folder: other,
                wallClock: wallClock
            ).0
            let writer = SnapshotWriter(
                configuration: SnapshotWriter.Configuration(
                    databasePath: path,
                    temporaryFolder: other,
                    backupsFolder: files.backups,
                    wallClock: wallClock,
                    timeZone: .gmt
                )
            )
            let snapshot = try await writer.writePreRestoreSnapshot()
            try RestoreMarker(libraryPath: files.library, backupsFolder: files.backups)
                .write(snapshot: snapshot)
            // The restored file passed the checks of a picked file, and the open refuses its
            // damaged clock row. The process stopped before the way back in memory ran.
            // swiftlint:disable:next arch_04_file_system
            try FileManager().copyItem(at: snapshot, to: URL(filePath: files.library))
            let damaged = try SQLiteConnection(path: files.library, mode: .readWrite)
            try damaged.execute(
                "UPDATE library SET value = 'damaged' WHERE key = 'lastTimestamp'"
            )
            _ = try damaged.text("PRAGMA journal_mode = DELETE")
        }
        defer { await harness.remove() }
        try await harness.waitForReplacement()
        #expect(harness.message == BackupMessage.restoreUndone.text)
        let names = harness.composition.selector?.workspaces.map(\.title) ?? []
        #expect(names.contains(try #require(workspace).title), "The snapshot is the library")
        let marker = RestoreMarker(
            libraryPath: harness.files.library,
            backupsFolder: harness.files.backups
        )
        #expect(marker.snapshot() == nil, "A good open removes the marker")
    }
}
