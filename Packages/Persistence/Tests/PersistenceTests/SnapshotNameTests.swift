import Foundation
import Model
import Testing
import os

@testable import Persistence

/// The names of "Back up now" and of the pre-restore snapshot, and the delete of the partial
/// file of a failed snapshot (task 1.2 of docs/m9-plan.md, D-154, D-155).
@Suite("Snapshot names")
struct SnapshotNameTests {
    @Test("Two snapshots in the same second get a counter")
    func sameSecond() async throws {
        let harness = try RepositoryHarness()
        _ = try await harness.open()
        let writer = try SnapshotWriterTests.writer(harness)
        let first = try await writer.writeSnapshotNow()
        let second = try await writer.writeSnapshotNow()
        #expect(first.lastPathComponent == "Pointer-2023-11-14-221320.sqlite")
        #expect(second.lastPathComponent == "Pointer-2023-11-14-221320-2.sqlite")
        #expect(Set(try Self.names(in: SnapshotWriterTests.backups(harness))).count == 2)
    }

    @Test("A VACUUM INTO into a folder that refuses the write leaves no file")
    func refusedWrite() async throws {
        let harness = try RepositoryHarness()
        _ = try await harness.open()
        let temporary = harness.folder.url.appending(path: "tmp", directoryHint: .isDirectory)
        try FileManager().createDirectory(at: temporary, withIntermediateDirectories: false)
        try FileManager().setAttributes([.posixPermissions: 0o500], ofItemAtPath: temporary.path)
        defer {
            do {
                try FileManager().setAttributes(
                    [.posixPermissions: 0o700],
                    ofItemAtPath: temporary.path
                )
            } catch {
                Issue.record("The folder stays read-only: \(error)")
            }
        }
        var configuration = SnapshotWriterTests.configuration(
            harness,
            clock: FixedWallClock(millis: RepositoryHarness.now)
        )
        configuration = SnapshotWriter.Configuration(
            databasePath: configuration.databasePath,
            temporaryFolder: temporary,
            backupsFolder: configuration.backupsFolder,
            wallClock: configuration.wallClock,
            timeZone: configuration.timeZone
        )
        let writer = SnapshotWriter(configuration: configuration)
        await #expect(throws: PersistenceError.self) { try await writer.writeSnapshotNow() }
        #expect(try Self.names(in: temporary).isEmpty)
        #expect(try Self.names(in: SnapshotWriterTests.backups(harness)).isEmpty)
    }

    @Test("A failed rename deletes the partial file, so the next snapshot of that second works")
    func failedRenameThenAgain() async throws {
        let harness = try RepositoryHarness()
        _ = try await harness.open()
        let fails = OSAllocatedUnfairLock(initialState: true)
        let writer = SnapshotWriter(
            configuration: SnapshotWriterTests.configuration(
                harness,
                clock: FixedWallClock(millis: RepositoryHarness.now)
            ),
            beforeRename: { () throws(PersistenceError) in
                guard fails.withLock({ $0 }) else { return }
                throw .fileFailed(reason: "the disk is full")
            }
        )
        await #expect(throws: PersistenceError.self) { try await writer.writeSnapshotNow() }
        fails.withLock { $0 = false }
        let url = try await writer.writeSnapshotNow()
        #expect(url.lastPathComponent == "Pointer-2023-11-14-221320.sqlite")
        let partials = try Self.names(in: harness.folder.url).filter {
            $0.hasSuffix(LibraryMaintenance.partialSuffix)
        }
        #expect(partials.isEmpty)
    }

    @Test("The rotation of 7 counts the names with a counter and keeps the newest")
    func rotationWithCounters() async throws {
        let harness = try RepositoryHarness()
        _ = try await harness.open()
        let writer = try SnapshotWriterTests.writer(harness)
        for _ in 0..<9 {
            _ = try await writer.writeSnapshotNow()
        }
        let names = try Self.names(in: SnapshotWriterTests.backups(harness))
        let expected = (3...9).map { "Pointer-2023-11-14-221320-\($0).sqlite" }
        #expect(Set(names) == Set(expected))
    }

    @Test("Only the newest pre-restore snapshot stays, outside the daily rotation")
    func preRestore() async throws {
        let harness = try RepositoryHarness()
        _ = try await harness.open()
        let clock = MovableWallClock(RepositoryHarness.now)
        let writer = SnapshotWriter(
            configuration: SnapshotWriterTests.configuration(harness, clock: clock)
        )
        _ = try await writer.writePreRestoreSnapshot()
        clock.advance(byHours: 1)
        let second = try await writer.writePreRestoreSnapshot()
        #expect(second.lastPathComponent == "Pointer-pre-restore-2023-11-14-231320.sqlite")
        for _ in 0..<8 {
            clock.advance(byHours: 24)
            _ = try await writer.writeSnapshotNow()
        }
        let names = try Self.names(in: SnapshotWriterTests.backups(harness))
        #expect(names.filter(SnapshotFiles.isPreRestore) == [second.lastPathComponent])
        #expect(names.filter(SnapshotFiles.isDaily).count == SnapshotFiles.keptCount)
    }

    @Test(
        "The name parser accepts a counter from 2 to the limit",
        arguments: [
            ("Pointer-2023-11-14-221320.sqlite", true),
            ("Pointer-2023-11-14-221320-2.sqlite", true),
            ("Pointer-2023-11-14-221320-99.sqlite", true),
            ("Pointer-2023-11-14-221320-100.sqlite", false),
            ("Pointer-2023-11-14-221320-1.sqlite", false),
            ("Pointer-2023-11-14-221320-0.sqlite", false),
            ("Pointer-2023-11-14-221320-02.sqlite", false),
            ("Pointer-2023-11-14-221320-.sqlite", false),
            ("Pointer-2023-11-14-22132.sqlite", false),
            ("Pointer-pre-migration-v1.sqlite", false),
            ("Pointer-pre-restore-2023-11-14-221320.sqlite", false),
        ]
    )
    func dailyNames(name: String, isDaily: Bool) {
        #expect(SnapshotFiles.isDaily(name) == isDaily)
    }

    @Test(
        "The pre-restore parser accepts its stamp and a counter",
        arguments: [
            ("Pointer-pre-restore-2023-11-14-221320.sqlite", true),
            ("Pointer-pre-restore-2023-11-14-221320-2.sqlite", true),
            ("Pointer-pre-restore-2023-11-14-221320-100.sqlite", false),
            ("Pointer-pre-restore-.sqlite", false),
        ]
    )
    func preRestoreNames(name: String, isPreRestore: Bool) {
        #expect(SnapshotFiles.isPreRestore(name) == isPreRestore)
        #expect(!SnapshotFiles.isDaily(name))
    }

    private static func names(in folder: URL) throws -> [String] {
        guard FileManager().fileExists(atPath: folder.path(percentEncoded: false)) else {
            return []
        }
        return try FileManager().contentsOfDirectory(atPath: folder.path(percentEncoded: false))
    }
}
