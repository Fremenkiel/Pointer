import Foundation
import Model
import Testing

@testable import Persistence

/// A damaged row throws a fault for that row and never crashes (storage.md section 9). The tests
/// turn off the CHECK constraints to write the damage, as a damaged file has it.
@Suite("Corrupt rows")
struct CorruptionTests {
    @Test(
        "A damaged stroke row throws a corrupt row fault",
        arguments: [
            Damage(
                "UPDATE stroke SET points = zeroblob(31)",
                "point BLOB of 31 bytes for 2 points"
            ),
            Damage("UPDATE stroke SET point_count = 1, points = zeroblob(16)", "point count 1"),
            Damage(
                "UPDATE stroke SET points = unhex('0000C07F' || printf('%058d', 0))",
                "point BLOB of 33 bytes"
            ),
            Damage(
                "UPDATE stroke SET points = unhex('0000C07F' || printf('%056d', 0))",
                "point is not finite"
            ),
            Damage("UPDATE stroke SET width = 0", "width 0.0"),
            Damage("UPDATE stroke SET width = 1e300", "width 1e+300"),
            Damage("UPDATE stroke SET created = zeroblob(27)", "clock value of 27 bytes"),
            Damage("UPDATE stroke SET id = zeroblob(15)", "ID of 15 bytes"),
        ]
    )
    func stroke(damage: Damage) throws {
        let library = try TestLibrary()
        try library.write(Values.stroke(6), StrokeRow.insert, StrokeRow.bind)
        try damage.apply(to: library)
        #expect(throws: PersistenceError.self) {
            try library.rows(StrokeRow.selectLive, canvas: Values.canvas, StrokeRow.read)
        }
        let error = Self.error {
            _ = try library.rows(StrokeRow.selectLive, canvas: Values.canvas, StrokeRow.read)
        }
        #expect(
            error.map { "\($0)" }?.contains(damage.reason) == true,
            "\(String(describing: error))"
        )
    }

    @Test(
        "A damaged workspace row throws a corrupt row fault",
        arguments: [
            Damage("UPDATE workspace SET title = ''", "invalidTitle(length: 0)"),
            Damage("UPDATE workspace SET title = CAST(X'C328' AS TEXT)", "text is not UTF-8"),
            Damage("UPDATE workspace SET sort_key = 'V0'", "trailing zero"),
            Damage("UPDATE workspace SET modified = X''", "clock value of 0 bytes"),
        ]
    )
    func workspace(damage: Damage) throws {
        let library = try TestLibrary()
        try library.write(try Values.workspace(), WorkspaceRow.insert, WorkspaceRow.bind)
        try damage.apply(to: library)
        let error = Self.error { _ = try library.rows(WorkspaceRow.selectLive, WorkspaceRow.read) }
        #expect(
            error.map { "\($0)" }?.contains(damage.reason) == true,
            "\(String(describing: error))"
        )
    }

    @Test(
        "A damaged card, text box, or erase record throws a corrupt row fault",
        arguments: [
            Damage("UPDATE card SET width = -1", "negative card size"),
            Damage("UPDATE card SET width = 10", "card size 10.0 by 48.0"),
            Damage("UPDATE text_box SET text = ''", "invalidText(length: 0)"),
            Damage("UPDATE stroke_erase SET is_deleted = 2", "flag 2"),
        ]
    )
    func nodes(damage: Damage) throws {
        let library = try TestLibrary()
        try library.write(try Values.card(3), CardRow.upsert, CardRow.bind)
        try library.write(try Values.textBox(5), TextBoxRow.upsert, TextBoxRow.bind)
        try library.write(Values.stroke(6), StrokeRow.insert, StrokeRow.bind)
        let record = EraseRecord(
            strokeID: Values.id(6),
            erased: Values.early,
            modified: Values.early,
            isDeleted: false
        )
        try library.write(record, EraseRow.upsert, EraseRow.bind)
        try damage.apply(to: library)
        let error = Self.error {
            _ = try library.rows(CardRow.selectLive, canvas: Values.canvas, CardRow.read)
            _ = try library.rows(TextBoxRow.selectLive, canvas: Values.canvas, TextBoxRow.read)
            _ = try library.rows(EraseRow.selectByStroke, strokeID: Values.id(6), EraseRow.read)
        }
        #expect(
            error.map { "\($0)" }?.contains(damage.reason) == true,
            "\(String(describing: error))"
        )
    }

    static func error(_ body: () throws -> Void) -> PersistenceError? {
        do {
            try body()
            return nil
        } catch {
            return error as? PersistenceError
        }
    }

    struct Damage: Sendable, CustomTestStringConvertible {
        let sql: StaticString
        let reason: String

        init(_ sql: StaticString, _ reason: String) {
            self.sql = sql
            self.reason = reason
        }

        var testDescription: String { reason }

        /// Writes the damage with the CHECK constraints off.
        func apply(to library: TestLibrary) throws {
            try library.connection.execute("PRAGMA ignore_check_constraints = ON")
            try library.connection.execute(sql)
        }
    }
}
