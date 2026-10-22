import Foundation
import Model
import Testing
import UIKit

@testable import CanvasFeature
@testable import Pointer

/// The preview render of a leave ends also when the render thread of the child stops before the
/// render ends, so that the leave does not wait for ever (m7-plan.md task 0.4, D-111, D-131).
@MainActor
@Suite("Preview render on a stopped thread")
struct PreviewStopTests {
    /// The longest wait for the completion of the preview render.
    private static let timeout = Duration.seconds(3)

    /// Waits until the preview of `leaving` is done, and returns `false` after `timeout`.
    private static func waitForPreview(of leaving: CardOpening) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !leaving.isPreviewDone {
            guard clock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    @Test("A preview render whose render thread stops calls its completion")
    func stoppedRenderThread() async throws {
        let tree = try await NavigationTests.makeTree(depth: 1)
        defer { tree.remove() }
        let composition = try NavigationTests.composition(for: tree)
        defer { composition.container.view.removeFromSuperview() }
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        try await NavigationTests.waitForCanvas(tree.workspace.canvasID, in: composition)
        let card = try #require(composition.container.canvas?.content.cards[tree.chain[0]])
        composition.openChild(card)
        try await NavigationTests.waitForCanvas(card.childCanvasID, in: composition)
        // The child stays alive in this scope on purpose: its renderer keeps the request.
        let child = try #require(composition.container.canvas)
        let path = try #require(composition.path)
        let leaving = CardOpening(target: path.popping())
        composition.renderPreview(of: child, for: card, in: leaving)
        // The view leaves the window before the next frame, so the render thread stops.
        child.view.removeFromSuperview()
        #expect(!leaving.isPreviewDone)
        let isDone = try await Self.waitForPreview(of: leaving)
        #expect(isDone, "The completion of the preview render did not run")
    }
}
