import Foundation
import SQLite3
import Testing

@testable import Persistence

@Suite("SQLite statement")
struct SQLiteStatementTests {
    /// Extended result codes from sqlite3.h. Swift does not import these macros.
    static let constraintCheck = SQLITE_CONSTRAINT | (1 << 8)
    static let constraintDatatype = SQLITE_CONSTRAINT | (12 << 8)

    @Test(
        "An integer goes in and comes back unchanged",
        arguments: [Int64.min, -1, 0, 1, Int64.max]
    )
    func integerRoundTrip(value: Int64) throws {
        let table = try ValueTable("INTEGER")
        let (connection, insert) = (table.connection, table.insert)
        try insert.bind(value, at: 1)
        #expect(try insert.step() == false)
        let read = try connection.prepare("SELECT value FROM item")
        #expect(try read.step())
        #expect(read.int64(at: 0) == value)
        #expect(!read.isNull(at: 0))
    }

    @Test(
        "A floating-point number goes in and comes back unchanged",
        arguments: [-1_000_000.5, -0.0, 0, 1e-300, 1_000_000.25, Double.greatestFiniteMagnitude]
    )
    func doubleRoundTrip(value: Double) throws {
        let table = try ValueTable("REAL")
        let (connection, insert) = (table.connection, table.insert)
        try insert.bind(value, at: 1)
        #expect(try insert.step() == false)
        let read = try connection.prepare("SELECT value FROM item")
        #expect(try read.step())
        // SQLite stores -0.0 as 0.0. Both compare equal, so a position does not change.
        #expect(read.double(at: 0) == value)
    }

    @Test(
        "Text goes in and comes back unchanged",
        arguments: ["", "Workspace", "\u{1F1E9}\u{1F1F0} flag", "zero\u{0}byte", "äöü ß"]
    )
    func textRoundTrip(value: String) throws {
        let table = try ValueTable("TEXT")
        let (connection, insert) = (table.connection, table.insert)
        try insert.bind(value, at: 1)
        #expect(try insert.step() == false)
        let read = try connection.prepare("SELECT value, length(value) FROM item")
        #expect(try read.step())
        #expect(read.string(at: 0) == value)
        // length() stops at the first U+0000, so Model refuses U+0000 in text (D-57).
        let counted = value.unicodeScalars.prefix { $0 != "\u{0}" }.count
        #expect(read.int64(at: 1) == Int64(counted))
    }

    @Test(
        "Bytes go in and come back unchanged, and empty bytes are not NULL",
        arguments: [Data(), Data([0]), Data([1, 2, 3, 255]), Data(repeating: 7, count: 4_800)]
    )
    func dataRoundTrip(value: Data) throws {
        let table = try ValueTable("BLOB")
        let (connection, insert) = (table.connection, table.insert)
        try insert.bind(value, at: 1)
        #expect(try insert.step() == false)
        let read = try connection.prepare("SELECT value, value IS NULL FROM item")
        #expect(try read.step())
        #expect(read.data(at: 0) == value)
        #expect(read.int64(at: 1) == 0)
    }

    @Test("NULL goes in and reads as NULL in each read")
    func nullRoundTrip() throws {
        let table = try ValueTable("BLOB")
        let (connection, insert) = (table.connection, table.insert)
        try insert.bindNull(at: 1)
        #expect(try insert.step() == false)
        let read = try connection.prepare("SELECT value FROM item")
        #expect(try read.step())
        #expect(read.isNull(at: 0))
        #expect(read.data(at: 0) == nil)
        #expect(read.string(at: 0) == nil)
    }

    @Test("A statement reads all rows in order and then reports the end")
    func rows() throws {
        let table = try ValueTable("INTEGER")
        let (connection, insert) = (table.connection, table.insert)
        for value in Int64(1)...3 {
            try insert.reset()
            try insert.bind(value, at: 1)
            #expect(try insert.step() == false)
            #expect(insert.changes == 1)
        }
        let read = try connection.prepare("SELECT value FROM item ORDER BY value")
        var values: [Int64] = []
        while try read.step(), values.count < 4 {
            values.append(read.int64(at: 0))
        }
        #expect(values == [1, 2, 3])
    }

    @Test("A failed step throws with the SQLite message, and the statement works again")
    func failedStep() throws {
        let folder = try TemporaryFolder()
        let connection = try SQLiteConnection(path: folder.path("check.sqlite"), mode: .readWrite)
        try connection.execute(
            "CREATE TABLE item (value TEXT NOT NULL CHECK (length(value) <= 3)) STRICT"
        )
        let insert = try connection.prepare("INSERT INTO item (value) VALUES (?)")
        try insert.bind("long", at: 1)
        #expect(
            throws: PersistenceError.sqlite(
                code: Self.constraintCheck,
                message: "CHECK constraint failed: length(value) <= 3"
            )
        ) {
            try insert.step()
        }
        try insert.reset()
        try insert.bind("ok", at: 1)
        #expect(try insert.step() == false)
        #expect(try connection.integer("SELECT count(*) FROM item") == 1)
    }

    @Test("A value of the wrong type is refused by a STRICT table")
    func strictType() throws {
        let table = try ValueTable("INTEGER")
        let insert = table.insert
        try insert.bind("text", at: 1)
        #expect(
            throws: PersistenceError.sqlite(
                code: Self.constraintDatatype,
                message: "cannot store TEXT value in INTEGER column item.value"
            )
        ) {
            try insert.step()
        }
    }

    @Test("Text with bytes that are not UTF-8 reads as nil")
    func invalidText() throws {
        let folder = try TemporaryFolder()
        let connection = try SQLiteConnection(path: folder.path("utf8.sqlite"), mode: .readWrite)
        let read = try connection.prepare("SELECT CAST(x'C328' AS TEXT)")
        #expect(try read.step())
        #expect(read.string(at: 0) == nil)
    }
}

/// A table with one column of one type, in its own folder. The folder lives as long as the
/// connection, because a removed folder breaks the open database.
private struct ValueTable {
    let folder: TemporaryFolder
    let connection: SQLiteConnection
    let insert: SQLiteStatement

    init(_ type: String) throws {
        folder = try TemporaryFolder()
        connection = try SQLiteConnection(path: folder.path("values.sqlite"), mode: .readWrite)
        switch type {
        case "INTEGER": try connection.execute("CREATE TABLE item (value INTEGER) STRICT")
        case "REAL": try connection.execute("CREATE TABLE item (value REAL) STRICT")
        case "TEXT": try connection.execute("CREATE TABLE item (value TEXT) STRICT")
        default: try connection.execute("CREATE TABLE item (value BLOB) STRICT")
        }
        insert = try connection.prepare("INSERT INTO item (value) VALUES (?)")
    }
}
