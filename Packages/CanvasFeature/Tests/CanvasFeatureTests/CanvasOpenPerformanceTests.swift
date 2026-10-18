import Foundation
import Geometry
import Model
import Persistence
import Rendering
import XCTest

/// M3 acceptance 3: a canvas with the content of D-56 opens to the first frame in under 300 ms
/// on the device (architecture.md section 12, PERF-03). The simulator skips it.
@MainActor
final class CanvasOpenPerformanceTests: XCTestCase {
    /// The budget of architecture.md section 12, in milliseconds.
    private static let budgetMilliseconds = 300.0
    /// The opens of the measurement.
    private static let openCount = 10
    /// The content of D-56.
    private static let strokeCount = 20_000
    private static let pointsPerStroke = 300
    private static let cardCount = 5_000
    private static let textBoxCount = 5_000
    private static let textLength = 200
    /// The strokes of one save while the test fills the library.
    private static let batch = 1_000
    /// The view of the iPad Pro 11-inch (M4) in landscape, in points, and its scale.
    private static let viewSize = Size(width: 1210, height: 834)
    private static let displayScale = 2.0

    func testOpenOfTwentyThousandStrokesAndTenThousandNodes() async throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Open times are valid on a device only.")
        #else
            let folder = try Self.makeFolder()
            defer { Self.removeFolder(folder) }
            let configuration = SQLiteLibraryRepository.Configuration(
                databasePath: folder.appending(path: "library.sqlite").path(percentEncoded: false),
                temporaryFolder: folder,
                device: DeviceID(rawValue: UUID()),
                wallClock: SystemWallClock(),
                timer: ContinuousSaveTimer()
            )
            let canvas = CanvasID(rawValue: UUID())
            // The app keeps one repository open and opens each canvas through it.
            let repository = SQLiteLibraryRepository(configuration: configuration) { _ in }
            _ = try await repository.open { _ in }
            try await Self.fill(repository, canvas, device: configuration.device)
            let renderer = try CanvasRenderer()
            var times: [Double] = []
            for _ in 0..<Self.openCount {
                times.append(try await Self.open(canvas, repository, renderer))
            }
            times.sort()
            let line = String(
                format: "open to the first frame: median %.1f ms, slowest %.1f ms over %d opens",
                times[times.count / 2],
                times.last ?? 0,
                times.count
            )
            XCTContext.runActivity(named: line) { _ in }
            XCTAssertLessThanOrEqual(times.last ?? .infinity, Self.budgetMilliseconds, line)
        #endif
    }

    /// Times the load of the canvas and its first frame, and notes the time of the load alone.
    private static func open(
        _ canvas: CanvasID,
        _ repository: SQLiteLibraryRepository,
        _ renderer: CanvasRenderer
    ) async throws -> Double {
        let clock = ContinuousClock()
        let start = clock.now
        let content = try await repository.content(of: canvas)
        let loaded = clock.now
        _ = try renderer.renderImage(
            of: Array(content.strokes.values),
            camera: Camera(center: .zero, zoom: 1),
            viewSize: viewSize,
            displayScale: displayScale
        )
        let total = start.duration(to: clock.now) / .milliseconds(1)
        let load = start.duration(to: loaded) / .milliseconds(1)
        XCTAssertEqual(content.strokes.count, strokeCount)
        XCTAssertEqual(content.nodeCount, cardCount + textBoxCount)
        let line = String(format: "load %.1f ms, total %.1f ms", load, total)
        XCTContext.runActivity(named: line) { _ in }
        return total
    }

    /// Fills the library with the content of D-56 on one canvas.
    private static func fill(
        _ repository: SQLiteLibraryRepository,
        _ canvas: CanvasID,
        device: DeviceID
    ) async throws {
        let points = InkPoints(
            (0..<pointsPerStroke).map {
                InkPoint(x: Float($0) / 10, y: Float($0 % 7), force: 0.5, time: 0)
            }
        )
        for start in stride(from: 0, to: strokeCount, by: batch) {
            let rows = (start..<start + batch).map { index in
                LibraryChange.stroke(
                    Stroke(
                        id: StrokeID(rawValue: UUID()),
                        canvasID: canvas,
                        created: HybridTimestamp(
                            wallMillis: 1,
                            counter: UInt32(index),
                            device: device
                        ),
                        origin: Point(
                            x: Double(index % 200) * 40 - 4_000,
                            y: Double(index / 200) * 40 - 2_000
                        ),
                        width: 2,
                        points: points
                    )
                )
            }
            try await repository.send(rows)
            try await repository.saveNow()
        }
        try await repository.send(try nodes(canvas, device))
        try await repository.saveNow()
    }

    private static func nodes(_ canvas: CanvasID, _ device: DeviceID) throws -> [LibraryChange] {
        let meta = RecordMeta(created: HybridTimestamp(wallMillis: 2, counter: 0, device: device))
        let key = try FractionalIndex(rawValue: "V")
        let text = String(repeating: "node ", count: textLength / 5)
        let cards = try (0..<cardCount).map { index in
            LibraryChange.card(
                try Card(
                    id: CardID(rawValue: UUID()),
                    meta: meta,
                    canvasID: canvas,
                    frame: Rect(
                        origin: Point(x: Double(index % 100) * 120, y: Double(index / 100) * 90),
                        size: Size(width: 100, height: 70)
                    ),
                    title: "Card \(index)",
                    sortKey: key
                )
            )
        }
        let textBoxes = try (0..<textBoxCount).map { index in
            LibraryChange.textBox(
                try TextBox(
                    id: TextBoxID(rawValue: UUID()),
                    meta: meta,
                    canvasID: canvas,
                    origin: Point(
                        x: Double(index % 100) * 120,
                        y: Double(index / 100) * 90 + 5_000
                    ),
                    text: text,
                    sortKey: key
                )
            )
        }
        return cards + textBoxes
    }

    /// Makes the folder of the library. The product owner allowed this file access in the
    /// test on 2026-10-18 (D-60).
    private static func makeFolder() throws -> URL {
        let folder = URL.temporaryDirectory.appending(
            path: "CanvasOpen-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        // swiftlint:disable:next arch_04_file_system
        try FileManager().createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Removes the folder of the library, about 95 MB (D-60).
    private static func removeFolder(_ folder: URL) {
        do {
            // swiftlint:disable:next arch_04_file_system
            try FileManager().removeItem(at: folder)
        } catch {
            XCTFail("The test folder stays behind: \(error)")
        }
    }
}
