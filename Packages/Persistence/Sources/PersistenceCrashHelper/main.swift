import Foundation
import Geometry
import Model
import Persistence

// The helper of the crash test of M3 acceptance 1 (D-54). It saves strokes through the
// repository without a pause, as a pencil that never stops, until the test stops it with
// SIGKILL. Each stroke carries the wall time of its creation, so the test can find the newest
// saved stroke. Arguments: the path of the library and the temporary folder.

/// The most strokes of one run: far more than 10 seconds at 100 strokes per second (FLOW-03).
let maxStrokes = 100_000
/// The pause between two strokes: 100 strokes per second, faster than a hand writes.
let strokeInterval = Duration.milliseconds(10)
/// The control points of each stroke.
let pointsPerStroke = 300

let arguments = CommandLine.arguments
guard arguments.count == 3 else { exit(EXIT_FAILURE) }
let device = DeviceID(rawValue: UUID())
let wallClock = SystemWallClock()
let repository = SQLiteLibraryRepository(
    configuration: SQLiteLibraryRepository.Configuration(
        databasePath: arguments[1],
        temporaryFolder: URL(filePath: arguments[2]),
        device: device,
        wallClock: wallClock,
        timer: ContinuousSaveTimer()
    )
) { _ in }
do {
    _ = try await repository.open { _ in }
} catch {
    exit(EXIT_FAILURE)
}
let canvas = CanvasID(rawValue: UUID())
let points = InkPoints(
    (0..<pointsPerStroke).map { InkPoint(x: Float($0), y: Float($0 % 7), force: 0.5, time: 0) }
)
FileHandle.standardOutput.write(Data("ready\n".utf8))
for index in 0..<maxStrokes {
    let created = HybridTimestamp(
        wallMillis: wallClock.nowMillis(),
        counter: UInt32(index),
        device: device
    )
    let stroke = Stroke(
        id: StrokeID(rawValue: UUID()),
        canvasID: canvas,
        created: created,
        origin: .zero,
        width: 2,
        points: points
    )
    do {
        try await repository.send([.stroke(stroke)])
    } catch {
        exit(EXIT_FAILURE)
    }
    await repository.requestSave()
    try await Task.sleep(for: strokeInterval)
}
