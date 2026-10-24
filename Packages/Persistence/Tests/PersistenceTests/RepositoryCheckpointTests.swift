import Foundation
import Geometry
import Model
import Testing

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
}
