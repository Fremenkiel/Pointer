import Foundation
import Geometry
import Model
import Testing
import UIKit

@testable import CanvasFeature
@testable import Pointer

/// An open or a leave that fails ends with the shown screen in a good state: it keeps its undo
/// history, a message shows, and the next open runs (m7-plan.md tasks 0.2 and 0.3, D-131,
/// UNDO-01, F-02, WS-02, CARD-04).
@MainActor
@Suite("Failed card opens", .serialized)
struct NavigationFailureTests {
    /// The longest wait for a failed open: the first frame of the child times out after 5 s.
    private static let failTimeout = Duration.seconds(15)

    /// One short stroke on `canvas`.
    private static func stroke(on canvas: CanvasID, clock: AppClock) -> Stroke {
        let points = InkPoints(
            (0..<20).map { InkPoint(x: Float($0) * 4, y: Float($0 % 3), force: 0.5, time: 0) }
        )
        return Stroke(
            id: StrokeID(rawValue: UUID()),
            canvasID: canvas,
            created: clock.now(),
            origin: Point(x: -40, y: 0),
            width: 2,
            points: points
        )
    }

    /// Waits until no open or leave runs, and returns `false` if one still runs after
    /// `failTimeout`.
    private static func endsOpening(in composition: AppComposition) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: failTimeout)
        while composition.opening != nil {
            guard clock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    /// Returns the message that the container shows, and closes it.
    private static func takeMessage(of composition: AppComposition) -> String? {
        let alert = composition.container.presentedViewController as? UIAlertController
        alert?.dismiss(animated: false)
        return alert?.message
    }

    /// Opens the card of a tree of depth 1 while the app has no window, so that the child with
    /// its stroke never draws and the open fails after `makeCanvas`. Then draws one stroke on
    /// the parent. The parent is a local of this function, so the caller holds no reference to
    /// it.
    private static func failOpenAndDraw(
        _ tree: NavigationTests.Tree,
        in composition: AppComposition
    ) async throws {
        let parent = try #require(composition.container.canvas)
        let card = try #require(parent.content.cards[tree.chain[0]])
        let host = try #require(composition.container.view.superview)
        composition.container.view.removeFromSuperview()
        composition.openChild(card)
        #expect(composition.opening != nil)
        let hasEnded = try await endsOpening(in: composition)
        try #require(hasEnded, "The failed open still runs")
        host.addSubview(composition.container.view)
        try await NavigationTests.waitForCanvas(tree.workspace.canvasID, in: composition)
        #expect(composition.container.canvas === parent)
        #expect(!parent.isInCardTransition)
        parent.addPenStrokes([stroke(on: parent.canvasID, clock: tree.clock)])
        #expect(parent.history.undoSteps.count == 1)
    }

    @Test("A failed open keeps the session of the parent across a workspace switch (D-131)")
    func failedOpenKeepsSession() async throws {
        let tree = try await NavigationTests.makeTree(depth: 1)
        defer { await tree.remove() }
        let other = try Workspace(
            id: tree.clock.makeIdentifier(),
            meta: RecordMeta(created: tree.clock.now()),
            title: "Other",
            sortKey: FractionalIndex(rawValue: "W")
        )
        try await tree.repository.create(other)
        // Without a stroke, the open of the empty child did not fail without a window.
        let child = CanvasID(tree.chain[0])
        try await tree.repository.send([.stroke(Self.stroke(on: child, clock: tree.clock))])
        try await tree.repository.saveNow()
        let composition = try NavigationTests.composition(for: tree)
        defer { composition.container.view.removeFromSuperview() }
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        try await NavigationTests.waitForCanvas(tree.workspace.canvasID, in: composition)
        try await Self.failOpenAndDraw(tree, in: composition)
        composition.selector?.select(other.id)
        try await NavigationTests.waitForCanvas(other.canvasID, in: composition)
        composition.selector?.select(tree.workspace.id)
        try await NavigationTests.waitForCanvas(tree.workspace.canvasID, in: composition)
        let shown = try #require(composition.container.canvas)
        #expect(shown.content.strokes.count == 1)
        #expect(shown.history.undoSteps.count == 1, "The stroke after the failed open")
        shown.undo()
        #expect(shown.content.strokes.isEmpty)
    }

    @Test("A leave whose parent has no card of the child ends with a message (D-131)")
    func leaveWithoutParentCard() async throws {
        let tree = try await NavigationTests.makeTree(depth: 2)
        defer { await tree.remove() }
        let composition = try NavigationTests.composition(for: tree)
        defer { composition.container.view.removeFromSuperview() }
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        try await NavigationTests.waitForCanvas(tree.workspace.canvasID, in: composition)
        let card = try #require(composition.container.canvas?.content.cards[tree.chain[0]])
        composition.openChild(card)
        try await NavigationTests.waitForCanvas(CanvasID(tree.chain[0]), in: composition)
        let deleted = try Card(
            id: card.id,
            meta: card.meta.changed(at: tree.clock.now(), isDeleted: true),
            canvasID: card.canvasID,
            frame: card.frame,
            title: card.title,
            sortKey: card.sortKey
        )
        try await tree.repository.send([.card(deleted)])
        try await tree.repository.saveNow()
        composition.leave()
        #expect(composition.opening != nil)
        let hasEnded = try await Self.endsOpening(in: composition)
        try #require(hasEnded, "The failed navigation still runs")
        try await NavigationTests.waitForCanvas(CanvasID(tree.chain[0]), in: composition)
        #expect(Self.takeMessage(of: composition) == AppStrings.canvasFailed)
        let next = try #require(composition.container.canvas?.content.cards[tree.chain[1]])
        composition.openChild(next)
        try await NavigationTests.waitForCanvas(CanvasID(tree.chain[1]), in: composition)
    }

    @Test("An open whose screen is not made ends with a message (D-131)")
    func openWithoutScreen() async throws {
        let tree = try await NavigationTests.makeTree(depth: 1)
        defer { await tree.remove() }
        let composition = try NavigationTests.composition(for: tree)
        defer { composition.container.view.removeFromSuperview() }
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        try await NavigationTests.waitForCanvas(tree.workspace.canvasID, in: composition)
        let card = try #require(composition.container.canvas?.content.cards[tree.chain[0]])
        // Without a clock, `makeCanvas` gives `nil`.
        composition.clock = nil
        composition.openChild(card)
        #expect(composition.opening != nil)
        let hasEnded = try await Self.endsOpening(in: composition)
        try #require(hasEnded, "The failed navigation still runs")
        try await NavigationTests.waitForCanvas(tree.workspace.canvasID, in: composition)
        #expect(Self.takeMessage(of: composition) == AppStrings.canvasFailed)
        composition.clock = tree.clock
        let again = try #require(composition.container.canvas?.content.cards[tree.chain[0]])
        composition.openChild(again)
        try await NavigationTests.waitForCanvas(CanvasID(tree.chain[0]), in: composition)
    }
}
