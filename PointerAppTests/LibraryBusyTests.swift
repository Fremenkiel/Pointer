import Foundation
import Model
import Testing
import UIKit

@testable import BackupFeature
@testable import CanvasFeature
@testable import Persistence
@testable import Pointer
@testable import Rendering

/// The busy state of a restore and of "Back up now", and the lifetimes around a restore that the
/// review after M9 found (D-169).
@MainActor
@Suite("Library busy state", .serialized)
struct LibraryBusyTests {
    /// The longest wait for the old composition to go away after a restore.
    private static let releaseTimeout = Duration.seconds(5)

    @Test("During \"Back up now\", the screen takes no input and the canvas no edit (D-169)")
    func backUpBlocksInput() async throws {
        let harness = try await AppHarness.start()
        defer { await harness.remove() }
        let composition = harness.composition
        let canvas = try #require(composition.container.canvas)
        let task = Task { await composition.backUpNow() }
        for _ in 0..<1_000 where !composition.isLibraryBusy {
            await Task.yield()
        }
        #expect(composition.isLibraryBusy)
        #expect(!composition.container.view.isUserInteractionEnabled)
        #expect(!canvas.isEditingEnabled)
        #expect(await composition.restore(from: harness.folder) == .ignored)
        #expect(await composition.backUpNow() == nil, "A second back-up does nothing")
        _ = try #require(await task.value).get()
        #expect(!composition.isLibraryBusy)
        #expect(composition.container.view.isUserInteractionEnabled)
        #expect(canvas.isEditingEnabled)
    }

    @Test("A second restore during a restore does nothing (D-169)")
    func secondRestoreIgnored() async throws {
        let harness = try await AppHarness.start()
        defer { await harness.remove() }
        let composition = harness.composition
        let snapshot = try await harness.otherSnapshot(wallMillis: SystemWallClock().nowMillis())
        async let first = composition.restore(from: snapshot.url)
        async let second = composition.restore(from: snapshot.url)
        let outcomes = await [first, second]
        #expect(outcomes.filter { $0 == .restored }.count == 1)
        #expect(outcomes.filter { $0 == .ignored }.count == 1)
        try await harness.waitForReplacement()
        #expect(harness.replacements == 1)
    }

    @Test("After a restore, the old composition and its screens go away (review after M9)")
    func oldCompositionGoes() async throws {
        let harness = try await AppHarness.start()
        defer { await harness.remove() }
        let watched = try await Self.restoreWithMessage(in: harness)
        try await harness.waitForReplacement()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.releaseTimeout)
        while !watched.alive.isEmpty, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(watched.alive == [], "Alive after the restore: \(watched.alive)")
    }

    @Test("A closed composition starts no idle timer (review after M9)")
    func closedCompositionStartsNoTimer() async throws {
        let harness = try await AppHarness.start()
        defer { await harness.remove() }
        await harness.composition.closeScreens()
        harness.composition.startIdleTimer()
        #expect(harness.composition.idleTimer == nil)
    }

    @Test("The share sheet shows above a popover, and its close lets the snapshots run")
    func shareAbovePopover() async throws {
        let harness = try await AppHarness.start()
        defer { await harness.remove() }
        let popover = UIViewController()
        harness.composition.container.present(popover, animated: false)
        let url = try #require(await harness.composition.backUpNow()).get()
        harness.composition.share(url, at: CGRect(x: 20, y: 20, width: 44, height: 44))
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: AppHarness.timeout)
        while !harness.composition.isSharing, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(harness.presented is UIActivityViewController)
        #expect(harness.composition.isSharing)
        #expect(popover.presentedViewController is UIActivityViewController)
    }

    @Test("Each final save ends its own extra time, also when one ends late (review 3.2.3)")
    func eachSaveEndsItsOwnTime() async throws {
        let harness = try await AppHarness.start()
        defer { await harness.remove() }
        harness.composition.enterBackground()
        harness.composition.enterBackground()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: AppHarness.timeout)
        while harness.background.ended < 2, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(harness.background.begun == 2)
        #expect(harness.background.endedTasks.count == 2)
        #expect(Set(harness.background.endedTasks).count == 2, "No task ends twice")
    }

    @Test("The end of the extra time ends the grant inside its handler (review after M9)")
    func expiryEndsTheGrant() {
        let time = FakeBackgroundTime()
        var hasExpired = false
        let grant = ExtraTime("Test", time: time) { hasExpired = true }
        time.expireAll()
        #expect(hasExpired)
        #expect(time.ended == 1, "The handler ends the task before it returns")
        grant.end()
        #expect(time.ended == 1, "A second end does nothing")
    }

    /// Weak references to the old composition and its screens.
    @MainActor
    private struct Watched {
        weak var composition: AppComposition?
        weak var container: AppViewController?
        weak var canvas: CanvasViewController?
        weak var renderer: CanvasRenderer?

        var alive: [String] {
            [
                composition.map { _ in "composition" }, container.map { _ in "container" },
                canvas.map { _ in "canvas" }, renderer.map { _ in "renderer" },
            ].compactMap { $0 }
        }
    }

    /// Shows a message on the old composition and restores a snapshot of another iPad. The old
    /// composition is a local of this function.
    private static func restoreWithMessage(in harness: AppHarness) async throws -> Watched {
        let composition = harness.composition
        let canvas = try #require(composition.container.canvas)
        let watched = Watched(
            composition: composition,
            container: composition.container,
            canvas: canvas,
            renderer: canvas.renderer
        )
        let snapshot = try await harness.otherSnapshot(wallMillis: SystemWallClock().nowMillis())
        // A message that shows during the restore must not keep the old screen.
        composition.container.showMessage("A message of the old composition")
        #expect(await composition.restore(from: snapshot.url) == .restored)
        return watched
    }
}
