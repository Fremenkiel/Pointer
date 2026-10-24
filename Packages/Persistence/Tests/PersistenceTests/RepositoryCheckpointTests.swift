import Foundation
import Geometry
import Model
import Testing
import os

@testable import Persistence

/// The checkpoints of the library run off the save path (D-146, storage.md section 4).
@Suite("Checkpoints of the library")
struct RepositoryCheckpointTests {
    /// The control points of one test stroke: about 2 pages of 4,096 bytes per stroke.
    private static let pointsPerStroke = 300
    /// The strokes of one save.
    private static let strokesPerSave = 50
    /// The most saves of one test.
    private static let maxSaves = 400

    private static func strokes(_ save: Int) -> [LibraryChange] {
        let points = InkPoints(
            (0..<pointsPerStroke).map {
                InkPoint(x: Float($0), y: Float($0 % 7), force: 1, time: 0)
            }
        )
        let canvas = CanvasID(rawValue: UUID())
        return (0..<strokesPerSave).map { index in
            .stroke(
                Stroke(
                    id: StrokeID(rawValue: UUID()),
                    canvasID: canvas,
                    created: HybridTimestamp(
                        wallMillis: UInt64(save * strokesPerSave + index + 1),
                        counter: 0,
                        device: Values.device
                    ),
                    origin: Point(x: Double(index), y: 0),
                    width: 2,
                    points: points
                )
            )
        }
    }

    /// Saves until the WAL holds at least `pages` pages, and returns the saves.
    private static func fill(
        _ repository: SQLiteLibraryRepository,
        toPages pages: Int
    ) async throws -> Int {
        for save in 0..<maxSaves {
            try await repository.send(strokes(save))
            try await repository.saveNow()
            if await repository.walPageCount >= pages { return save + 1 }
        }
        Issue.record("The WAL did not reach \(pages) pages")
        return maxSaves
    }

    @Test("The write connection runs no automatic checkpoint")
    func noAutomaticCheckpoint() async throws {
        let harness = try RepositoryHarness()
        let repository = harness.make(usesCheckpointer: false)
        _ = try await repository.open { _ in }
        _ = try await Self.fill(repository, toPages: 3_000)
        // The automatic checkpoint would restart the WAL at 1,000 pages.
        #expect(await repository.walPageCount >= 3_000)
    }

    @Test("The checkpointer runs after 1,000 pages, and the next save restarts the WAL")
    func checkpointerRestartsTheWAL() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        _ = try await Self.fill(repository, toPages: SQLiteLibraryRepository.checkpointPages)
        await repository.waitForCheckpoint()
        try await repository.send(Self.strokes(Self.maxSaves))
        try await repository.saveNow()
        #expect(await repository.walPageCount < SQLiteLibraryRepository.checkpointPages)
    }

    @Test("The write connection runs a checkpoint at the hard limit")
    func hardLimitCheckpoint() async throws {
        let harness = try RepositoryHarness()
        let repository = harness.make(usesCheckpointer: false)
        _ = try await repository.open { _ in }
        let limit = SQLiteLibraryRepository.checkpointHardLimitPages
        _ = try await Self.fill(repository, toPages: limit)
        try await repository.send(Self.strokes(Self.maxSaves))
        try await repository.saveNow()
        #expect(await repository.walPageCount < limit)
    }

    @Test("The saved rows stay after the checkpoints")
    func rowsStay() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        let saves = try await Self.fill(repository, toPages: 2_500)
        await repository.waitForCheckpoint()
        let reader = try harness.reader()
        let count = try reader.integer("SELECT count(*) FROM stroke")
        #expect(count == Int64(saves * Self.strokesPerSave))
    }

    @Test("An idle checkpointer gets the checkpoint also past the hard limit")
    func idleCheckpointerTakesTheHardLimit() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        // A read transaction pins the WAL, as a snapshot does, so the WAL passes the hard limit.
        let reader = try harness.reader()
        try reader.execute("BEGIN")
        _ = try reader.integer("SELECT count(*) FROM stroke")
        _ = try await Self.fill(
            repository,
            toPages: SQLiteLibraryRepository.checkpointHardLimitPages
        )
        try reader.execute("COMMIT")
        await repository.waitForCheckpoint()
        let before = await repository.writeConnectionCheckpoints
        try await repository.send(Self.strokes(Self.maxSaves))
        try await repository.saveNow()
        #expect(await repository.writeConnectionCheckpoints == before)
        await repository.waitForCheckpoint()
        try await repository.send(Self.strokes(Self.maxSaves + 1))
        try await repository.saveNow()
        #expect(await repository.walPageCount < SQLiteLibraryRepository.checkpointPages)
    }

    @Test("The write connection checkpoints past the hard limit while the checkpointer is busy")
    func busyCheckpointerLeavesTheHardLimitToTheWriter() async throws {
        let harness = try RepositoryHarness()
        let gate = DispatchSemaphore(value: 0)
        let repository = harness.make(beforeCheckpoint: { gate.wait() })
        _ = try await repository.open { _ in }
        defer { gate.signal() }
        let limit = SQLiteLibraryRepository.checkpointHardLimitPages
        _ = try await Self.fill(repository, toPages: limit)
        #expect(await repository.writeConnectionCheckpoints >= 1)
        try await repository.send(Self.strokes(Self.maxSaves))
        try await repository.saveNow()
        #expect(await repository.walPageCount < limit)
    }

    @Test("A save does not wait for a checkpoint that just started past the hard limit")
    func justStartedCheckpointDoesNotBlock() async throws {
        let harness = try RepositoryHarness()
        let isBlocked = OSAllocatedUnfairLock(initialState: false)
        let gate = DispatchSemaphore(value: 0)
        let repository = harness.make(beforeCheckpoint: {
            if isBlocked.withLock({ $0 }) { gate.wait() }
        })
        _ = try await repository.open { _ in }
        defer { gate.signal() }
        let reader = try harness.reader()
        try reader.execute("BEGIN")
        _ = try reader.integer("SELECT count(*) FROM stroke")
        _ = try await Self.fill(
            repository,
            toPages: SQLiteLibraryRepository.checkpointHardLimitPages
        )
        try reader.execute("COMMIT")
        await repository.waitForCheckpoint()
        isBlocked.withLock { $0 = true }
        // The first save starts a checkpoint that stays busy, as after the end of a snapshot.
        try await repository.send(Self.strokes(Self.maxSaves))
        try await repository.saveNow()
        let before = await repository.writeConnectionCheckpoints
        try await repository.send(Self.strokes(Self.maxSaves + 1))
        try await repository.saveNow()
        #expect(await repository.writeConnectionCheckpoints == before)
    }
}
