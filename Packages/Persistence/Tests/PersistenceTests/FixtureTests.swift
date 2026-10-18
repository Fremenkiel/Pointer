import Foundation
import Geometry
import Model
import Testing

@testable import Persistence

/// The fixture of each schema version opens and reads (TEST-08, storage.md section 6).
@Suite("Schema fixtures")
struct FixtureTests {
    @Test("The fixture of version 1 has the same schema as a new library")
    func schemaMatches() throws {
        let fixture = try TestLibrary(fixture: "library-v1")
        let fresh = try TestLibrary()
        let sql: StaticString = """
            SELECT type || ' ' || name || ': ' || sql FROM sqlite_schema
            WHERE sql IS NOT NULL ORDER BY name
            """
        let fixtureSchema = try MigrationRunnerTests.names(fixture.connection, sql)
        #expect(fixtureSchema == (try MigrationRunnerTests.names(fresh.connection, sql)))
        #expect(fixtureSchema.count == 9)
    }

    @Test("The fixture of version 1 opens without a migration and gives the expected live rows")
    func readsRows() throws {
        let fixture = try TestLibrary(fixture: "library-v1")
        let runner = MigrationRunner(migrations: Migration.library)
        #expect(try runner.snapshotVersion(of: fixture.connection) == nil)
        #expect(try runner.run(on: fixture.connection, hasSnapshot: false) == .current)

        let workspaces = try fixture.rows(WorkspaceRow.selectLive, WorkspaceRow.read)
        #expect(workspaces == [try Values.workspace()])
        let cards = try fixture.rows(CardRow.selectLive, canvas: Values.canvas, CardRow.read)
        #expect(
            cards == [
                try Card(
                    id: Values.id(3),
                    meta: RecordMeta(created: Values.early),
                    canvasID: Values.canvas,
                    frame: Rect(origin: Point(x: -10.5, y: 20), size: Size(width: 64, height: 48)),
                    title: "Card",
                    sortKey: FractionalIndex(rawValue: "V")
                )
            ]
        )
        let textBoxes = try fixture.rows(
            TextBoxRow.selectLive,
            canvas: Values.canvas,
            TextBoxRow.read
        )
        #expect(textBoxes.map(\.text) == ["Hello"])
        let strokes = try fixture.rows(StrokeRow.selectLive, canvas: Values.canvas, StrokeRow.read)
        #expect(strokes.map(\.id) == [Values.id(5)])
        #expect(strokes.first?.points.values == Values.points.values)
        #expect(strokes.first?.bounds == Values.stroke(5).bounds)
        let erased = try fixture.rows(
            EraseRow.selectByStroke,
            strokeID: Values.id(6),
            EraseRow.read
        )
        #expect(erased.map(\.erased) == [Values.late])
    }
}
