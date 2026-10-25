import Testing

@testable import Persistence

/// The reads of the columns of a row (review after M8, section 3.2, item 10).
@Suite("Row reader")
struct RowReaderTests {
    @Test("A NULL number is a damaged row")
    func nullNumber() throws {
        let connection = try SQLiteConnection(path: SQLiteConnection.memoryPath, mode: .memory)
        let statement = try connection.prepare("SELECT NULL")
        #expect(try statement.step())
        var reader = RowReader(statement, table: "test")
        #expect(throws: PersistenceError.self) { try reader.double() }
    }

    @Test("A finite number reads as stored")
    func finiteNumber() throws {
        let connection = try SQLiteConnection(path: SQLiteConnection.memoryPath, mode: .memory)
        let statement = try connection.prepare("SELECT 2.5")
        #expect(try statement.step())
        var reader = RowReader(statement, table: "test")
        #expect(try reader.double() == 2.5)
    }
}
