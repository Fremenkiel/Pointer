import Foundation
import Model
import Testing
import os

@testable import Persistence

@Suite("Snapshot writer")
struct SnapshotWriterTests {
    @Test("A snapshot holds all rows of the live library and passes the integrity check")
    func allRows() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        try await repository.create(try Values.workspace())
        let erase = EraseRecord(
            strokeID: Values.stroke(2, millis: 1).id,
            erased: Values.early,
            modified: Values.late,
            isDeleted: false
        )
        try await repository.send(
            (1...20).map { .stroke(Values.stroke($0, millis: 1)) }
                + [.card(try Values.card(3)), .textBox(try Values.textBox(5)), .erase(erase)]
        )
        try await repository.saveNow()

        let url = try await Self.writer(harness).writeSnapshotNow()
        #expect(url.lastPathComponent == "Pointer-2023-11-14-221320.sqlite")
        let live = try SQLiteConnection(path: harness.path, mode: .readWrite)
        let attach = try live.prepare("ATTACH ? AS snapshot")
        try attach.bind(url.path(percentEncoded: false), at: 1)
        try LibraryStatements.run(attach)
        #expect(try live.text("PRAGMA snapshot.integrity_check") == "ok")
        #expect(try live.integer("PRAGMA snapshot.page_size") == SQLiteConnection.pageSize)
        #expect(try live.integer("PRAGMA snapshot.user_version") == 1)
        #expect(try live.integer(Self.differences) == 0)
        #expect(try live.integer("SELECT count(*) FROM snapshot.stroke") == 20)
        let backups = try FileManager().contentsOfDirectory(atPath: Self.backups(harness).path)
        #expect(backups == [url.lastPathComponent])
    }

    @Test("A snapshot that fails before the rename leaves no file in Backups and in tmp")
    func stopBeforeRename() async throws {
        let harness = try RepositoryHarness()
        _ = try await harness.open()
        let writer = SnapshotWriter(
            configuration: Self.configuration(
                harness,
                clock: FixedWallClock(millis: RepositoryHarness.now)
            ),
            beforeRename: { () throws(PersistenceError) in throw .fileFailed(reason: "stopped") }
        )
        await #expect(throws: PersistenceError.fileFailed(reason: "stopped")) {
            try await writer.writeSnapshotNow()
        }
        let backups = Self.backups(harness).path(percentEncoded: false)
        let names = (try? FileManager().contentsOfDirectory(atPath: backups)) ?? []
        #expect(names.isEmpty)
        let temporary = try FileManager().contentsOfDirectory(atPath: harness.folder.url.path)
        #expect(!temporary.contains("Pointer-2023-11-14-221320.sqlite.partial"))
        #expect(try await writer.isDailySnapshotDue())
    }

    @Test("The idle signal makes a snapshot at once, then again only after 24 hours")
    func dailyInterval() async throws {
        let harness = try RepositoryHarness()
        _ = try await harness.open()
        let clock = MovableWallClock(RepositoryHarness.now)
        let writer = SnapshotWriter(configuration: Self.configuration(harness, clock: clock))
        #expect(try await writer.appIsIdle() != nil)
        clock.advance(byHours: 23)
        #expect(try await writer.appIsIdle() == nil)
        clock.advance(byHours: 1)
        #expect(try await writer.appIsIdle() != nil)
    }

    @Test("Only the newest 7 daily snapshots stay, and a pre-migration snapshot stays too")
    func rotation() async throws {
        let harness = try RepositoryHarness()
        _ = try await harness.open()
        let clock = MovableWallClock(RepositoryHarness.now)
        let writer = SnapshotWriter(configuration: Self.configuration(harness, clock: clock))
        try await writer.writePreMigrationSnapshot(oldVersion: 1)
        var written: [String] = []
        for _ in 0..<9 {
            written.append(try await writer.writeSnapshotNow().lastPathComponent)
            clock.advance(byHours: 24)
        }
        let names = try FileManager().contentsOfDirectory(atPath: Self.backups(harness).path)
        #expect(
            Set(names)
                == Set(
                    written.suffix(SnapshotFiles.keptCount) + ["Pointer-pre-migration-v1.sqlite"]
                )
        )
    }

    @Test("A second pre-migration snapshot of the same version keeps the first one")
    func preMigrationKept() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        let writer = try Self.writer(harness)
        try await writer.writePreMigrationSnapshot(oldVersion: 1)
        try await repository.create(try Values.workspace())
        try await writer.writePreMigrationSnapshot(oldVersion: 1)
        let url = Self.backups(harness).appending(path: "Pointer-pre-migration-v1.sqlite")
        let snapshot = try SQLiteConnection(path: url.path(percentEncoded: false), mode: .readOnly)
        #expect(try snapshot.integer("SELECT count(*) FROM workspace") == 0)
    }

    @Test("The repository writes the pre-migration snapshot through the writer before it migrates")
    func preMigrationThroughRepository() async throws {
        let harness = try RepositoryHarness()
        _ = try await harness.open()
        let writer = try Self.writer(harness)
        let repository = harness.make(
            migrations: Migration.library + [MigrationRunnerTests.addTable]
        )
        _ = try await repository.open { version throws(PersistenceError) in
            try await writer.writePreMigrationSnapshot(oldVersion: version)
        }
        let url = Self.backups(harness).appending(path: "Pointer-pre-migration-v1.sqlite")
        let snapshot = try SQLiteConnection(path: url.path(percentEncoded: false), mode: .readOnly)
        #expect(try snapshot.integer("PRAGMA user_version") == 1)
        #expect(try harness.reader().integer("PRAGMA user_version") == 2)
    }

    @Test("Saves run and finish while a snapshot of a large library runs")
    func saveDuringSnapshot() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        let filler = try SQLiteConnection(path: harness.path, mode: .readWrite)
        try filler.execute(Self.largeLibrary)
        let writer = try Self.writer(harness)
        let isDone = OSAllocatedUnfairLock(initialState: false)
        let snapshot = Task {
            defer { isDone.withLock { $0 = true } }
            return try await writer.writeSnapshotNow()
        }
        let clock = ContinuousClock()
        var savesDuringSnapshot = 0
        var slowest = Duration.zero
        for index in 0..<200 where !isDone.withLock({ $0 }) {
            try await repository.send([
                .stroke(Values.stroke(UInt8(index % 250), millis: UInt64(index)))
            ])
            slowest = max(slowest, try await clock.measure { try await repository.saveNow() })
            if !isDone.withLock({ $0 }) { savesDuringSnapshot += 1 }
        }
        _ = try await snapshot.value
        #expect(savesDuringSnapshot > 0, "No save ran while the snapshot ran")
        #expect(slowest < .milliseconds(500), "A save waited \(slowest)")
    }

    /// About 100 MB of strokes, so that the snapshot takes a while.
    static let largeLibrary: StaticString = """
        WITH RECURSIVE n (i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 20000)
        INSERT INTO stroke
        SELECT randomblob(16), X'00', zeroblob(28), 0, 0, 2, 0, 0, 1, 1, 300, randomblob(4800)
        FROM n
        """

    /// Counts the rows that are in one database but not in the other, in each table.
    static let differences: StaticString = """
        SELECT
            (SELECT count(*) FROM (
                SELECT * FROM main.workspace EXCEPT SELECT * FROM snapshot.workspace))
          + (SELECT count(*) FROM (
                SELECT * FROM snapshot.workspace EXCEPT SELECT * FROM main.workspace))
          + (SELECT count(*) FROM (SELECT * FROM main.card EXCEPT SELECT * FROM snapshot.card))
          + (SELECT count(*) FROM (SELECT * FROM snapshot.card EXCEPT SELECT * FROM main.card))
          + (SELECT count(*) FROM (
                SELECT * FROM main.text_box EXCEPT SELECT * FROM snapshot.text_box))
          + (SELECT count(*) FROM (
                SELECT * FROM snapshot.text_box EXCEPT SELECT * FROM main.text_box))
          + (SELECT count(*) FROM (
                SELECT * FROM main.stroke EXCEPT SELECT * FROM snapshot.stroke))
          + (SELECT count(*) FROM (
                SELECT * FROM snapshot.stroke EXCEPT SELECT * FROM main.stroke))
          + (SELECT count(*) FROM (
                SELECT * FROM main.stroke_erase EXCEPT SELECT * FROM snapshot.stroke_erase))
          + (SELECT count(*) FROM (
                SELECT * FROM snapshot.stroke_erase EXCEPT SELECT * FROM main.stroke_erase))
          + (SELECT count(*) FROM (
                SELECT * FROM main.library EXCEPT SELECT * FROM snapshot.library))
          + (SELECT count(*) FROM (
                SELECT * FROM snapshot.library EXCEPT SELECT * FROM main.library))
        """

    static func backups(_ harness: RepositoryHarness) -> URL {
        harness.folder.url.appending(path: "Backups", directoryHint: .isDirectory)
    }

    static func configuration(
        _ harness: RepositoryHarness,
        clock: any WallClock
    ) -> SnapshotWriter.Configuration {
        SnapshotWriter.Configuration(
            databasePath: harness.path,
            temporaryFolder: harness.folder.url,
            backupsFolder: backups(harness),
            wallClock: clock,
            timeZone: TimeZone(identifier: "UTC") ?? .gmt
        )
    }

    static func writer(_ harness: RepositoryHarness) throws -> SnapshotWriter {
        SnapshotWriter(
            configuration: configuration(
                harness,
                clock: FixedWallClock(millis: RepositoryHarness.now)
            )
        )
    }
}
