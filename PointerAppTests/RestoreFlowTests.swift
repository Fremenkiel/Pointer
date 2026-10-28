import Foundation
import Geometry
import Model
import Testing
import UIKit

@testable import BackupFeature
@testable import CanvasFeature
@testable import Persistence
@testable import Pointer

/// The restore flow and the new composition after it (tasks 2.2 and 2.3 of the M9 plan,
/// D-20, D-112, D-149, D-151, D-152, D-164).
@MainActor
@Suite("Restore flow", .serialized)
struct RestoreFlowTests {
    private static let day: UInt64 = 24 * 60 * 60 * 1000

    @Test(
        "The clock continues after the larger of the old clock and the restored clock (D-152)",
        arguments: [false, true]
    )
    func clock(isNewer: Bool) async throws {
        let harness = try await AppHarness.start()
        defer { await harness.remove() }
        let old = try #require(harness.composition.clock?.factory.clock.last)
        let wall = isNewer ? old.wallMillis + Self.day : old.wallMillis - Self.day
        let snapshot = try await harness.otherSnapshot(wallMillis: wall)
        let device = try #require(harness.composition.clock?.factory.clock.device)
        #expect(await harness.composition.restore(from: snapshot.url) == .restored)
        try await harness.waitForReplacement()
        let clock = try #require(harness.composition.clock?.factory.clock)
        let floor = isNewer ? snapshot.stamp : old
        #expect((clock.last.wallMillis, clock.last.counter) >= (floor.wallMillis, floor.counter))
        #expect(clock.device == device, "The clock keeps the device ID of this iPad")
        let next = harness.composition.clock?.now()
        #expect(
            next.map { ($0.wallMillis, $0.counter) > (floor.wallMillis, floor.counter) } == true
        )
    }

    @Test("A restore opens the first workspace if the last one is not in the snapshot (D-151)")
    func firstWorkspace() async throws {
        let harness = try await AppHarness.start()
        defer { await harness.remove() }
        let before = try #require(harness.composition.selector?.current?.id)
        let snapshot = try await harness.otherSnapshot(wallMillis: Self.now())
        #expect(await harness.composition.restore(from: snapshot.url) == .restored)
        try await harness.waitForReplacement()
        #expect(harness.composition.selector?.workspaces.map(\.id) == [snapshot.workspace.id])
        #expect(harness.composition.selector?.current?.id == snapshot.workspace.id)
        #expect(before != snapshot.workspace.id)
        #expect(harness.replacements == 1)
    }

    @Test("A restore cuts the stored path at the first card that is not valid (D-112)")
    func cutPath() async throws {
        let harness = try await AppHarness.start()
        defer { await harness.remove() }
        let snapshot = try await harness.otherSnapshot(wallMillis: Self.now())
        try await harness.composition.deviceStore?.save(
            lastWorkspace: snapshot.workspace.id,
            navigationPath: [snapshot.card.id, CardID(rawValue: UUID())]
        )
        #expect(await harness.composition.restore(from: snapshot.url) == .restored)
        try await harness.waitForReplacement()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: AppHarness.timeout)
        while harness.composition.container.canvas?.canvasID != snapshot.card.childCanvasID {
            guard clock.now < deadline else { throw OpenTimedOut() }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(harness.composition.path?.cards == [snapshot.card.id])
    }

    @Test("If the restored library does not open, the pre-restore snapshot comes back (D-20)")
    func wayBack() async throws {
        let harness = try await AppHarness.start()
        defer { await harness.remove() }
        let before = try #require(harness.composition.selector?.workspaces.map(\.id))
        let snapshot = try await harness.otherSnapshot(wallMillis: Self.now())
        // A damaged clock row passes the checks of a picked file, and the open refuses it.
        let damaged = harness.folder.appending(path: "damaged.sqlite")
        // swiftlint:disable:next arch_04_file_system
        try FileManager().copyItem(at: snapshot.url, to: damaged)
        let writer = try SQLiteConnection(
            path: damaged.path(percentEncoded: false),
            mode: .readWrite
        )
        try writer.execute("UPDATE library SET value = 'damaged' WHERE key = 'lastTimestamp'")
        _ = try writer.text("PRAGMA journal_mode = DELETE")
        #expect(await harness.composition.restore(from: damaged) == .restored)
        try await harness.waitForReplacement()
        try await harness.waitForReplacement()
        #expect(harness.replacements == 2)
        #expect(harness.composition.selector?.workspaces.map(\.id) == before)
        #expect(harness.message == BackupMessage.restoreUndone.text)
    }

    @Test("The flow saves a text edit and a pending card into the pre-restore snapshot (D-149)")
    func busyScreen() async throws {
        let harness = try await AppHarness.start()
        defer { await harness.remove() }
        let canvas = try #require(harness.composition.container.canvas)
        canvas.showPendingCard()
        let pending = try #require(canvas.cardInteraction.pendingCard)
        canvas.startNewTextBox(at: Point(x: 400, y: 300))
        canvas.textEditing.view.text = "saved before the restore"
        let snapshot = try await harness.otherSnapshot(wallMillis: Self.now())
        #expect(await harness.composition.restore(from: snapshot.url) == .restored)
        try await harness.waitForReplacement()
        // swiftlint:disable:next arch_04_file_system
        let names = try FileManager().contentsOfDirectory(atPath: harness.files.backups.path)
        let name = try #require(names.first(where: SnapshotFiles.isPreRestore))
        let saved = try SQLiteConnection(
            path: harness.files.backups.appending(path: name).path(percentEncoded: false),
            mode: .readOnly
        )
        #expect(try saved.integer("SELECT count(*) FROM text_box") == 1)
        #expect(try saved.integer("SELECT count(*) FROM card") == 1, "Card \(pending.id)")
        #expect(harness.background.begun == 1 && harness.background.ended == 1)
    }

    @Test("A refused file leaves the library and the screen as they were")
    func refusedFile() async throws {
        let harness = try await AppHarness.start()
        defer { await harness.remove() }
        let picked = harness.folder.appending(path: "notes.sqlite")
        try Data("not a database at all, only text".utf8).write(to: picked)
        let canvas = try #require(harness.composition.container.canvas)
        #expect(await harness.composition.restore(from: picked) == .refused(.notALibrary))
        #expect(harness.replacements == 0)
        #expect(harness.composition.container.canvas === canvas)
        #expect(canvas.isEditingEnabled)
        #expect(harness.message == BackupMessage.notALibrary.text)
        #expect(harness.background.begun == 0)
    }

    @Test("At the end of the extra time, the restore stops and the old library opens (D-164)")
    func stopAtExpiry() async throws {
        let harness = try await AppHarness.start()
        defer { await harness.remove() }
        let before = try #require(harness.composition.selector?.workspaces.map(\.id))
        let snapshot = try await harness.otherSnapshot(wallMillis: Self.now())
        harness.background.expiresAtOnce = true
        #expect(
            await harness.composition.restore(from: snapshot.url) == .stopped(.restoreStopped)
        )
        try await harness.waitForReplacement()
        #expect(harness.composition.selector?.workspaces.map(\.id) == before)
        #expect(harness.message == BackupMessage.restoreStopped.text)
        #expect(harness.background.ended == 1)
    }

    private static func now() -> UInt64 { SystemWallClock().nowMillis() }
}
