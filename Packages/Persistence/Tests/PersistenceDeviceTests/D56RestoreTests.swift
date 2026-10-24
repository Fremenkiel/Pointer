import Foundation
import Geometry
import Model
import XCTest

@testable import Persistence

/// The restore of the D-56 library on the device: a snapshot, a change, and a restore that
/// gives all rows of the snapshot again (task 4.1 of docs/m9-plan.md, M9 acceptance 2).
@MainActor
final class D56RestoreTests: XCTestCase {
    /// The strokes that the change adds after the snapshot.
    private static let addedStrokes = 1_000

    func testRestoreOfD56LibraryGivesTheRowsOfTheSnapshot() async throws {
        let library = try await D56Library.make()
        defer { await library.remove() }
        let folder = library.folder
        let path = folder.appending(path: "library.sqlite").path(percentEncoded: false)
        let writer = SnapshotWriter(
            configuration: SnapshotWriter.Configuration(
                databasePath: path,
                temporaryFolder: folder,
                backupsFolder: folder.appending(path: "Backups", directoryHint: .isDirectory),
                wallClock: SystemWallClock(),
                timeZone: .current
            )
        )
        let snapshot = try await writer.writeSnapshotNow()
        try await Self.change(library)
        XCTAssertGreaterThan(try Self.differences(path, snapshot), 0, "The change made rows differ")
        let checked = try await SnapshotImport(temporaryFolder: folder).copyAndCheck(snapshot)
        try await library.repository.restore(from: checked, stop: RestoreStop())
        let differences = try Self.differences(path, snapshot)
        let strokes = try SQLiteConnection(path: path, mode: .readOnly)
            .integer("SELECT count(*) FROM stroke")
        let line = "D-56 restore: \(differences) rows differ, \(strokes) strokes"
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertEqual(differences, 0, line)
        XCTAssertEqual(strokes, Int64(D56Library.strokeCount), line)
        _ = try await library.repository.open { _ in }
    }

    /// Adds strokes, so that the library differs from the snapshot.
    private static func change(_ library: D56Library) async throws {
        let points = InkPoints([
            InkPoint(x: 0, y: 0, force: 1, time: 0), InkPoint(x: 5, y: 5, force: 1, time: 0.1),
        ])
        let rows = (0..<addedStrokes).map { index in
            LibraryChange.stroke(
                Stroke(
                    id: StrokeID(rawValue: UUID()),
                    canvasID: library.canvas,
                    created: HybridTimestamp(
                        wallMillis: 3,
                        counter: UInt32(index),
                        device: library.device
                    ),
                    origin: Point(x: Double(index), y: 9_000),
                    width: 2,
                    points: points
                )
            )
        }
        try await library.repository.send(rows)
        try await library.repository.saveNow()
    }

    /// Counts the rows that differ between the library at `path` and the snapshot.
    private static func differences(_ path: String, _ snapshot: URL) throws -> Int64 {
        let live = try SQLiteConnection(path: path, mode: .readOnly)
        let attach = try live.prepare("ATTACH ? AS snapshot")
        try attach.bind(snapshot.path(percentEncoded: false), at: 1)
        try LibraryStatements.run(attach)
        return try live.integer(Self.differenceCount)
    }

    /// The rows that are in one database but not in the other, in each table, as
    /// `SnapshotWriterTests.differences` counts them on the Mac.
    private static let differenceCount: StaticString = """
        SELECT
            (SELECT count(*) FROM (
                SELECT * FROM main.workspace EXCEPT SELECT * FROM snapshot.workspace))
          + (SELECT count(*) FROM (
                SELECT * FROM snapshot.workspace EXCEPT SELECT * FROM main.workspace))
          + (SELECT count(*) FROM (SELECT * FROM main.card EXCEPT SELECT * FROM snapshot.card))
          + (SELECT count(*) FROM (SELECT * FROM snapshot.card EXCEPT SELECT * FROM main.card))
          + (SELECT count(*) FROM (
                SELECT * FROM main.text_box EXCEPT SELECT * FROM snapshot.text_box))
          + (SELECT count(*) FROM (
                SELECT * FROM snapshot.text_box EXCEPT SELECT * FROM main.text_box))
          + (SELECT count(*) FROM (
                SELECT * FROM main.stroke EXCEPT SELECT * FROM snapshot.stroke))
          + (SELECT count(*) FROM (
                SELECT * FROM snapshot.stroke EXCEPT SELECT * FROM main.stroke))
          + (SELECT count(*) FROM (
                SELECT * FROM main.stroke_erase EXCEPT SELECT * FROM snapshot.stroke_erase))
          + (SELECT count(*) FROM (
                SELECT * FROM snapshot.stroke_erase EXCEPT SELECT * FROM main.stroke_erase))
          + (SELECT count(*) FROM (
                SELECT * FROM main.library EXCEPT SELECT * FROM snapshot.library))
          + (SELECT count(*) FROM (
                SELECT * FROM snapshot.library EXCEPT SELECT * FROM main.library))
        """
}
