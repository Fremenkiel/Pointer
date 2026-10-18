import Foundation
import Model
import SQLite3
import Testing

@testable import Persistence

@Suite("Migration runner")
struct MigrationRunnerTests {
    static let addTable = Migration(
        version: 2,
        statements: "CREATE TABLE extra (value INTEGER) STRICT",
        setVersion: "PRAGMA user_version = 2"
    )
    static let failingStep = Migration(
        version: 2,
        statements: "CREATE TABLE extra (value INTEGER) STRICT; INSERT INTO missing VALUES (1);",
        setVersion: "PRAGMA user_version = 2"
    )

    @Test("An empty database gets schema version 1 with all tables and no snapshot")
    func emptyDatabase() throws {
        let folder = try TemporaryFolder()
        let connection = try SQLiteConnection(path: folder.path("new.sqlite"), mode: .readWrite)
        let backups = Recorder()
        let runner = MigrationRunner(migrations: Migration.library) { backups.add($0) }
        #expect(try runner.run(on: connection) == .current)
        #expect(try connection.integer("PRAGMA user_version") == 1)
        let tables = try Self.names(
            connection,
            "SELECT name FROM sqlite_schema WHERE type = 'table' ORDER BY name"
        )
        #expect(tables == ["card", "library", "stroke", "stroke_erase", "text_box", "workspace"])
        #expect(backups.versions.isEmpty)
    }

    @Test("A database at the newest version stays as it is")
    func currentDatabase() throws {
        let library = try TestLibrary()
        let backups = Recorder()
        let runner = MigrationRunner(migrations: Migration.library) { backups.add($0) }
        #expect(try runner.run(on: library.connection) == .current)
        #expect(backups.versions.isEmpty)
    }

    @Test("A database with a newer version is reported and not changed")
    func newerDatabase() throws {
        let library = try TestLibrary()
        try library.connection.execute("PRAGMA user_version = 7")
        let runner = MigrationRunner(migrations: Migration.library) { _ in }
        #expect(try runner.run(on: library.connection) == .newer(version: 7))
        #expect(try library.connection.integer("PRAGMA user_version") == 7)
    }

    @Test("A database of version 0 with tables is not a Pointer library")
    func unknownDatabase() throws {
        let folder = try TemporaryFolder()
        let connection = try SQLiteConnection(path: folder.path("other.sqlite"), mode: .readWrite)
        try connection.execute("CREATE TABLE other (value INTEGER)")
        let runner = MigrationRunner(migrations: Migration.library) { _ in }
        #expect(throws: PersistenceError.unknownSchema) { try runner.run(on: connection) }
    }

    @Test("An older database gets a snapshot first, then all steps in one transaction")
    func olderDatabase() throws {
        let library = try TestLibrary()
        let backups = Recorder()
        let runner = MigrationRunner(migrations: Migration.library + [Self.addTable]) { version in
            #expect((try? library.connection.integer("PRAGMA user_version")) == 1)
            backups.add(version)
        }
        #expect(try runner.run(on: library.connection) == .current)
        #expect(backups.versions == [1])
        #expect(try library.connection.integer("PRAGMA user_version") == 2)
        #expect(try library.connection.integer("SELECT count(*) FROM extra") == 0)
    }

    @Test("A failed step rolls back, so the old schema and its rows stay")
    func failedStep() throws {
        let library = try TestLibrary()
        try library.write(try Values.workspace(), WorkspaceRow.upsert, WorkspaceRow.bind)
        let runner = MigrationRunner(migrations: Migration.library + [Self.failingStep]) { _ in }
        #expect(
            throws: PersistenceError.sqlite(code: SQLITE_ERROR, message: "no such table: missing")
        ) {
            try runner.run(on: library.connection)
        }
        #expect(try library.connection.integer("PRAGMA user_version") == 1)
        #expect(
            try library.connection.integer(
                "SELECT count(*) FROM sqlite_schema WHERE name = 'extra'"
            ) == 0
        )
        #expect(try library.rows(WorkspaceRow.selectLive, WorkspaceRow.read).count == 1)
    }

    @Test("A failed snapshot stops the migration before any step")
    func failedBackup() throws {
        let library = try TestLibrary()
        let runner = MigrationRunner(
            migrations: Migration.library + [Self.addTable],
            backup: Self.failingBackup
        )
        #expect(
            throws: PersistenceError.sqlite(code: SQLITE_FULL, message: "database or disk is full")
        ) {
            try runner.run(on: library.connection)
        }
        #expect(try library.connection.integer("PRAGMA user_version") == 1)
    }

    static func failingBackup(_ version: Int64) throws(PersistenceError) {
        throw .sqlite(code: SQLITE_FULL, message: "database or disk is full")
    }

    static func names(_ connection: SQLiteConnection, _ sql: StaticString) throws -> [String] {
        let statement = try connection.prepare(sql)
        var names: [String] = []
        while try statement.step(), names.count < 100 {
            names.append(statement.string(at: 0) ?? "")
        }
        return names
    }
}

/// Collects the versions that the backup function receives.
final class Recorder {
    private(set) var versions: [Int64] = []

    func add(_ version: Int64) { versions.append(version) }
}
