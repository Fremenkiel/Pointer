import Foundation
import Model
import Testing

@testable import CanvasFeature
@testable import Pointer

/// The guards of a pinch-out leave (review of 2026-10-28, 3.2.15).
@MainActor
@Suite("Pinch-out leave on a busy library", .serialized)
struct PinchLeaveBusyTests {
    private final class Loads {
        var canvases: [CanvasID] = []
    }

    @Test("A pinch leave during a restore starts no load")
    func pinchDuringRestore() async throws {
        let tree = try await NavigationTests.makeTree(depth: 1)
        let composition = try NavigationTests.composition(for: tree)
        defer {
            composition.container.view.removeFromSuperview()
            await tree.remove()
        }
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        try await NavigationTests.waitForCanvas(tree.workspace.canvasID, in: composition)
        let card = try #require(composition.container.canvas?.content.cards[tree.chain[0]])
        composition.openChild(card)
        try await NavigationTests.waitForCanvas(CanvasID(tree.chain[0]), in: composition)
        let loads = Loads()
        composition.onLoadStarted = { [loads] in loads.canvases.append($0) }
        composition.isLibraryBusy = true
        composition.leaveByPinch()
        #expect(composition.opening == nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(loads.canvases.isEmpty, "No load of the parent started")
        composition.isLibraryBusy = false
    }
}
