import Foundation
import Model
import Testing
import UIKit

@testable import CanvasFeature
@testable import Pointer

/// A double tap and a squeeze do nothing during a card flight, on both screens, and act on the
/// shown screen after it (m7-plan.md task 1.3, architecture.md 4.5, CARD-03, D-63, D-130).
@MainActor
@Suite("Pencil actions during a card flight", .serialized)
struct PencilFlightTests {
    /// A point of the canvas where a squeeze opens the palette.
    private static let tip = CGPoint(x: 100, y: 100)

    @Test("A double tap and a squeeze change nothing on both screens during the open of a card")
    func duringOpen() async throws {
        let tree = try await NavigationTests.makeTree(depth: 1)
        defer { await tree.remove() }
        let composition = try NavigationTests.composition(for: tree)
        defer { composition.container.view.removeFromSuperview() }
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        try await NavigationTests.waitForCanvas(tree.workspace.canvasID, in: composition)
        try await Self.actDuringOpen(tree, in: composition)
        try await NavigationTests.waitForCanvas(CanvasID(tree.chain[0]), in: composition)
        Self.actOnShownCanvas(in: composition)
    }

    /// Opens the card and, while the parent flies and the child waits above it, double-taps and
    /// squeezes on both screens. The screens are locals of this function, so the caller holds no
    /// reference to them.
    private static func actDuringOpen(
        _ tree: NavigationTests.Tree,
        in composition: AppComposition
    ) async throws {
        let parent = try #require(composition.container.canvas)
        let card = try #require(parent.content.cards[tree.chain[0]])
        composition.openChild(card)
        let child = try await waitForChild(in: composition)
        defer { composition.container.presentedViewController?.dismiss(animated: false) }
        try #require(parent.isInCardTransition, "The flight ended before the child joined")
        for screen in [parent, child] {
            screen.doubleTap(action: .switchEraser)
            screen.squeeze(isEnded: true, action: .showContextualPalette, hoverLocation: tip)
            #expect(screen.tool == .pen)
            #expect(screen.toolControls.selected == .pen)
        }
        #expect(composition.container.presentedViewController == nil, "The palette opened")
        #expect(parent.isShownCanvas)
        #expect(!child.isShownCanvas)
    }

    /// After the open, the shown child takes a double tap and a squeeze.
    private static func actOnShownCanvas(in composition: AppComposition) {
        guard let child = composition.container.canvas else {
            Issue.record("No shown canvas after the open")
            return
        }
        #expect(child.isShownCanvas)
        child.doubleTap(action: .switchEraser)
        #expect(child.tool == .eraser)
        child.squeeze(isEnded: true, action: .showContextualPalette, hoverLocation: tip)
        #expect(composition.container.presentedViewController != nil, "The palette did not open")
        composition.container.presentedViewController?.dismiss(animated: false)
    }

    /// Waits until the open added the child screen above the parent, and returns it.
    private static func waitForChild(
        in composition: AppComposition
    ) async throws -> CanvasViewController {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: NavigationTests.timeout)
        while composition.opening?.added == nil {
            guard clock.now < deadline else { throw OpenTimedOut() }
            try await Task.sleep(for: .milliseconds(1))
        }
        return try #require(composition.opening?.added)
    }
}
