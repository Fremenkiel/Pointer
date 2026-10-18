import SQLite3
import Testing

@Suite("System SQLite")
struct SQLiteVersionTests {
    /// SQLite 3.37.0, the first version with `STRICT` tables (storage.md 3.3, review B-4). SQLite
    /// encodes a version as major * 1,000,000 + minor * 1,000 + patch.
    static let strictTablesVersion: Int32 = 3_037_000

    @Test("The system SQLite supports STRICT tables")
    func supportsStrictTables() {
        #expect(sqlite3_libversion_number() >= Self.strictTablesVersion)
    }
}
