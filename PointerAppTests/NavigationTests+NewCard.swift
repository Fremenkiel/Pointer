import Foundation
import Geometry
import Model
import Testing

@testable import CanvasFeature
@testable import Pointer

/// A card that the card button makes inside a child canvas stays after a leave and a new open
/// (CARD-01, D-117, D-123).
extension NavigationTests {
    /// Opens the card of a tree of depth 1 and returns the shown child.
    private static func openChild(
        of tree: Tree,
        in composition: AppComposition
    ) async throws -> CanvasViewController {
        let card = try #require(composition.container.canvas?.content.cards[tree.chain[0]])
        composition.openChild(card)
        try await waitForCanvas(CanvasID(tree.chain[0]), in: composition)
        return try #require(composition.container.canvas)
    }

    /// Leaves the child and waits for the end of the flight of the parent.
    private static func leave(_ tree: Tree, in composition: AppComposition) async throws {
        composition.leave()
        try await waitForCanvas(tree.workspace.canvasID, in: composition)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while composition.container.canvas?.isInCardTransition == true {
            guard clock.now < deadline else { throw OpenTimedOut() }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("A card of the card button, dragged into place in a child, stays after a leave")
    func newCardInChild() async throws {
        let tree = try await Self.makeTree(depth: 1)
        defer { await tree.remove() }
        let composition = try Self.composition(for: tree)
        defer { composition.container.view.removeFromSuperview() }
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        try await Self.waitForCanvas(tree.workspace.canvasID, in: composition)
        let child = try await Self.openChild(of: tree, in: composition)
        child.showPendingCard()
        let pending = try #require(child.textEditing.pendingCard)
        let start = pending.frame.center
        #expect(child.beginPendingDrag(at: start))
        child.continuePendingDrag(to: Point(x: start.x + 200, y: start.y))
        child.endPendingDrag(isPlaced: true)
        #expect(child.content.cards[pending.id] != nil)
        try await Self.leave(tree, in: composition)
        let again = try await Self.openChild(of: tree, in: composition)
        #expect(again.content.cards[pending.id] != nil)
    }

    @Test("A pending card of the card button joins the child at a leave (D-123)")
    func pendingCardAtLeave() async throws {
        let tree = try await Self.makeTree(depth: 1)
        defer { await tree.remove() }
        let composition = try Self.composition(for: tree)
        defer { composition.container.view.removeFromSuperview() }
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        try await Self.waitForCanvas(tree.workspace.canvasID, in: composition)
        let child = try await Self.openChild(of: tree, in: composition)
        child.showPendingCard()
        let pending = try #require(child.textEditing.pendingCard)
        try await Self.leave(tree, in: composition)
        let again = try await Self.openChild(of: tree, in: composition)
        let card = try #require(again.content.cards[pending.id])
        #expect(card.frame == pending.frame)
        #expect(again.history.undoSteps.count == 1)
    }
}
