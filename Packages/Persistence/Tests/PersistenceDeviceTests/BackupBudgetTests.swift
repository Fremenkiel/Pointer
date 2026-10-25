import Foundation
import Geometry
import Model
import XCTest
import os

@testable import Persistence

/// The time and the peak memory growth of "Back up now" and of a restore of the D-56 library,
/// against the budgets of D-165 (task 4.3 of docs/m9-plan.md, architecture.md section 12).
@MainActor
final class BackupBudgetTests: XCTestCase {
    /// "Back up now" of the D-56 library: the save and the snapshot (D-165).
    private static let backUpBudgetSeconds = 0.5
    /// A restore of the D-56 library: the copy, the checks, the pre-restore snapshot, the
    /// backup, and the checkpoint (D-165).
    private static let restoreBudgetSeconds = 1.5
    /// The peak memory growth of each of the two (D-165).
    private static let memoryBudgetMegabytes = 50.0
    /// The time between two reads of the available memory (section 1.1 of docs/m9-plan.md).
    private static let pollInterval = Duration.microseconds(250)

    func testBackUpNowAndRestoreOfD56Library() async throws {
        let library = try await D56Library.make()
        defer { await library.remove() }
        let folder = library.folder
        let writer = SnapshotWriter(
            configuration: SnapshotWriter.Configuration(
                databasePath: folder.appending(path: "library.sqlite").path(percentEncoded: false),
                temporaryFolder: folder,
                backupsFolder: folder.appending(path: "Backups", directoryHint: .isDirectory),
                wallClock: SystemWallClock(),
                timeZone: .current
            )
        )
        let repository = library.repository
        let backUp = try await Self.measure {
            try await repository.saveNow()
            return try await writer.writeSnapshotNow()
        }
        let importer = SnapshotImport(temporaryFolder: folder)
        let snapshot = backUp.value
        let restore = try await Self.measure {
            let checked = try await importer.copyAndCheck(snapshot)
            _ = try await writer.writePreRestoreSnapshot()
            try await repository.restore(from: checked, stop: RestoreStop())
            await importer.discard(checked)
        }
        let line = Self.report(backUp: backUp, restore: restore)
        XCTAssertLessThanOrEqual(backUp.seconds, Self.backUpBudgetSeconds, line)
        XCTAssertLessThanOrEqual(restore.seconds, Self.restoreBudgetSeconds, line)
        XCTAssertLessThanOrEqual(backUp.megabytes, Self.memoryBudgetMegabytes, line)
        XCTAssertLessThanOrEqual(restore.megabytes, Self.memoryBudgetMegabytes, line)
        _ = try await repository.open { _ in }
    }

    /// A restore of a canvas at the stroke limit: 200,000 handwriting strokes of 60 points, as
    /// in D-144. The copy holds its pages until `SQLITE_DONE` (D-180), so its peak grows with
    /// the library. The peak must stay below half of the memory that the process has at the
    /// start, so that the copy ends before a memory stop (D-180, item 5).
    func testRestorePeakOfStrokeLimit() async throws {
        let folder = URL.temporaryDirectory.appending(
            path: "RestorePeak-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager().createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager().removeItem(at: folder) }
        let path = folder.appending(path: "library.sqlite").path(percentEncoded: false)
        let repository = try await Self.fillStrokeLimit(at: path, folder: folder)
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
        let size = try snapshot.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let importer = SnapshotImport(temporaryFolder: folder)
        let checked = try await importer.copyAndCheck(snapshot)
        try await OnScreenCanvas.waitForSteadyMemory()
        let available = Double(os_proc_available_memory()) / 1_048_576
        let restore = try await Self.measure {
            try await repository.restore(from: checked, stop: RestoreStop())
        }
        await importer.discard(checked)
        await repository.close()
        let line = String(
            format: "Restore of 200,000 strokes: %.0f MB file, %.2f s, peak %.0f MB of %.0f MB",
            Double(size) / 1_048_576,
            restore.seconds,
            restore.megabytes,
            available
        )
        XCTContext.runActivity(named: line) { _ in }
        PerformanceRecord.attach(["restore-limit.s": restore.seconds])
        XCTAssertLessThan(restore.megabytes, available / 2, line)
    }

    /// The strokes of one save while the library fills.
    private static let fillBatch = 5_000

    /// Opens a new library at `path` and fills one canvas with `Limits.maxStrokesPerCanvas`
    /// strokes of 60 points.
    private static func fillStrokeLimit(
        at path: String,
        folder: URL
    ) async throws -> SQLiteLibraryRepository {
        let device = DeviceID(rawValue: UUID())
        let repository = SQLiteLibraryRepository(
            configuration: SQLiteLibraryRepository.Configuration(
                databasePath: path,
                temporaryFolder: folder,
                device: device,
                wallClock: SystemWallClock(),
                timer: ContinuousSaveTimer()
            )
        ) { _ in }
        _ = try await repository.open { _ in }
        let canvas = CanvasID(rawValue: UUID())
        let points = InkPoints(
            (0..<60).map { InkPoint(x: Float($0) / 4, y: Float($0 % 9), force: 0.5, time: 0) }
        )
        for start in stride(from: 0, to: Limits.maxStrokesPerCanvas, by: fillBatch) {
            let rows = (start..<start + fillBatch).map { index in
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
                            x: Double(index % 400) * 20,
                            y: Double(index / 400) * 20
                        ),
                        width: 2,
                        points: points
                    )
                )
            }
            try await repository.send(rows)
            try await repository.saveNow()
        }
        return repository
    }

    /// Writes the times and the memory of both as an activity and as samples (D-172).
    ///
    /// - Returns: The line of the activity.
    private static func report<First, Second>(
        backUp: Measure<First>,
        restore: Measure<Second>
    ) -> String {
        let line = String(
            format: "D-56 back up now: %.3f s, peak memory %.0f MB; restore: %.3f s, %.0f MB",
            backUp.seconds,
            backUp.megabytes,
            restore.seconds,
            restore.megabytes
        )
        XCTContext.runActivity(named: line) { _ in }
        PerformanceRecord.attach([
            "back-up.s": backUp.seconds,
            "back-up-peak.mb": backUp.megabytes,
            "restore.s": restore.seconds,
            "restore-peak.mb": restore.megabytes,
        ])
        return line
    }

    /// The time, the peak memory growth, and the result of `body` after steady memory.
    private struct Measure<Value> {
        let value: Value
        let seconds: Double
        let megabytes: Double
    }

    /// Runs `body` after 1.5 s of steady memory and reads the available memory every 0.25 ms.
    private static func measure<Value: Sendable>(
        _ body: @escaping @Sendable () async throws -> Value
    ) async throws -> Measure<Value> {
        try await OnScreenCanvas.waitForSteadyMemory()
        let available = os_proc_available_memory()
        var lowest = available
        let isDone = OSAllocatedUnfairLock(initialState: false)
        let clock = ContinuousClock()
        let start = clock.now
        let task = Task.detached {
            defer { isDone.withLock { $0 = true } }
            return try await body()
        }
        // The bound covers 10 minutes at the poll interval (FLOW-03).
        for _ in 0..<2_400_000 where !isDone.withLock({ $0 }) {
            lowest = min(lowest, os_proc_available_memory())
            try await Task.sleep(for: pollInterval)
        }
        let value = try await task.value
        return Measure(
            value: value,
            seconds: start.duration(to: clock.now) / .seconds(1),
            megabytes: Double(available - min(available, lowest)) / 1_048_576
        )
    }
}
