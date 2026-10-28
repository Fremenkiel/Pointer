import Foundation
import Model
import XCTest

@testable import CanvasFeature
@testable import Persistence
@testable import Pointer
@testable import Rendering

/// The close of a composition before a restore (task 2.1 of the M9 plan, D-150, D-157).
@MainActor
final class CompositionCloseTests: XCTestCase {
    /// The longest wait for the screens to go away after the close.
    private static let releaseTimeout = Duration.seconds(5)

    /// Weak references to the parts that the close must let go.
    @MainActor
    private struct Watched {
        weak var composition: AppComposition?
        weak var canvas: CanvasViewController?
        weak var renderer: CanvasRenderer?
        weak var engine: RenderEngine?

        var alive: [String] {
            [
                composition.map { _ in "composition" }, canvas.map { _ in "canvas" },
                renderer.map { _ in "renderer" }, engine.map { _ in "engine" },
            ].compactMap { $0 }
        }
    }

    func testCloseDuringAnOpenWithAPendingCardLetsTheScreensGo() async throws {
        let tree = try await NavigationTests.makeTree(depth: 1)
        defer { await tree.remove() }
        let watched = try await Self.closeDuringOpen(of: tree)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.releaseTimeout)
        while !watched.alive.isEmpty, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(watched.alive, [], "Alive after the close: \(watched.alive)")
        // The pending card joined the canvas, and the close saved it (D-149).
        let reader = try SQLiteConnection(
            path: tree.folder.appending(path: "library.sqlite").path(percentEncoded: false),
            mode: .readOnly
        )
        let cards = try reader.integer("SELECT count(*) FROM card")
        XCTAssertEqual(cards, 2, "The chain card and the pending card")
    }

    /// Starts an open with a pending card on the parent and closes the composition at once.
    /// The composition and the screens are locals of this function.
    private static func closeDuringOpen(of tree: NavigationTests.Tree) async throws -> Watched {
        let composition = try NavigationTests.composition(for: tree)
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        try await NavigationTests.waitForCanvas(tree.workspace.canvasID, in: composition)
        let parent = try XCTUnwrap(composition.container.canvas)
        parent.showPendingCard()
        XCTAssertNotNil(parent.textEditing.pendingCard)
        let watched = Watched(
            composition: composition,
            canvas: parent,
            renderer: parent.renderer,
            engine: parent.renderer.engine
        )
        composition.openChild(try XCTUnwrap(parent.content.cards[tree.chain[0]]))
        XCTAssertNotNil(composition.opening, "The open runs")
        try await composition.close()
        XCTAssertNil(composition.container.canvas)
        XCTAssertNil(composition.opening)
        XCTAssertEqual(composition.sessions.count, 0)
        XCTAssertNil(composition.path)
        composition.container.view.removeFromSuperview()
        return watched
    }
}
