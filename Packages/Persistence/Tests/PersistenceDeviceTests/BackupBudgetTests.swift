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
        let line = String(
            format: "D-56 back up now: %.3f s, peak memory %.0f MB; restore: %.3f s, %.0f MB",
            backUp.seconds,
            backUp.megabytes,
            restore.seconds,
            restore.megabytes
        )
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertLessThanOrEqual(backUp.seconds, Self.backUpBudgetSeconds, line)
        XCTAssertLessThanOrEqual(restore.seconds, Self.restoreBudgetSeconds, line)
        XCTAssertLessThanOrEqual(backUp.megabytes, Self.memoryBudgetMegabytes, line)
        XCTAssertLessThanOrEqual(restore.megabytes, Self.memoryBudgetMegabytes, line)
        _ = try await repository.open { _ in }
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
