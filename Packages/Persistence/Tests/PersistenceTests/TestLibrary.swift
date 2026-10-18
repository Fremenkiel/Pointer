import Foundation
import Geometry
import Model
import Testing

@testable import Persistence

/// A library with schema version 1 in its own temporary folder (TEST-04).
struct TestLibrary {
    let folder: TemporaryFolder
    let connection: SQLiteConnection

    init(file: String = "library.sqlite") throws {
        folder = try TemporaryFolder()
        connection = try SQLiteConnection(path: folder.path(file), mode: .readWrite)
        let runner = MigrationRunner(migrations: Migration.library)
        _ = try runner.run(on: connection, hasSnapshot: false)
    }

    /// Opens a copy of a fixture database of the test bundle.
    init(fixture name: String) throws {
        folder = try TemporaryFolder()
        let source = try #require(
            Bundle.module.url(forResource: name, withExtension: "sqlite", subdirectory: "Fixtures")
        )
        try FileManager().copyItem(at: source, to: folder.url.appending(path: "fixture.sqlite"))
        connection = try SQLiteConnection(path: folder.path("fixture.sqlite"), mode: .readWrite)
    }

    /// Writes one row with `bind` through `sql`.
    func write<Row>(
        _ row: Row,
        _ sql: StaticString,
        _ bind: (Row, SQLiteStatement) throws(PersistenceError) -> Void
    ) throws {
        let statement = try connection.prepare(sql)
        try bind(row, statement)
        _ = try statement.step()
    }

    /// Reads all rows of `sql` with `read`, after `bind` sets the parameters.
    func rows<Row>(
        _ sql: StaticString,
        canvas: CanvasID? = nil,
        strokeID: StrokeID? = nil,
        _ read: (SQLiteStatement) throws(PersistenceError) -> Row
    ) throws -> [Row] {
        let statement = try connection.prepare(sql)
        var binder = try RowBinder(statement)
        if let canvas { try binder.bind(canvas) }
        if let strokeID { try binder.bind(strokeID) }
        var result: [Row] = []
        while try statement.step(), result.count < Limits.maxStrokesPerCanvas {
            result.append(try read(statement))
        }
        return result
    }
}

enum Values {
    static let device = DeviceID(
        rawValue: UUID(uuid: (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    )
    static let early = HybridTimestamp(wallMillis: 1_700_000_000_000, counter: 0, device: device)
    static let late = HybridTimestamp(wallMillis: 1_700_000_000_001, counter: 0, device: device)
    static let meta = RecordMeta(created: early, modified: late, isDeleted: false)

    static func id<ID: EntityIdentifier>(_ byte: UInt8) -> ID {
        ID(rawValue: UUID(uuid: (3, byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
    }

    static let workspaceID: WorkspaceID = id(1)
    static var canvas: CanvasID { CanvasID(workspaceID) }

    static let points = InkPoints([
        InkPoint(x: 0, y: 0, force: 0.5, time: 0), InkPoint(x: 3, y: 4, force: -1, time: 0.25),
    ])

    static func stroke(_ byte: UInt8, canvas: CanvasID = Values.canvas) -> Stroke {
        Stroke(
            id: id(byte),
            canvasID: canvas,
            created: early,
            origin: Point(x: 100, y: 200),
            width: 2,
            points: points
        )
    }

    static func workspace(_ byte: UInt8 = 1, title: String = "Fixture") throws -> Workspace {
        try Workspace(
            id: id(byte),
            meta: meta,
            title: title,
            sortKey: FractionalIndex(rawValue: "V")
        )
    }

    static func card(_ byte: UInt8, isDeleted: Bool = false) throws -> Card {
        try Card(
            id: id(byte),
            meta: RecordMeta(created: early, modified: late, isDeleted: isDeleted),
            canvasID: canvas,
            frame: Rect(origin: Point(x: -10.5, y: 20), size: Size(width: 64, height: 48)),
            title: "Card",
            sortKey: FractionalIndex(rawValue: "V")
        )
    }

    static func textBox(_ byte: UInt8, isDeleted: Bool = false) throws -> TextBox {
        try TextBox(
            id: id(byte),
            meta: RecordMeta(created: early, modified: late, isDeleted: isDeleted),
            canvasID: canvas,
            origin: Point(x: 1, y: 2),
            text: "Hello",
            sortKey: FractionalIndex(rawValue: "W")
        )
    }
}
