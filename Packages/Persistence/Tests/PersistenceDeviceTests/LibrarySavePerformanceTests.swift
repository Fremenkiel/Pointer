import Foundation
import Geometry
import Model
import Persistence
import XCTest

/// The time of one save of the library on the device (architecture.md section 12). The budget
/// is 50 ms off the main actor. The times are valid on a device only. The class runs on the main
/// actor for `XCTContext`. The saves themselves run on the executor of the repository.
@MainActor
final class LibrarySavePerformanceTests: XCTestCase {
    /// The save budget of architecture.md section 12, in milliseconds.
    private static let budgetMilliseconds = 50.0
    /// The saves of each measurement.
    private static let saveCount = 50
    /// The control points of one stroke, as the dense content of M2.
    private static let pointsPerStroke = 300
    /// The strokes of one second of fast handwriting.
    private static let strokesPerSecond = 10
    /// The strokes of a heavy save, for the headroom of the budget.
    private static let heavyStrokes = 240

    func testSaveOfOneSecondOfHandwriting() async throws {
        let times = try await Self.measureSaves(strokesPerSave: Self.strokesPerSecond)
        let line = Self.report("one second, \(Self.strokesPerSecond) strokes", times)
        XCTAssertLessThanOrEqual(times.last ?? .infinity, Self.budgetMilliseconds, line)
    }

    func testSaveOfTwoHundredFortyStrokes() async throws {
        let times = try await Self.measureSaves(strokesPerSave: Self.heavyStrokes)
        let line = Self.report("\(Self.heavyStrokes) strokes", times)
        XCTAssertLessThanOrEqual(times.last ?? .infinity, Self.budgetMilliseconds, line)
    }

    /// Returns the sorted times of `saveCount` saves in milliseconds.
    private static func measureSaves(strokesPerSave: Int) async throws -> [Double] {
        let files = FileManager()
        let folder = files.temporaryDirectory.appending(
            path: "LibrarySave-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { removeFolder(folder, files) }
        let device = DeviceID(rawValue: UUID())
        let path = folder.appending(path: "library.sqlite").path(percentEncoded: false)
        let configuration = SQLiteLibraryRepository.Configuration(
            databasePath: path,
            temporaryFolder: folder,
            device: device,
            wallClock: SystemWallClock(),
            timer: ContinuousSaveTimer()
        )
        let repository = SQLiteLibraryRepository(configuration: configuration) { _ in }
        _ = try await repository.open { _ in }
        // SQLite must not hold the files at the delete (task 1.1 of docs/m9-plan.md).
        defer { await repository.close() }
        let canvas = CanvasID(rawValue: UUID())
        let clock = ContinuousClock()
        var times: [Double] = []
        for save in 0..<saveCount {
            let rows = (0..<strokesPerSave).map { index in
                LibraryChange.stroke(stroke(save * strokesPerSave + index, canvas, device))
            }
            try await repository.send(rows)
            let duration = try await clock.measure { try await repository.saveNow() }
            times.append(duration / .milliseconds(1))
        }
        return times.sorted()
    }

    private static func removeFolder(_ folder: URL, _ files: FileManager) {
        do {
            try files.removeItem(at: folder)
        } catch {
            XCTFail("The test folder stays behind: \(error)")
        }
    }

    private static func stroke(_ number: Int, _ canvas: CanvasID, _ device: DeviceID) -> Stroke {
        let points = (0..<pointsPerStroke).map { index in
            InkPoint(x: Float(index), y: Float(index % 7), force: 0.5, time: Float(index) / 240)
        }
        return Stroke(
            id: StrokeID(rawValue: UUID()),
            canvasID: canvas,
            created: HybridTimestamp(wallMillis: UInt64(number), counter: 0, device: device),
            origin: Point(x: Double(number), y: 0),
            width: 2,
            points: InkPoints(points)
        )
    }

    private static func report(_ name: String, _ times: [Double]) -> String {
        let line = String(
            format: "save of %@: median %.2f ms, slowest %.2f ms over %d saves",
            name,
            times[times.count / 2],
            times.last ?? 0,
            times.count
        )
        XCTContext.runActivity(named: line) { _ in }
        PerformanceRecord.attach([
            "save.median.ms": times[times.count / 2],
            "save.slowest.ms": times.last ?? 0,
        ])
        return line
    }
}
