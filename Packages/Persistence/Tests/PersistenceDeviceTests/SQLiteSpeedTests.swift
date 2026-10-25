import Foundation
import Geometry
import Model
import Persistence
import SQLite3
import XCTest

/// The read and write speed of SQLite through the repository on the device, for research.md
/// section 5 (review B-4). The records are text boxes of about 400 bytes, as on the Mac. Each
/// time is the best of 5 runs with a warm cache. It runs on the iPad only (D-77).
@MainActor
final class SQLiteSpeedTests: XCTestCase {
    private static let runs = 5
    private static let recordCount = 1_000
    private static let changedCount = 5
    /// About 400 bytes per row with the IDs and the clock values.
    private static let textLength = 300

    func testReadAndWriteSpeed() async throws {
        let operations = [
            TimedOperation("write 1,000 in one transaction", "write-one") {
                try await Self.writeInOneTransaction($0, $1)
            },
            TimedOperation("write 1,000 in 1,000 transactions", "write-many") {
                try await Self.writeInManyTransactions($0, $1)
            },
            TimedOperation("read 1,000", "read") { try await Self.readRecords($0, $1) },
            TimedOperation("save 5 changed", "save-changed") {
                try await Self.saveChanged($0, $1)
            },
            TimedOperation("write and read one stroke of 16,384 points", "large-stroke") {
                try await Self.largeStroke($0, $1)
            },
        ]
        var results: [String] = ["SQLite \(String(cString: sqlite3_libversion()))"]
        var samples: [String: Double] = [:]
        for operation in operations {
            let best = try await Self.best(operation.run)
            results.append(operation.name + " " + Self.format(best))
            samples["\(operation.key).best.ms"] = best
        }
        let line = results.joined(separator: "; ")
        XCTContext.runActivity(named: line) { _ in }
        PerformanceRecord.attach(samples)
    }

    /// Returns the best time of `runs` runs, in milliseconds. Each run gets a new library.
    /// One timed operation on a new library.
    private typealias Operation = (SQLiteLibraryRepository, CanvasID) async throws -> Duration

    /// An operation with its name in the report and its sample key (D-172).
    private struct TimedOperation {
        let name: String
        let key: String
        let run: Operation

        init(_ name: String, _ key: String, _ run: @escaping Operation) {
            self.name = name
            self.key = key
            self.run = run
        }
    }

    private static func best(
        _ run: Operation
    ) async throws -> Double {
        var best = Double.infinity
        for _ in 0..<runs {
            let folder = FileManager().temporaryDirectory.appending(
                path: "Speed-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            try FileManager().createDirectory(at: folder, withIntermediateDirectories: true)
            defer { removeFolder(folder) }
            let repository = SQLiteLibraryRepository(
                configuration: SQLiteLibraryRepository.Configuration(
                    databasePath: folder.appending(path: "library.sqlite").path(
                        percentEncoded: false
                    ),
                    temporaryFolder: folder,
                    device: device,
                    wallClock: SystemWallClock(),
                    timer: ContinuousSaveTimer()
                )
            ) { _ in }
            _ = try await repository.open { _ in }
            // SQLite must not hold the files at the delete (task 1.1 of docs/m9-plan.md).
            defer { await repository.close() }
            best = min(
                best,
                try await run(repository, CanvasID(rawValue: UUID())) / .milliseconds(1)
            )
        }
        return best
    }

    private static func writeInOneTransaction(
        _ repository: SQLiteLibraryRepository,
        _ canvas: CanvasID
    ) async throws -> Duration {
        let rows = try records(recordCount, canvas, counter: 0)
        return try await ContinuousClock().measure {
            try await repository.send(rows)
            try await repository.saveNow()
        }
    }

    private static func writeInManyTransactions(
        _ repository: SQLiteLibraryRepository,
        _ canvas: CanvasID
    ) async throws -> Duration {
        let rows = try records(recordCount, canvas, counter: 0)
        return try await ContinuousClock().measure {
            for row in rows {
                try await repository.send([row])
                try await repository.saveNow()
            }
        }
    }

    private static func readRecords(
        _ repository: SQLiteLibraryRepository,
        _ canvas: CanvasID
    ) async throws -> Duration {
        try await repository.send(try records(recordCount, canvas, counter: 0))
        try await repository.saveNow()
        _ = try await repository.content(of: canvas)
        return try await ContinuousClock().measure {
            let content = try await repository.content(of: canvas)
            XCTAssertEqual(content.textBoxes.count, recordCount)
        }
    }

    private static func saveChanged(
        _ repository: SQLiteLibraryRepository,
        _ canvas: CanvasID
    ) async throws -> Duration {
        let rows = try records(recordCount, canvas, counter: 0)
        try await repository.send(rows)
        try await repository.saveNow()
        let changed = try rows.prefix(changedCount).map { row -> LibraryChange in
            guard case .textBox(let box) = row else { return row }
            let meta = RecordMeta(
                created: box.meta.created,
                modified: timestamp(1),
                isDeleted: false
            )
            return .textBox(
                try TextBox(
                    id: box.id,
                    meta: meta,
                    canvasID: canvas,
                    origin: Point(x: 1, y: 1),
                    text: box.text,
                    sortKey: box.sortKey
                )
            )
        }
        return try await ContinuousClock().measure {
            try await repository.send(changed)
            try await repository.saveNow()
        }
    }

    private static func largeStroke(
        _ repository: SQLiteLibraryRepository,
        _ canvas: CanvasID
    ) async throws -> Duration {
        let points = InkPoints(
            (0..<Limits.maxPointsPerStroke).map { InkPoint(x: Float($0), y: 0, force: 1, time: 0) }
        )
        let stroke = Stroke(
            id: StrokeID(rawValue: UUID()),
            canvasID: canvas,
            created: timestamp(0),
            origin: .zero,
            width: 2,
            points: points
        )
        return try await ContinuousClock().measure {
            try await repository.send([.stroke(stroke)])
            try await repository.saveNow()
            let content = try await repository.content(of: canvas)
            XCTAssertEqual(content.strokes.count, 1)
        }
    }

    private static let device = DeviceID(rawValue: UUID())

    private static func timestamp(_ counter: UInt32) -> HybridTimestamp {
        HybridTimestamp(wallMillis: 1_700_000_000_000, counter: counter, device: device)
    }

    private static func records(
        _ count: Int,
        _ canvas: CanvasID,
        counter: UInt32
    ) throws -> [LibraryChange] {
        let text = String(repeating: "x", count: textLength)
        let key = try FractionalIndex(rawValue: "V")
        return try (0..<count).map { index in
            .textBox(
                try TextBox(
                    id: TextBoxID(rawValue: UUID()),
                    meta: RecordMeta(created: timestamp(counter)),
                    canvasID: canvas,
                    origin: Point(x: Double(index), y: 0),
                    text: text,
                    sortKey: key
                )
            )
        }
    }

    private static func format(_ milliseconds: Double) -> String {
        String(format: "%.2f ms", milliseconds)
    }

    private static func removeFolder(_ folder: URL) {
        do {
            try FileManager().removeItem(at: folder)
        } catch {
            XCTFail("The test folder stays behind: \(error)")
        }
    }
}
