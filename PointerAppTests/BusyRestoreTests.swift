import Foundation
import Geometry
import Model
import Testing

@testable import CanvasFeature
@testable import Pointer

/// A restore while a child canvas is open, a card flies, and a text edit runs (task 4.2 of
/// the M9 plan, D-148, D-150).
@MainActor
@Suite("Restore with a busy screen", .serialized)
struct BusyRestoreTests {
    @Test("A restore during a card flight and a text edit in a child shows the restored library")
    func busyScreen() async throws {
        let harness = try await AppHarness.start()
        defer { await harness.remove() }
        let root = try #require(harness.composition.container.canvas)
        root.showPendingCard()
        let card = try #require(root.textEditing.pendingCard)
        root.placePendingCard()
        harness.composition.openChild(try #require(root.content.cards[card.id]))
        try await NavigationTests.waitForCanvas(CanvasID(card.id), in: harness.composition)
        let child = try #require(harness.composition.container.canvas)
        child.startNewTextBox(at: Point(x: 10, y: 10))
        child.textEditing.view.text = "in the middle of an edit"
        // A second card in the child, and its open starts the flight that the restore meets.
        child.showPendingCard()
        let inner = try #require(child.textEditing.pendingCard)
        child.placePendingCard()
        harness.composition.openChild(try #require(child.content.cards[inner.id]))
        let snapshot = try await harness.otherSnapshot(wallMillis: SystemWallClock().nowMillis())
        #expect(await harness.composition.restore(from: snapshot.url) == .restored)
        try await harness.waitForReplacement()
        let shown = try #require(harness.composition.container.canvas)
        #expect(shown.canvasID == snapshot.workspace.canvasID)
        #expect(shown.content.cards[snapshot.card.id] != nil)
        #expect(harness.composition.path?.level == 0)
        #expect(harness.composition.sessions.count == 0)
    }
}
