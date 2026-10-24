import Foundation
import Model
import Testing

@testable import Persistence

/// The edges of a restore and of a snapshot that the review after M9 found (D-168).
@Suite("Edges of the restore and the snapshots")
struct RestoreEdgeTests {
    @Test("A read-only library of a newer schema takes a restore of an older snapshot (D-168)")
    func readOnlyLibraryTakesRestore() async throws {
        let source = try await RepositoryRestoreTests.sourceLibrary()
        let target = try RepositoryHarness()
        let first = try await target.open()
        await first.close()
        // A version far above `Schema.currentVersion` stays newer when the schema grows.
        try SQLiteConnection(path: target.path, mode: .readWrite).execute(
            "PRAGMA user_version = 999"
        )
        let repository = target.make()
        let launch = try await repository.open { _ in }
        try #require(launch.isReadOnly)
        let checked = try await RepositoryRestoreTests.checkedSnapshot(of: source, into: target)
        try await repository.saveNow()
        try await repository.restore(from: checked, stop: RestoreStop())
        #expect(try RepositoryRestoreTests.differences(target, checked) == 0)
        let reopened = try await repository.open { _ in }
        #expect(!reopened.isReadOnly)
        await repository.close()
    }

    @Test("A reader that holds the checkpoint after the copy leaves a restored library")
    func readerAfterCopy() async throws {
        let source = try await RepositoryRestoreTests.sourceLibrary()
        let target = try RepositoryHarness()
        let repository = try await target.open()
        try await repository.send([.stroke(Values.stroke(40))])
        try await repository.saveNow()
        let checked = try await RepositoryRestoreTests.checkedSnapshot(of: source, into: target)
        // A read on another connection holds the TRUNCATE checkpoint for the busy timeout.
        let reader = try target.reader()
        let read = try reader.prepare("SELECT id FROM stroke")
        #expect(try read.step())
        try await repository.restore(from: checked, stop: RestoreStop())
        try read.reset()
        #expect(try RepositoryRestoreTests.differences(target, checked) == 0)
    }

    @Test("A failed delete of an old daily snapshot keeps the new one")
    func lockedOldDailySnapshot() async throws {
        let harness = try RepositoryHarness()
        _ = try await harness.open()
        let writer = try SnapshotWriterTests.writer(harness)
        let oldest = try await writer.writeSnapshotNow()
        for _ in 1..<SnapshotFiles.keptCount {
            _ = try await writer.writeSnapshotNow()
        }
        try Self.lock(oldest)
        defer { Self.unlock(oldest) }
        let newest = try await writer.writeSnapshotNow()
        #expect(FileManager().fileExists(atPath: newest.path(percentEncoded: false)))
        #expect(FileManager().fileExists(atPath: oldest.path(percentEncoded: false)))
    }

    @Test("A failed delete of an older pre-restore snapshot keeps the new one")
    func lockedPreRestoreSnapshot() async throws {
        let harness = try RepositoryHarness()
        _ = try await harness.open()
        let writer = try SnapshotWriterTests.writer(harness)
        let older = try await writer.writePreRestoreSnapshot()
        try Self.lock(older)
        defer { Self.unlock(older) }
        let newer = try await writer.writePreRestoreSnapshot()
        #expect(newer != older)
        #expect(FileManager().fileExists(atPath: newer.path(percentEncoded: false)))
    }

    /// Makes `file` immutable, so that a delete fails.
    private static func lock(_ file: URL) throws {
        try FileManager().setAttributes([.immutable: true], ofItemAtPath: file.path)
    }

    /// Lets the temporary folder delete `file` again.
    private static func unlock(_ file: URL) {
        do {
            try FileManager().setAttributes([.immutable: false], ofItemAtPath: file.path)
        } catch {
            Issue.record("The snapshot stays immutable: \(error)")
        }
    }
}
