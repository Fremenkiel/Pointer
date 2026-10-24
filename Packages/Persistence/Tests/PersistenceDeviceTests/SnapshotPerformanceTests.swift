import Foundation
import Geometry
import Model
import XCTest
import os

@testable import Persistence

/// The time of a snapshot of a large library on the device, and the time of the saves that run
/// during it (D-32). The times are valid on a device only.
@MainActor
final class SnapshotPerformanceTests: XCTestCase {
    /// The save budget of architecture.md section 12, in milliseconds.
    private static let saveBudgetMilliseconds = 50.0
    /// The strokes of the library: the stroke content of D-56.
    private static let strokeCount = 20_000
    /// The strokes of one save.
    private static let strokesPerSave = 10
    /// A save above this time counts as slow in the report, in milliseconds.
    private static let slowSaveMilliseconds = 10.0
    /// The saves of the control run without a snapshot.
    private static let controlSaves = 640
    /// The most saves while the snapshot runs.
    private static let maxSaves = 1_000

    func testSnapshotOfTwentyThousandStrokesWithSaves() async throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Snapshot times are valid on a device only.")
        #else
            let run = try await Self.withFilledLibrary { repository, path, folder in
                let writer = SnapshotWriter(
                    configuration: SnapshotWriter.Configuration(
                        databasePath: path,
                        temporaryFolder: folder,
                        backupsFolder: folder.appending(path: "Backups"),
                        wallClock: SystemWallClock(),
                        timeZone: .current
                    )
                )
                return try await Self.snapshotWithSaves(writer, repository)
            }
            let snapshotTime = run.snapshotMilliseconds
            let saveTimes = run.saveMilliseconds
            let size = run.bytes
            let line = String(
                format: "snapshot of %d strokes, %d MB: %.0f ms; saves: %@",
                Self.strokeCount,
                size >> 20,
                snapshotTime,
                Self.summary(saveTimes)
            )
            XCTContext.runActivity(named: line) { _ in }
            XCTAssertGreaterThan(saveTimes.count, 0, line)
            XCTAssertLessThanOrEqual(saveTimes.max() ?? 0, Self.saveBudgetMilliseconds, line)
        #endif
    }

    func testSameSavesWithoutSnapshot() async throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Save times are valid on a device only.")
        #else
            let saveTimes = try await Self.withFilledLibrary { repository, _, _ in
                let clock = ContinuousClock()
                var saveTimes: [Double] = []
                for save in 0..<Self.controlSaves {
                    try await repository.send(Self.rows(save, count: Self.strokesPerSave))
                    let duration = try await clock.measure { try await repository.saveNow() }
                    saveTimes.append(duration / .milliseconds(1))
                }
                return saveTimes
            }
            let line = "no snapshot: saves: " + Self.summary(saveTimes)
            XCTContext.runActivity(named: line) { _ in }
            XCTAssertLessThanOrEqual(saveTimes.max() ?? 0, Self.saveBudgetMilliseconds, line)
        #endif
    }

    /// Returns the median, the 99th percentile, the slowest time with its index, and the count
    /// of slow saves.
    private static func summary(_ times: [Double]) -> String {
        let sorted = times.sorted()
        guard let slowest = sorted.last, let index = times.firstIndex(of: slowest) else {
            return "none"
        }
        return String(
            format:
                "%d saves, median %.2f ms, p99 %.2f ms, slowest %.2f ms at save %d, %d over 10 ms",
            sorted.count,
            sorted[sorted.count / 2],
            sorted[sorted.count * 99 / 100],
            slowest,
            index,
            sorted.filter { $0 > slowSaveMilliseconds }.count
        )
    }

    private struct SnapshotRun {
        let bytes: Int
        let snapshotMilliseconds: Double
        let saveMilliseconds: [Double]
    }

    /// Runs a snapshot and saves 10 strokes again and again until the snapshot ends.
    private static func snapshotWithSaves(
        _ writer: SnapshotWriter,
        _ repository: SQLiteLibraryRepository
    ) async throws -> SnapshotRun {
        let clock = ContinuousClock()
        let isDone = OSAllocatedUnfairLock(initialState: false)
        let start = clock.now
        let snapshot = Task {
            defer { isDone.withLock { $0 = true } }
            return try await writer.writeSnapshotNow()
        }
        var saveTimes: [Double] = []
        for save in 0..<maxSaves where !isDone.withLock({ $0 }) {
            try await repository.send(rows(save, count: strokesPerSave))
            let duration = try await clock.measure { try await repository.saveNow() }
            saveTimes.append(duration / .milliseconds(1))
        }
        let url = try await snapshot.value
        return SnapshotRun(
            bytes: try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0,
            snapshotMilliseconds: start.duration(to: clock.now) / .milliseconds(1),
            saveMilliseconds: saveTimes
        )
    }

    /// Runs `body` on a filled library in a folder of its own. The last checkpoint ends and the
    /// repository goes before the folder goes. A checkpoint after the delete failed with a disk
    /// I/O error and ran into the measures of the next suite (TEST-04).
    private static func withFilledLibrary<Result>(
        _ body: (SQLiteLibraryRepository, String, URL) async throws -> Result
    ) async throws -> Result {
        let files = FileManager()
        let folder = files.temporaryDirectory.appending(
            path: "Snapshot-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { removeFolder(folder, files) }
        return try await run(body, in: folder)
    }

    /// Runs `body` on a new filled library in `folder`, and closes the repository, which waits
    /// for its last checkpoint (task 1.1 of docs/m9-plan.md).
    private static func run<Result>(
        _ body: (SQLiteLibraryRepository, String, URL) async throws -> Result,
        in folder: URL
    ) async throws -> Result {
        let path = folder.appending(path: "library.sqlite").path(percentEncoded: false)
        let repository = try await filledRepository(path: path, folder: folder)
        defer { await repository.close() }
        return try await body(repository, path, folder)
    }

    private static func filledRepository(
        path: String,
        folder: URL
    ) async throws -> SQLiteLibraryRepository {
        let repository = SQLiteLibraryRepository(
            configuration: SQLiteLibraryRepository.Configuration(
                databasePath: path,
                temporaryFolder: folder,
                device: DeviceID(rawValue: UUID()),
                wallClock: SystemWallClock(),
                timer: ContinuousSaveTimer()
            )
        ) { _ in }
        _ = try await repository.open { _ in }
        for batch in 0..<(strokeCount / 1_000) {
            try await repository.send(rows(batch + maxSaves, count: 1_000))
            try await repository.saveNow()
        }
        return repository
    }

    private static func rows(_ batch: Int, count: Int) -> [LibraryChange] {
        let device = DeviceID(rawValue: UUID())
        let canvas = CanvasID(rawValue: UUID())
        let points = InkPoints(
            (0..<300).map { InkPoint(x: Float($0), y: Float($0 % 7), force: 0.5, time: 0) }
        )
        return (0..<count).map { index in
            .stroke(
                Stroke(
                    id: StrokeID(rawValue: UUID()),
                    canvasID: canvas,
                    created: HybridTimestamp(
                        wallMillis: UInt64(batch * count + index),
                        counter: 0,
                        device: device
                    ),
                    origin: Point(x: Double(index), y: 0),
                    width: 2,
                    points: points
                )
            )
        }
    }

    private static func removeFolder(_ folder: URL, _ files: FileManager) {
        do {
            try files.removeItem(at: folder)
        } catch {
            XCTFail("The test folder stays behind: \(error)")
        }
    }
}
