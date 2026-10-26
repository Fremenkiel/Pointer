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

/// The waits of 1 ms for a SIGKILL of the own process to land: at most 1 second (FLOW-03). The
/// restore mode runs before the code below this line, so its constants must stand above it.
let maxStopWaits = 1_000
/// The exit status of a helper that the SIGKILL did not stop.
let missedStopStatus: Int32 = 2

let arguments = CommandLine.arguments
if arguments.count == 7, arguments[1] == "restore" {
    await runRestore(Array(arguments.dropFirst(2)))
}
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

/// Stops the process with SIGKILL now. The signal can land on another thread and let the
/// caller run on to `exit` (POSIX `kill`), so the caller waits for the stop. If the stop does
/// not come, the helper exits with `missedStopStatus`.
func stopNow() -> Never {
    kill(getpid(), SIGKILL)
    for _ in 0..<maxStopWaits {
        usleep(1_000)
    }
    exit(missedStopStatus)
}

/// Stops the process with SIGKILL 0.5 ms from now, from a thread of its own. The stop lands in
/// the copy, which runs in steps of pages on the calling task.
func stopDuringCopy() {
    let stop = Thread {
        usleep(500)
        kill(getpid(), SIGKILL)
    }
    stop.start()
}

/// The restore mode of the crash test of D-180. Arguments: the path of the library, the
/// temporary folder, the backups folder, the picked snapshot, and the step at which the helper
/// stops itself with SIGKILL: "marker" after the marker, "copy" right at the start of the copy,
/// or "done" after the copy. The library stays as each stop leaves it.
func runRestore(_ values: [String]) async {
    precondition(
        values.count == 5 && ["marker", "copy", "done"].contains(values[4]),
        "The restore mode takes 5 arguments and a known stop step"
    )
    let (library, temporary, backups, picked, step) =
        (values[0], URL(filePath: values[1]), URL(filePath: values[2]), values[3], values[4])
    let repository = SQLiteLibraryRepository(
        configuration: SQLiteLibraryRepository.Configuration(
            databasePath: library,
            temporaryFolder: temporary,
            device: DeviceID(rawValue: UUID()),
            wallClock: SystemWallClock(),
            timer: ContinuousSaveTimer()
        )
    ) { _ in }
    let writer = SnapshotWriter(
        configuration: SnapshotWriter.Configuration(
            databasePath: library,
            temporaryFolder: temporary,
            backupsFolder: backups,
            wallClock: SystemWallClock(),
            timeZone: .gmt
        )
    )
    do {
        _ = try await repository.open { _ in }
        let fallback = try await writer.writePreRestoreSnapshot()
        try RestoreMarker(libraryPath: library, backupsFolder: backups).write(snapshot: fallback)
        if step == "marker" { stopNow() }
        let checked = try await SnapshotImport(temporaryFolder: temporary)
            .copyAndCheck(URL(filePath: picked))
        if step == "copy" { stopDuringCopy() }
        try await repository.restore(from: checked, stop: RestoreStop())
        if step == "done" { stopNow() }
    } catch {
        exit(EXIT_FAILURE)
    }
    exit(EXIT_SUCCESS)
}
