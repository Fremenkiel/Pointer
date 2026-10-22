import Foundation
import Geometry
import Model
import Persistence
import Testing
import UIKit

@testable import CanvasFeature
@testable import Pointer

/// Acceptance 2 of M6: a tree of 32 levels (m6-plan.md task 5.2, CARD-09, D-95).
@MainActor
@Suite("Tree of 32 levels")
struct DeepTreeTests {
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

    /// Waits until the shown canvas ends its card flight.
    private static func waitForFlight(in composition: AppComposition) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: NavigationTests.timeout)
        while composition.container.canvas?.isInCardTransition ?? true {
            guard clock.now < deadline else { throw OpenTimedOut() }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Opens each level from the root, draws at each, is refused at 32, and leaves to the root")
    func openAndLeave() async throws {
        let tree = try await NavigationTests.makeTree(depth: Limits.maxDepth)
        defer { tree.remove() }
        let composition = try NavigationTests.composition(for: tree)
        defer { composition.container.view.removeFromSuperview() }
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        try await NavigationTests.waitForCanvas(tree.workspace.canvasID, in: composition)
        for card in tree.chain {
            let canvas = try #require(composition.container.canvas)
            canvas.addPenStrokes([Self.stroke(on: canvas.canvasID, clock: tree.clock)])
            composition.openChild(try #require(canvas.content.cards[card]))
            try await NavigationTests.waitForCanvas(CanvasID(card), in: composition)
        }
        let deepest = try #require(composition.container.canvas)
        #expect(deepest.level == Limits.maxDepth)
        #expect(composition.path?.level == Limits.maxDepth)
        deepest.addPenStrokes([Self.stroke(on: deepest.canvasID, clock: tree.clock)])
        deepest.showPendingCard()
        #expect(deepest.textEditing.pendingCard == nil, "No card at level 32 (D-95)")
        let alert = composition.container.presentedViewController as? UIAlertController
        #expect(alert?.message == CanvasStrings.depthLimit)
        alert?.dismiss(animated: false)
        for level in (0..<Limits.maxDepth).reversed() {
            composition.leave()
            let canvas = level == 0 ? tree.workspace.canvasID : CanvasID(tree.chain[level - 1])
            try await NavigationTests.waitForCanvas(canvas, in: composition)
            // The app refuses a leave during the flight of the last leave.
            try await Self.waitForFlight(in: composition)
        }
        #expect(composition.path?.level == 0)
        try await tree.repository.saveNow()
        var canvases = [tree.workspace.canvasID]
        canvases += tree.chain.map { CanvasID($0) }
        for canvas in canvases {
            let content = try await tree.repository.content(of: canvas)
            #expect(content.strokes.count == 1, "One stroke on \(canvas)")
        }
    }

    @Test("A launch with the path of 32 cards opens level 32")
    func launch() async throws {
        let tree = try await NavigationTests.makeTree(depth: Limits.maxDepth)
        defer { tree.remove() }
        let composition = try NavigationTests.composition(for: tree)
        defer { composition.container.view.removeFromSuperview() }
        composition.launchPath = try NavigationPath(workspace: tree.workspace.id, cards: tree.chain)
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        let last = try #require(tree.chain.last)
        try await NavigationTests.waitForCanvas(CanvasID(last), in: composition)
        #expect(composition.container.canvas?.level == Limits.maxDepth)
        #expect(composition.path?.cards == tree.chain)
        #expect(composition.container.upButton != nil)
    }
}
