import Foundation
import Geometry
import Model
import Testing

@testable import Persistence

@Suite("Row codecs")
struct RowCodecTests {
    @Test("A workspace goes into its row and back unchanged, and a second write of its ID fails")
    func workspace() throws {
        let library = try TestLibrary()
        let workspace = try Values.workspace()
        try library.write(workspace, WorkspaceRow.insert, WorkspaceRow.bind)
        #expect(try library.rows(WorkspaceRow.selectLive, WorkspaceRow.read) == [workspace])
        let renamed = try Values.workspace(title: "Renamed")
        #expect(throws: PersistenceError.self) {
            try library.write(renamed, WorkspaceRow.insert, WorkspaceRow.bind)
        }
        #expect(try library.rows(WorkspaceRow.selectLive, WorkspaceRow.read) == [workspace])
    }

    @Test("A card goes into its row and back unchanged, with and without a title")
    func card() throws {
        let library = try TestLibrary()
        let card = try Values.card(3)
        let untitled = try Card(
            id: Values.id(4),
            meta: Values.meta,
            canvasID: Values.canvas,
            frame: card.frame,
            title: "",
            sortKey: card.sortKey
        )
        try library.write(card, CardRow.upsert, CardRow.bind)
        try library.write(untitled, CardRow.upsert, CardRow.bind)
        let rows = try library.rows(CardRow.selectLive, canvas: Values.canvas, CardRow.read)
        #expect(Set(rows) == [card, untitled])
        // An empty title is no title, so the row holds NULL (3.2.18).
        let untitledRows = try library.connection.integer(
            "SELECT count(*) FROM card WHERE title IS NULL"
        )
        #expect(untitledRows == 1)
    }

    @Test("A text box goes into its row and back unchanged")
    func textBox() throws {
        let library = try TestLibrary()
        let textBox = try Values.textBox(5)
        try library.write(textBox, TextBoxRow.upsert, TextBoxRow.bind)
        #expect(
            try library.rows(TextBoxRow.selectLive, canvas: Values.canvas, TextBoxRow.read) == [
                textBox
            ]
        )
    }

    @Test("A stroke goes into its row and back with the same points, origin, width, and bounds")
    func stroke() throws {
        let library = try TestLibrary()
        let stroke = Values.stroke(6)
        try library.write(stroke, StrokeRow.insert, StrokeRow.bind)
        let read = try #require(
            try library.rows(StrokeRow.selectLive, canvas: Values.canvas, StrokeRow.read).first
        )
        #expect(read.id == stroke.id)
        #expect(read.canvasID == stroke.canvasID)
        #expect(read.created == stroke.created)
        #expect(read.origin == stroke.origin)
        #expect(read.width == stroke.width)
        #expect(read.points.values == stroke.points.values)
        #expect(read.bounds == stroke.bounds)
    }

    @Test("The point BLOB holds 16 little-endian bytes per point: x, y, force, time")
    func pointLayout() throws {
        let library = try TestLibrary()
        try library.write(Values.stroke(6), StrokeRow.insert, StrokeRow.bind)
        let blob = try #require(
            try library.rows("SELECT points FROM stroke") { statement in statement.data(at: 0) }
                .first
        )
        var expected = Data()
        for value: Float in [0, 0, 0.5, 0, 3, 4, -1, 0.25] {
            expected.append(
                contentsOf: [0, 8, 16, 24].map { UInt8(truncatingIfNeeded: value.bitPattern >> $0) }
            )
        }
        #expect(blob == expected)
    }

    @Test("A stroke with the largest point count goes into its row and back unchanged")
    func largestStroke() throws {
        let library = try TestLibrary()
        let points = InkPoints(
            (0..<Limits.maxPointsPerStroke).map {
                InkPoint(x: Float($0), y: 1, force: 0.5, time: 0)
            }
        )
        let stroke = Stroke(
            id: Values.id(7),
            canvasID: Values.canvas,
            created: Values.early,
            origin: .zero,
            width: 2,
            points: points
        )
        try library.write(stroke, StrokeRow.insert, StrokeRow.bind)
        let read = try library.rows(StrokeRow.selectLive, canvas: Values.canvas, StrokeRow.read)
        #expect(read.first?.points.values == points.values)
    }

    @Test("An erase record goes into its row and back, and an undo updates the same row")
    func eraseRecord() throws {
        let library = try TestLibrary()
        try library.write(Values.stroke(6), StrokeRow.insert, StrokeRow.bind)
        let record = EraseRecord(
            strokeID: Values.id(6),
            erased: Values.early,
            modified: Values.early,
            isDeleted: false
        )
        try library.write(record, EraseRow.upsert, EraseRow.bind)
        #expect(
            try library.rows(EraseRow.selectByStroke, strokeID: Values.id(6), EraseRow.read) == [
                record
            ]
        )
        let undone = EraseRecord(
            strokeID: Values.id(6),
            erased: Values.early,
            modified: Values.late,
            isDeleted: true
        )
        try library.write(undone, EraseRow.upsert, EraseRow.bind)
        #expect(
            try library.rows(EraseRow.selectByStroke, strokeID: Values.id(6), EraseRow.read) == [
                undone
            ]
        )
    }

    @Test("The live reads skip tombstones, erased strokes, and other canvases")
    func liveRows() throws {
        let library = try TestLibrary()
        try Self.writeMixedRows(library)
        let canvas = Values.canvas
        let cards = try library.rows(CardRow.selectLive, canvas: canvas, CardRow.read)
        #expect(cards.map(\.id) == [Values.id(3)])
        let textBoxes = try library.rows(TextBoxRow.selectLive, canvas: canvas, TextBoxRow.read)
        #expect(textBoxes.map(\.id) == [Values.id(5)])
        let strokes = try library.rows(StrokeRow.selectLive, canvas: canvas, StrokeRow.read)
        #expect(Set(strokes.map(\.id)) == [Values.id(7), Values.id(9)])
    }

    /// Writes a live and a deleted card and text box, three strokes on the canvas, one stroke on
    /// another canvas, a live erase of stroke 8, and an undone erase of stroke 9.
    static func writeMixedRows(_ library: TestLibrary) throws {
        try library.write(try Values.card(3), CardRow.upsert, CardRow.bind)
        try library.write(try Values.card(4, isDeleted: true), CardRow.upsert, CardRow.bind)
        try library.write(try Values.textBox(5), TextBoxRow.upsert, TextBoxRow.bind)
        try library.write(
            try Values.textBox(6, isDeleted: true),
            TextBoxRow.upsert,
            TextBoxRow.bind
        )
        for byte: UInt8 in [7, 8, 9] {
            try library.write(Values.stroke(byte), StrokeRow.insert, StrokeRow.bind)
        }
        try library.write(
            Values.stroke(10, canvas: Values.id(99)),
            StrokeRow.insert,
            StrokeRow.bind
        )
        for (byte, isUndone) in [(UInt8(8), false), (UInt8(9), true)] {
            let record = EraseRecord(
                strokeID: Values.id(byte),
                erased: Values.early,
                modified: isUndone ? Values.late : Values.early,
                isDeleted: isUndone
            )
            try library.write(record, EraseRow.upsert, EraseRow.bind)
        }
    }
}
