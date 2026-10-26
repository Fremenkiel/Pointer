import Foundation
import Testing

@testable import Persistence

/// The marker of a restore in progress (D-180, storage.md section 7.5). The crash test writes
/// it in a helper process, so these tests cover it in process.
@Suite("Restore marker")
struct RestoreMarkerTests {
    /// A library with a pre-restore snapshot, and the marker of the library. The harness holds
    /// the temporary folder, so it must stay alive.
    private struct Rig {
        let harness: RepositoryHarness
        let marker: RestoreMarker
        let snapshot: URL
    }

    private static func rig() async throws -> Rig {
        let harness = try RepositoryHarness()
        _ = try await harness.open()
        let snapshot = try await SnapshotWriterTests.writer(harness).writePreRestoreSnapshot()
        let marker = RestoreMarker(
            libraryPath: harness.path,
            backupsFolder: SnapshotWriterTests.backups(harness)
        )
        return Rig(harness: harness, marker: marker, snapshot: snapshot)
    }

    @Test("A written marker names its pre-restore snapshot, and a remove clears it")
    func roundTrip() async throws {
        let rig = try await Self.rig()
        let (harness, marker, snapshot) = (rig.harness, rig.marker, rig.snapshot)
        #expect(marker.snapshot() == nil)
        try marker.write(snapshot: snapshot)
        #expect(marker.path == harness.path + ".restoring")
        #expect(marker.snapshot()?.lastPathComponent == snapshot.lastPathComponent)
        try marker.remove()
        #expect(marker.snapshot() == nil)
        try marker.remove()
    }

    @Test("A marker whose snapshot is gone, or with another name, gives no snapshot")
    func damaged() async throws {
        let rig = try await Self.rig()
        let (harness, marker, snapshot) = (rig.harness, rig.marker, rig.snapshot)
        try marker.write(snapshot: snapshot)
        try FileManager().removeItem(at: snapshot)
        #expect(marker.snapshot() == nil)
        try Data("Pointer-2026-10-26.sqlite".utf8).write(to: URL(filePath: marker.path))
        #expect(marker.snapshot() == nil)
        #expect(FileManager().fileExists(atPath: harness.path))
    }

    @Test("A marker that cannot be written throws fileFailed")
    func writeFails() async throws {
        let rig = try await Self.rig()
        let (harness, snapshot) = (rig.harness, rig.snapshot)
        let missing = harness.folder.url.appending(path: "Missing", directoryHint: .isDirectory)
        let marker = RestoreMarker(
            libraryPath: missing.appending(path: "library.sqlite").path(percentEncoded: false),
            backupsFolder: missing
        )
        #expect {
            try marker.write(snapshot: snapshot)
        } throws: { error in
            guard case .fileFailed = error as? PersistenceError else { return false }
            return true
        }
        #expect(marker.snapshot() == nil)
    }
}
