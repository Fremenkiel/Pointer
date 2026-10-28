import Foundation
import Model
import Testing

@testable import CanvasFeature
@testable import Pointer

/// The edit state of a canvas that an open adds while the state of the app changes (review of
/// 2026-10-28).
extension NavigationTests {
    @Test("A save failure during the open of a card reaches the child (review of 2026-10-28)")
    func saveFailureDuringOpen() async throws {
        let tree = try await Self.makeTree(depth: 1)
        defer { await tree.remove() }
        let composition = try Self.composition(for: tree)
        defer { composition.container.view.removeFromSuperview() }
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        try await Self.waitForCanvas(tree.workspace.canvasID, in: composition)
        let card = try #require(composition.container.canvas?.content.cards[tree.chain[0]])
        composition.openChild(card)
        // The child exists before the flight ends, and the third failed save lands then.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.timeout)
        while composition.opening?.canvas == nil, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(composition.opening?.canvas != nil)
        composition.handle(.savesFailing(count: 3, reason: "test"))
        try await Self.waitForCanvas(CanvasID(tree.chain[0]), in: composition)
        #expect(composition.container.canvas?.isEditingEnabled == false)
        composition.handle(.savesRecovered)
        #expect(composition.container.canvas?.isEditingEnabled == true)
    }
}
