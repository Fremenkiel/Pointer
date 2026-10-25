import Foundation
import Model
import SQLite3
import Testing
import os

@testable import Persistence

@Suite("Repository launch")
struct RepositoryLaunchTests {
    static let day: UInt64 = 24 * 60 * 60 * 1000

    @Test("A new library gets the four library rows of D-58")
    func creationRows() async throws {
        let harness = try RepositoryHarness()
        let launch = try await harness.make().open { _ in }
        let created = HybridTimestamp(
            wallMillis: RepositoryHarness.now,
            counter: 0,
            device: Values.device
        )
        #expect(launch == LibraryLaunch(isReadOnly: false, lastTimestamp: created))
        let reader = try harness.reader()
        let rows = try MigrationRunnerTests.names(
            reader,
            "SELECT key || '=' || value FROM library ORDER BY key"
        )
        #expect(
            rows == [
                "created=\(ValueCodec.hex(created))",
                "createdBy=01000000-0000-0000-0000-000000000000",
                "formatVersion=1",
                "lastTimestamp=\(ValueCodec.hex(created))",
            ]
        )
    }

    @Test("An older library gets its snapshot before the migration, and a failed snapshot stops it")
    func preMigrationSnapshot() async throws {
        let harness = try RepositoryHarness()
        _ = try await harness.open()
        let migrations = Migration.library + [MigrationRunnerTests.addTable]
        let failing = harness.make(migrations: migrations)
        await #expect(throws: ModelError.self) {
            try await failing.open { _ throws(PersistenceError) in
                throw .sqlite(code: SQLITE_FULL, message: "database or disk is full")
            }
        }
        #expect(try harness.reader().integer("PRAGMA user_version") == 1)

        let versions = VersionList()
        let repository = harness.make(migrations: migrations)
        let path = harness.path
        _ = try await repository.open { version throws(PersistenceError) in
            let reader = try SQLiteConnection(path: path, mode: .readOnly)
            versions.add(version, seen: try reader.integer("PRAGMA user_version"))
        }
        #expect(versions.values == [1, 1])
        #expect(try harness.reader().integer("PRAGMA user_version") == 2)
    }

    @Test(
        "A partial pre-migration snapshot of a stopped launch does not block the next open (F-08)"
    )
    func partialPreMigrationSnapshot() async throws {
        let harness = try RepositoryHarness()
        _ = try await harness.open()
        let partial = harness.folder.url.appending(
            path: SnapshotFiles.preMigrationName(oldVersion: 1) + SnapshotFiles.partialExtension
        )
        try Data([1, 2, 3]).write(to: partial)
        let writer = SnapshotWriter(
            configuration: SnapshotWriterTests.configuration(
                harness,
                clock: FixedWallClock(millis: RepositoryHarness.now)
            )
        )
        let repository = harness.make(
            migrations: Migration.library + [MigrationRunnerTests.addTable]
        )
        _ = try await repository.open { version throws(PersistenceError) in
            try await writer.writePreMigrationSnapshot(oldVersion: version)
        }
        #expect(try harness.reader().integer("PRAGMA user_version") == 2)
        let backups = SnapshotWriterTests.backups(harness).path(percentEncoded: false)
        let names = try FileManager().contentsOfDirectory(atPath: backups)
        #expect(names == [SnapshotFiles.preMigrationName(oldVersion: 1)])
    }

    @Test("The launch removes tombstones older than 30 days with their subtrees and keeps the rest")
    func tombstones() async throws {
        let harness = try RepositoryHarness()
        _ = try await harness.open()
        let writer = try SQLiteConnection(path: harness.path, mode: .readWrite)
        try writer.execute(Self.tombstoneRows)
        try Data().write(to: harness.folder.url.appending(path: "Pointer-1.sqlite.partial"))
        try Data().write(to: harness.folder.url.appending(path: "keep.sqlite"))

        _ = try await harness.open(wallMillis: RepositoryHarness.now + 31 * Self.day)
        let reader = try harness.reader()
        let left = try MigrationRunnerTests.names(
            reader,
            """
            SELECT 'workspace ' || title FROM workspace UNION ALL
            SELECT 'card ' || title FROM card UNION ALL SELECT 'text ' || text FROM text_box
            UNION ALL SELECT 'stroke ' || hex(substr(id, 1, 2)) FROM stroke
            UNION ALL SELECT 'erase ' || hex(substr(stroke_id, 1, 2)) FROM stroke_erase
            ORDER BY 1
            """
        )
        #expect(
            left == [
                "card young", "erase 0303", "stroke 0302", "stroke 0303", "text live",
                "workspace live",
            ]
        )
        #expect(try reader.integer("PRAGMA freelist_count") == 0)
        let files = try FileManager().contentsOfDirectory(atPath: harness.folder.url.path)
        #expect(!files.contains("Pointer-1.sqlite.partial"))
        #expect(files.contains("keep.sqlite"))
    }

    @Test("A launch that removes many tombstones starts a checkpoint (review after M8, 3.2.8)")
    func checkpointAfterCleanup() async throws {
        let harness = try RepositoryHarness()
        _ = try await harness.open()
        let writer = try SQLiteConnection(path: harness.path, mode: .readWrite)
        try writer.execute(Self.tombstoneRows)
        // 12,000 strokes of 4 KB under the old workspace: their delete fills more than
        // `checkpointPages` pages of the WAL.
        try writer.execute(
            """
            WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 12000)
            INSERT INTO stroke SELECT randomblob(16), X'11', zeroblob(28), 0, 0, 2, 0, 0, 1, 1, 256,
                zeroblob(4096) FROM n
            """
        )
        try writer.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        let checkpoints = VersionList()
        let repository = harness.make(
            wallMillis: RepositoryHarness.now + 31 * Self.day,
            beforeCheckpoint: { checkpoints.add(1, seen: 0) }
        )
        _ = try await repository.open { _ in }
        await repository.waitForCheckpoint()
        let pages = await repository.walPageCount
        #expect(!checkpoints.values.isEmpty, "No checkpoint after a cleanup of \(pages) pages")
    }

    @Test("The launch reports the canvases that its cleanup removes, for their previews (D-18)")
    func removedCanvases() async throws {
        let harness = try RepositoryHarness()
        _ = try await harness.open()
        let writer = try SQLiteConnection(path: harness.path, mode: .readWrite)
        try writer.execute(
            """
            INSERT INTO workspace VALUES (X'0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A', 'old', 'V',
                zeroblob(28), zeroblob(28), 1);
            INSERT INTO card VALUES (X'0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B',
                X'0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A', 0, 0, 64, 48, 'under old', 'V',
                zeroblob(28), zeroblob(28), 0);
            INSERT INTO workspace VALUES (X'0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C', 'live', 'W',
                zeroblob(28), zeroblob(28), 0);
            """
        )
        let later = harness.make(wallMillis: RepositoryHarness.now + 31 * Self.day)
        let launch = try await later.open { _ in }
        let removed = Set(launch.removedCanvases.map(\.rawValue.uuidString))
        #expect(
            removed == [
                "0A0A0A0A-0A0A-0A0A-0A0A-0A0A0A0A0A0A", "0B0B0B0B-0B0B-0B0B-0B0B-0B0B0B0B0B0B",
            ]
        )
    }

    @Test("A damaged library file gives a fault at the open and stays as it was (storage.md 9)")
    func damagedLibrary() async throws {
        let harness = try RepositoryHarness()
        let damage = Data((0..<8_192).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try damage.write(to: URL(filePath: harness.path))
        await #expect(throws: ModelError.self) { _ = try await harness.make().open { _ in } }
        #expect(try Data(contentsOf: URL(filePath: harness.path)) == damage)
    }

    /// Rows at day 0 (`zeroblob` sorts first) and at day 30 after `RepositoryHarness.now`
    /// (`young`). The launch runs at day 31, so only the day-0 tombstones are old.
    static let tombstoneRows: StaticString = """
        INSERT INTO workspace VALUES (X'01', 'old', 'V', zeroblob(28), zeroblob(28), 1);
        INSERT INTO workspace VALUES (X'02', 'live', 'W', zeroblob(28), zeroblob(28), 0);
        INSERT INTO card VALUES (X'11', X'01', 0, 0, 64, 48, 'under old', 'V',
            zeroblob(28), zeroblob(28), 0);
        INSERT INTO card VALUES (X'12', X'11', 0, 0, 64, 48, 'deeper', 'V',
            zeroblob(28), zeroblob(28), 0);
        INSERT INTO card VALUES (X'13', X'02', 0, 0, 64, 48, 'old card', 'V',
            zeroblob(28), zeroblob(28), 1);
        INSERT INTO card VALUES (X'14', X'02', 0, 0, 64, 48, 'young', 'V', zeroblob(28),
            X'0000018C6A6430000000000001000000000000000000000000000000', 1);
        INSERT INTO text_box VALUES (X'21', X'12', 0, 0, 'in subtree', 'V',
            zeroblob(28), zeroblob(28), 0);
        INSERT INTO text_box VALUES (X'22', X'02', 0, 0, 'old text', 'V',
            zeroblob(28), zeroblob(28), 1);
        INSERT INTO text_box VALUES (X'23', X'02', 0, 0, 'live', 'V',
            zeroblob(28), zeroblob(28), 0);
        INSERT INTO stroke VALUES (X'0301', X'12', zeroblob(28), 0, 0, 2, 0, 0, 1, 1, 2,
            zeroblob(32));
        INSERT INTO stroke VALUES (X'0302', X'02', zeroblob(28), 0, 0, 2, 0, 0, 1, 1, 2,
            zeroblob(32));
        INSERT INTO stroke VALUES (X'0303', X'02', zeroblob(28), 0, 0, 2, 0, 0, 1, 1, 2,
            zeroblob(32));
        INSERT INTO stroke VALUES (X'0304', X'02', zeroblob(28), 0, 0, 2, 0, 0, 1, 1, 2,
            zeroblob(32));
        INSERT INTO stroke_erase VALUES (X'0301', zeroblob(28), zeroblob(28), 0);
        INSERT INTO stroke_erase VALUES (X'0303', zeroblob(28), zeroblob(28), 1);
        INSERT INTO stroke_erase VALUES (X'0304', zeroblob(28), zeroblob(28), 0);
        """
}

/// Collects the snapshot versions and the schema version that each snapshot saw.
final class VersionList: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: [Int64]())

    var values: [Int64] { state.withLock { $0 } }

    func add(_ version: Int64, seen: Int64) { state.withLock { $0 += [version, seen] } }
}
