import Foundation
import Model
import SQLite3
import Testing

@testable import Persistence

/// Each CHECK constraint takes its limit and refuses one past it (storage.md section 9, TEST-06).
@Suite("Schema constraints")
struct ConstraintTests {
    @Test(
        "A workspace title has 1 to 120 code points",
        arguments: [(0, false), (1, true), (120, true), (121, false)]
    )
    func workspaceTitle(length: Int, isAccepted: Bool) throws {
        let library = try TestLibrary()
        let result = try Self.insert(library, "INSERT INTO workspace VALUES (?, ?, 'V', ?, ?, 0)") {
            try $0.bind(Values.workspaceID)
            try $0.bind(String(repeating: "a", count: length))
            try $0.bind(Values.early)
            try $0.bind(Values.early)
        }
        #expect(result == isAccepted)
    }

    @Test(
        "A tombstone flag is 0 or 1 in each table",
        arguments: [(0, true), (1, true), (2, false), (-1, false)]
    )
    func deletedFlag(value: Int64, isAccepted: Bool) throws {
        let library = try TestLibrary()
        try library.write(Values.stroke(6), StrokeRow.insert, StrokeRow.bind)
        let tables: [StaticString] = [
            "INSERT INTO workspace VALUES (?, 'T', 'V', ?, ?, ?)",
            "INSERT INTO card VALUES (?, X'00', 0, 0, 64, 48, NULL, 'V', ?, ?, ?)",
            "INSERT INTO text_box VALUES (?, X'00', 0, 0, 'T', 'V', ?, ?, ?)",
            "INSERT INTO stroke_erase VALUES (?, ?, ?, ?)",
        ]
        for sql in tables {
            let result = try Self.insert(library, sql) {
                try $0.bind(Values.id(6) as StrokeID)
                try $0.bind(Values.early)
                try $0.bind(Values.early)
                try $0.bind(value)
            }
            #expect(result == isAccepted, "\(sql)")
        }
    }

    @Test(
        "A card is at least the minimum size (TEST-06)",
        arguments: [
            (Limits.minCardWidth, Limits.minCardHeight, true),
            (Limits.minCardWidth.nextDown, Limits.minCardHeight, false),
            (Limits.minCardWidth, Limits.minCardHeight.nextDown, false),
        ]
    )
    func cardSize(width: Double, height: Double, isAccepted: Bool) throws {
        let library = try TestLibrary()
        let result = try Self.insert(
            library,
            "INSERT INTO card VALUES (?, ?, 0, 0, ?, ?, NULL, 'V', ?, ?, 0)"
        ) {
            try $0.bind(Values.id(3) as CardID)
            try $0.bind(Values.canvas)
            try $0.bind(width)
            try $0.bind(height)
            try $0.bind(Values.early)
            try $0.bind(Values.early)
        }
        #expect(result == isAccepted)
    }

    @Test(
        "A card title has at most 120 code points",
        arguments: [(0, true), (120, true), (121, false)]
    )
    func cardTitle(length: Int, isAccepted: Bool) throws {
        let library = try TestLibrary()
        let result = try Self.insert(
            library,
            "INSERT INTO card VALUES (?, ?, 0, 0, 64, 48, ?, 'V', ?, ?, 0)"
        ) {
            try $0.bind(Values.id(3) as CardID)
            try $0.bind(Values.canvas)
            try $0.bind(String(repeating: "b", count: length))
            try $0.bind(Values.early)
            try $0.bind(Values.early)
        }
        #expect(result == isAccepted)
    }

    @Test(
        "A text box text has 1 to 10,000 code points",
        arguments: [(0, false), (1, true), (Limits.maxTextLength, true), (10_001, false)]
    )
    func text(length: Int, isAccepted: Bool) throws {
        let library = try TestLibrary()
        let result = try Self.insert(
            library,
            "INSERT INTO text_box VALUES (?, ?, 0, 0, ?, 'V', ?, ?, 0)"
        ) {
            try $0.bind(Values.id(5) as TextBoxID)
            try $0.bind(Values.canvas)
            try $0.bind(String(repeating: "c", count: length))
            try $0.bind(Values.early)
            try $0.bind(Values.early)
        }
        #expect(result == isAccepted)
    }

    @Test(
        "A stroke has 2 to 16,384 points, and its BLOB holds 16 bytes per point",
        arguments: [
            (1, 16, false), (2, 32, true), (16_384, 262_144, true), (16_385, 262_160, false),
            (2, 31, false),
        ]
    )
    func strokePoints(count: Int64, byteCount: Int, isAccepted: Bool) throws {
        let library = try TestLibrary()
        let sql: StaticString = "INSERT INTO stroke VALUES (?, ?, ?, 0, 0, 2, 0, 0, 1, 1, ?, ?)"
        let result = try Self.insert(library, sql, lastBlob: Data(count: byteCount)) {
            try $0.bind(Values.id(6) as StrokeID)
            try $0.bind(Values.canvas)
            try $0.bind(Values.early)
            try $0.bind(count)
        }
        #expect(result == isAccepted)
    }

    @Test("An erase record needs an existing stroke")
    func eraseForeignKey() throws {
        let library = try TestLibrary()
        let record = EraseRecord(
            strokeID: Values.id(6),
            erased: Values.early,
            modified: Values.early,
            isDeleted: false
        )
        #expect(
            throws: PersistenceError.sqlite(
                code: SQLITE_CONSTRAINT | (3 << 8),
                message: "FOREIGN KEY constraint failed"
            )
        ) {
            try library.write(record, EraseRow.upsert, EraseRow.bind)
        }
    }

    /// Returns true if the insert works, false if a constraint refuses it.
    static func insert(
        _ library: TestLibrary,
        _ sql: StaticString,
        lastBlob: Data? = nil,
        _ bind: (inout RowBinder) throws -> Void
    ) throws -> Bool {
        let statement = try library.connection.prepare(sql)
        var binder = try RowBinder(statement)
        try bind(&binder)
        if let lastBlob { try statement.bind(lastBlob, at: statement.parameterCount) }
        do {
            _ = try statement.step()
            return true
        } catch .sqlite(let code, _) where code & 0xFF == SQLITE_CONSTRAINT {
            return false
        }
    }
}
