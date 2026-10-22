import Foundation
import Model
import Testing
import UIKit

@testable import CanvasFeature
@testable import Pointer

/// A workspace switch during the open of a card cancels the open: no screen of the open stays in
/// the container, and the next open runs (architecture.md 6.2, WS-02, CARD-03).
@MainActor
@Suite("Cancelled card opens", .serialized)
struct NavigationCancelTests {
    /// The moment of the switch in the open.
    enum Moment: String, CaseIterable, Sendable {
        /// At once, while the content of the child loads.
        case duringLoad
        /// After the child screen joined the container, while it waits for its first frame.
        case duringFirstFrame
    }

    @Test(
        "A switch during an open leaves one screen, and the next open runs",
        arguments: Moment.allCases
    )
    func switchDuringOpen(at moment: Moment) async throws {
        let tree = try await NavigationTests.makeTree(depth: 1)
        defer { tree.remove() }
        let other = try Workspace(
            id: tree.clock.makeIdentifier(),
            meta: RecordMeta(created: tree.clock.now()),
            title: "Other",
            sortKey: FractionalIndex(rawValue: "W")
        )
        try await tree.repository.create(other)
        let composition = try NavigationTests.composition(for: tree)
        defer { composition.container.view.removeFromSuperview() }
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        try await NavigationTests.waitForCanvas(tree.workspace.canvasID, in: composition)
        let card = try #require(composition.container.canvas?.content.cards[tree.chain[0]])
        composition.openChild(card)
        if moment == .duringFirstFrame { try await Self.waitForScreens(2, in: composition) }
        composition.selector?.select(other.id)
        try await NavigationTests.waitForCanvas(other.canvasID, in: composition)
        // The flight of the old parent ends after 0.35 s.
        try await Task.sleep(for: .milliseconds(600))
        #expect(Self.screens(in: composition) == 1, "Screens: \(Self.screens(in: composition))")
        #expect(composition.opening == nil)
        composition.selector?.select(tree.workspace.id)
        try await NavigationTests.waitForCanvas(tree.workspace.canvasID, in: composition)
        let again = try #require(composition.container.canvas?.content.cards[tree.chain[0]])
        composition.openChild(again)
        try await NavigationTests.waitForCanvas(CanvasID(tree.chain[0]), in: composition)
        #expect(Self.screens(in: composition) == 1)
    }

    /// The canvas screens in the container.
    private static func screens(in composition: AppComposition) -> Int {
        composition.container.children.count { $0 is CanvasViewController }
    }

    /// Waits until the container holds `count` canvas screens.
    private static func waitForScreens(_ count: Int, in composition: AppComposition) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: NavigationTests.timeout)
        while screens(in: composition) < count {
            guard clock.now < deadline else { throw OpenTimedOut() }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}
