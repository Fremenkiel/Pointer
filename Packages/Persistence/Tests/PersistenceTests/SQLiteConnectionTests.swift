import Foundation
import SQLite3
import Testing

@testable import Persistence

@Suite("SQLite connection")
struct SQLiteConnectionTests {
    @Test("A new database gets the settings of storage.md section 3.1 and a 4,096-byte page")
    func newDatabaseSettings() throws {
        let folder = try TemporaryFolder()
        let connection = try SQLiteConnection(path: folder.path("new.sqlite"), mode: .readWrite)
        try Self.expectLibrarySettings(connection)
    }

    @Test("A database that opens again keeps its settings")
    func reopenedSettings() throws {
        let folder = try TemporaryFolder()
        let path = folder.path("again.sqlite")
        do {
            let first = try SQLiteConnection(path: path, mode: .readWrite)
            try first.execute("CREATE TABLE item (value INTEGER) STRICT")
        }
        let second = try SQLiteConnection(path: path, mode: .readWrite)
        try Self.expectLibrarySettings(second)
        #expect(try second.integer("SELECT count(*) FROM item") == 0)
    }

    @Test("A read-only connection reads but refuses a write with the SQLite message")
    func readOnly() throws {
        let folder = try TemporaryFolder()
        let path = folder.path("read.sqlite")
        let writer = try SQLiteConnection(path: path, mode: .readWrite)
        try writer.execute("CREATE TABLE item (value INTEGER) STRICT; INSERT INTO item VALUES (7);")
        let reader = try SQLiteConnection(path: path, mode: .readOnly)
        #expect(try reader.integer("SELECT value FROM item") == 7)
        #expect(try reader.integer("PRAGMA foreign_keys") == 1)
        #expect(try reader.integer("PRAGMA busy_timeout") == 2000)
        #expect(
            throws: PersistenceError.sqlite(
                code: SQLITE_READONLY,
                message: "attempt to write a readonly database"
            )
        ) {
            try reader.execute("INSERT INTO item VALUES (8)")
        }
    }

    @Test("A read-only open of a missing file throws with the SQLite message")
    func missingFile() throws {
        let folder = try TemporaryFolder()
        #expect(
            throws: PersistenceError.sqlite(
                code: SQLITE_CANTOPEN,
                message: "unable to open database file"
            )
        ) {
            try SQLiteConnection(path: folder.path("missing.sqlite"), mode: .readOnly)
        }
    }

    @Test("A statement that does not compile throws with the SQLite message")
    func syntaxError() throws {
        let folder = try TemporaryFolder()
        let connection = try SQLiteConnection(path: folder.path("syntax.sqlite"), mode: .readWrite)
        #expect(
            throws: PersistenceError.sqlite(
                code: SQLITE_ERROR,
                message: "near \"SELEC\": syntax error"
            )
        ) {
            try connection.prepare("SELEC 1")
        }
        #expect(
            throws: PersistenceError.sqlite(code: SQLITE_ERROR, message: "no such table: missing")
        ) {
            try connection.execute("DELETE FROM missing")
        }
    }

    @Test("A query without a row throws instead of giving a value")
    func noRow() throws {
        let folder = try TemporaryFolder()
        let connection = try SQLiteConnection(path: folder.path("empty.sqlite"), mode: .readWrite)
        try connection.execute("CREATE TABLE item (value TEXT) STRICT")
        #expect(throws: PersistenceError.self) { try connection.integer("SELECT 1 FROM item") }
        #expect(throws: PersistenceError.self) { try connection.text("SELECT value FROM item") }
    }

    @Test("A file that is not a database throws at the open")
    func notADatabase() throws {
        let folder = try TemporaryFolder()
        let path = folder.path("text.sqlite")
        try Data(repeating: 0x41, count: 4096).write(to: URL(filePath: path))
        #expect(
            throws: PersistenceError.sqlite(code: SQLITE_NOTADB, message: "file is not a database")
        ) {
            try SQLiteConnection(path: path, mode: .readWrite)
        }
    }

    static func expectLibrarySettings(_ connection: SQLiteConnection) throws {
        #expect(try connection.text("PRAGMA journal_mode") == "wal")
        #expect(try connection.integer("PRAGMA synchronous") == 1)
        #expect(try connection.integer("PRAGMA foreign_keys") == 1)
        #expect(try connection.integer("PRAGMA auto_vacuum") == 2)
        #expect(try connection.integer("PRAGMA busy_timeout") == 2000)
        #expect(try connection.integer("PRAGMA page_size") == SQLiteConnection.pageSize)
    }
}
