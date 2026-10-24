import Foundation
import Model
import Testing

@testable import Persistence

/// The restore of a checked snapshot into the live library (task 1.4 of docs/m9-plan.md,
/// storage.md section 9, M9 acceptance 2, D-148, D-164).
@Suite("Restore of the repository")
struct RepositoryRestoreTests {
    /// About 10 MB of strokes: 2,500 pages, so the copy takes 3 steps of 1,024 pages.
    static let mediumLibrary: StaticString = """
        WITH RECURSIVE n (i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 2000)
        INSERT INTO stroke
        SELECT randomblob(16), X'00', zeroblob(28), 0, 0, 2, 0, 0, 1, 1, 300, randomblob(4800)
        FROM n
        """

    @Test("A restore over a different library gives the rows of the snapshot")
    func restoreGivesSnapshotRows() async throws {
        let source = try await Self.sourceLibrary()
        let target = try RepositoryHarness()
        let repository = try await target.open()
        try await repository.send([.stroke(Values.stroke(40)), .card(try Values.card(41))])
        try await repository.saveNow()
        let checked = try await Self.checkedSnapshot(of: source, into: target)
        try await repository.restore(from: checked, stop: RestoreStop())
        #expect(try Self.differences(target, checked) == 0)
        _ = try await repository.open { _ in }
        let content = try await repository.content(of: Values.canvas)
        #expect(Set(content.strokes.keys) == [Values.stroke(1).id, Values.stroke(2).id])
        await repository.close()
    }

    @Test("A stop in the middle keeps the old library")
    func stopKeepsOldLibrary() async throws {
        let source = try RepositoryHarness()
        _ = try await source.open()
        try SQLiteConnection(path: source.path, mode: .readWrite).execute(Self.mediumLibrary)
        let target = try RepositoryHarness()
        let repository = try await target.open()
        try await repository.send([.stroke(Values.stroke(40))])
        try await repository.saveNow()
        let checked = try await Self.checkedSnapshot(of: source, into: target)
        await #expect(throws: PersistenceError.restoreStopped) {
            try await repository.restore(from: checked, stop: RestoreStop(stopsAfterReads: 1))
        }
        let reader = try target.reader()
        #expect(try reader.integer("SELECT count(*) FROM stroke") == 1)
        #expect(try reader.text("PRAGMA integrity_check") == "ok")
        _ = try await repository.open { _ in }
        await repository.close()
    }

    @Test("A stop before the first step keeps the old library")
    func stopBeforeStart() async throws {
        let source = try await Self.sourceLibrary()
        let target = try RepositoryHarness()
        let repository = try await target.open()
        let checked = try await Self.checkedSnapshot(of: source, into: target)
        let stop = RestoreStop()
        stop.stop()
        #expect(stop.isStopped)
        await #expect(throws: PersistenceError.restoreStopped) {
            try await repository.restore(from: checked, stop: stop)
        }
        #expect(try target.reader().integer("SELECT count(*) FROM workspace") == 0)
    }

    @Test("A restore of an older schema version migrates at the next open")
    func olderVersionMigrates() async throws {
        let source = try await Self.sourceLibrary()
        let target = try RepositoryHarness()
        let migrations = Migration.library + [MigrationRunnerTests.addTable]
        let repository = target.make(migrations: migrations)
        _ = try await repository.open { _ in }
        let checked = try await Self.checkedSnapshot(of: source, into: target)
        try await repository.restore(from: checked, stop: RestoreStop())
        #expect(try target.reader().integer("PRAGMA user_version") == 1)
        let versions = VersionList()
        let path = target.path
        _ = try await repository.open { version throws(PersistenceError) in
            let reader = try SQLiteConnection(path: path, mode: .readOnly)
            versions.add(version, seen: try reader.integer("PRAGMA user_version"))
        }
        #expect(versions.values == [1, 1])
        #expect(try target.reader().integer("PRAGMA user_version") == 2)
        await repository.close()
    }

    @Test("The -wal file has 0 bytes after the restore")
    func walIsEmpty() async throws {
        let source = try RepositoryHarness()
        _ = try await source.open()
        try SQLiteConnection(path: source.path, mode: .readWrite).execute(Self.mediumLibrary)
        let target = try RepositoryHarness()
        let repository = try await target.open()
        let checked = try await Self.checkedSnapshot(of: source, into: target)
        // A second connection keeps the -wal file after the close of the repository.
        let reader = try target.reader()
        try await repository.restore(from: checked, stop: RestoreStop())
        let wal = try FileManager().attributesOfItem(atPath: target.path + "-wal")[.size] as? Int
        #expect(wal == 0)
        #expect(try reader.integer("SELECT count(*) FROM stroke") == 2_000)
    }

    @Test("A restore works while the checkpointer connection is open")
    func restoreWithCheckpointer() async throws {
        let source = try await Self.sourceLibrary()
        let target = try RepositoryHarness()
        let repository = try await target.open()
        _ = try await RepositoryCheckpointTests.fill(
            repository,
            toPages: SQLiteLibraryRepository.checkpointPages
        )
        await repository.waitForCheckpoint()
        #expect(await repository.checkpointer != nil)
        let checked = try await Self.checkedSnapshot(of: source, into: target)
        try await repository.restore(from: checked, stop: RestoreStop())
        #expect(try Self.differences(target, checked) == 0)
        #expect(await repository.checkpointer == nil)
    }

    /// A library with two strokes, a card, and a workspace.
    private static func sourceLibrary() async throws -> RepositoryHarness {
        let source = try RepositoryHarness()
        let repository = try await source.open()
        try await repository.create(try Values.workspace())
        try await repository.send([
            .stroke(Values.stroke(1)), .stroke(Values.stroke(2)), .card(try Values.card(3)),
        ])
        try await repository.saveNow()
        await repository.close()
        return source
    }

    /// Writes a snapshot of `source` and copies it into the folder of `target` with its checks.
    private static func checkedSnapshot(
        of source: RepositoryHarness,
        into target: RepositoryHarness
    ) async throws -> CheckedSnapshot {
        let url = try await SnapshotWriterTests.writer(source).writeSnapshotNow()
        return try await SnapshotImport(temporaryFolder: target.folder.url).copyAndCheck(url)
    }

    /// Counts the rows that differ between the library of `target` and the snapshot.
    private static func differences(
        _ target: RepositoryHarness,
        _ snapshot: CheckedSnapshot
    ) throws -> Int64 {
        let live = try SQLiteConnection(path: target.path, mode: .readWrite)
        let attach = try live.prepare("ATTACH ? AS snapshot")
        try attach.bind(snapshot.file.path(percentEncoded: false), at: 1)
        try LibraryStatements.run(attach)
        return try live.integer(SnapshotWriterTests.differences)
    }
}
