import Foundation
import Model
import Testing

@testable import Persistence
@testable import Pointer

/// The launch removes the preview files of the canvases that the 30-day purge removes (D-18,
/// m10-plan.md task 2.9). Before the fix, the files stayed on the disk without an owner.
@MainActor
@Suite("Previews of purged canvases")
struct PurgedPreviewTests {
    private static let day: UInt64 = 24 * 60 * 60 * 1000

    /// The canvases of a deleted workspace and its card.
    private struct Deleted {
        let workspace: CanvasID
        let card: CanvasID
    }

    /// Writes a workspace with one card, deleted at `millis`, and a preview file for each canvas.
    private static func deleted(at millis: UInt64, files: AppFiles) async throws -> Deleted {
        let device = DeviceID(rawValue: UUID())
        let wallClock = StoppedWallClock(millis: millis)
        let repository = SQLiteLibraryRepository(
            configuration: SQLiteLibraryRepository.Configuration(
                databasePath: files.library,
                temporaryFolder: files.temporary,
                device: device,
                wallClock: wallClock,
                timer: ContinuousSaveTimer()
            )
        ) { _ in }
        _ = try await repository.open { _ in }
        let stamp = HybridTimestamp(wallMillis: millis, counter: 1, device: device)
        let workspace = try Workspace(
            id: WorkspaceID(rawValue: UUID()),
            meta: RecordMeta(created: stamp),
            title: "Old",
            sortKey: FractionalIndex(rawValue: "V")
        )
        try await repository.create(workspace)
        let card = try Card(
            id: CardID(rawValue: UUID()),
            meta: RecordMeta(created: stamp),
            canvasID: workspace.canvasID,
            frame: NavigationTests.frame,
            title: "Card",
            sortKey: FractionalIndex(rawValue: "V")
        )
        try await repository.send([.card(card)])
        let later = HybridTimestamp(wallMillis: millis, counter: 2, device: device)
        try await repository.delete(workspace.id, modified: later)
        try await repository.saveNow()
        await repository.close()
        let store = PreviewStore(folder: files.previews)
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        try await store.write(png, for: workspace.canvasID)
        try await store.write(png, for: CanvasID(card.id))
        return Deleted(workspace: workspace.canvasID, card: CanvasID(card.id))
    }

    @Test("The launch removes the previews of the purged canvases and keeps the others")
    func removesPurged() async throws {
        let now = UInt64(Date().timeIntervalSince1970 * 1000)
        var old: Deleted?
        var recent: Deleted?
        let harness = try await AppHarness.start { files in
            // The recent one comes first, because each open purges at the time of its clock.
            recent = try await Self.deleted(at: now - Self.day, files: files)
            old = try await Self.deleted(at: now - 40 * Self.day, files: files)
        }
        defer { await harness.remove() }
        let purged = try #require(old)
        let kept = try #require(recent)
        let store = PreviewStore(folder: harness.files.previews)
        #expect(await store.read(purged.workspace) == nil, "The purged workspace has no preview")
        #expect(await store.read(purged.card) == nil, "The purged card has no preview")
        #expect(await store.read(kept.workspace) != nil, "A recent tombstone keeps its preview")
        #expect(await store.read(kept.card) != nil, "A recent tombstone keeps its card preview")
    }
}
