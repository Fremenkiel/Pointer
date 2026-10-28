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
        let runner = MigrationRunner(migrations: Migration.library)
        #expect(try runner.run(on: connection, hasSnapshot: false) == .current)
        #expect(try connection.integer("PRAGMA user_version") == 1)
        let tables = try Self.names(
            connection,
            "SELECT name FROM sqlite_schema WHERE type = 'table' ORDER BY name"
        )
        #expect(tables == ["card", "library", "stroke", "stroke_erase", "text_box", "workspace"])
    }

    @Test("A database at the newest version stays as it is")
    func currentDatabase() throws {
        let library = try TestLibrary()
        let runner = MigrationRunner(migrations: Migration.library)
        #expect(try runner.run(on: library.connection, hasSnapshot: true) == .current)
    }

    @Test("A database with a newer version is reported and not changed")
    func newerDatabase() throws {
        let library = try TestLibrary()
        try library.connection.execute("PRAGMA user_version = 7")
        let runner = MigrationRunner(migrations: Migration.library)
        #expect(try runner.run(on: library.connection, hasSnapshot: true) == .newer(version: 7))
        #expect(try library.connection.integer("PRAGMA user_version") == 7)
    }

    @Test("A database of version 0 with tables is not a Pointer library")
    func unknownDatabase() throws {
        let folder = try TemporaryFolder()
        let connection = try SQLiteConnection(path: folder.path("other.sqlite"), mode: .readWrite)
        try connection.execute("CREATE TABLE other (value INTEGER)")
        let runner = MigrationRunner(migrations: Migration.library)
        #expect(throws: PersistenceError.unknownSchema) {
            try runner.run(on: connection, hasSnapshot: false)
        }
    }

    @Test("An older database needs a snapshot, and then all steps run in one transaction")
    func olderDatabase() throws {
        let library = try TestLibrary()
        let runner = MigrationRunner(migrations: Migration.library + [Self.addTable])
        #expect(try runner.snapshotVersion(of: library.connection) == 1)
        #expect(try runner.run(on: library.connection, hasSnapshot: true) == .current)
        #expect(try library.connection.integer("PRAGMA user_version") == 2)
        #expect(try library.connection.integer("SELECT count(*) FROM extra") == 0)
        #expect(try runner.snapshotVersion(of: library.connection) == nil)
    }

    @Test("An empty or a current database needs no snapshot")
    func noSnapshot() throws {
        let folder = try TemporaryFolder()
        let empty = try SQLiteConnection(path: folder.path("empty.sqlite"), mode: .readWrite)
        let runner = MigrationRunner(migrations: Migration.library)
        #expect(try runner.snapshotVersion(of: empty) == nil)
        let current = try TestLibrary()
        #expect(try runner.snapshotVersion(of: current.connection) == nil)
    }

    @Test("A failed step rolls back, so the old schema and its rows stay")
    func failedStep() throws {
        let library = try TestLibrary()
        try library.write(try Values.workspace(), WorkspaceRow.insert, WorkspaceRow.bind)
        let runner = MigrationRunner(migrations: Migration.library + [Self.failingStep])
        #expect(
            throws: PersistenceError.sqlite(code: SQLITE_ERROR, message: "no such table: missing")
        ) {
            try runner.run(on: library.connection, hasSnapshot: true)
        }
        #expect(try library.connection.integer("PRAGMA user_version") == 1)
        #expect(
            try library.connection.integer(
                "SELECT count(*) FROM sqlite_schema WHERE name = 'extra'"
            ) == 0
        )
        #expect(try library.rows(WorkspaceRow.selectLive, WorkspaceRow.read).count == 1)
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
