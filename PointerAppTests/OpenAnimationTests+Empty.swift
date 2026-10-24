import Foundation
import XCTest

@testable import CanvasFeature
@testable import Pointer

/// The frame captures of an open and a leave of a card on an empty canvas, whose child is empty
/// too (m6-plan.md task 5.1, acceptance 1, D-98).
extension OpenAnimationTests {
    func testOpenAndLeaveOfEmptyCardHaveNoLateFrame() async throws {
        let tree = try await NavigationTests.makeTree(depth: 1)
        defer { await tree.remove() }
        let composition = try NavigationTests.composition(for: tree)
        defer { composition.container.view.removeFromSuperview() }
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        let parent = try await Self.waitForCanvas(tree.workspace.canvasID, in: composition)
        try await Self.waitForDrawn(parent)
        let card = try XCTUnwrap(parent.content.cards[tree.chain[0]])
        let open = try await Self.measureOpen(
            of: card,
            from: parent,
            in: composition,
            name: "an empty card"
        )
        XCTContext.runActivity(named: open.text) { _ in }
        // The product owner accepted 1 late frame at the start of this flight in full runs
        // (m6-fix-plan.md section 6.6). M10 traces it (D-125).
        Self.expectNoLateFrame(open.late, open.text, accepted: "D-125")
        try await Self.waitForDrawn(open.child)
        let leave = try await Self.measureLeave(
            of: open.child,
            card: card,
            in: composition,
            name: "an empty card"
        )
        XCTContext.runActivity(named: leave.text) { _ in }
        // The first frames of a leave wait for the driver to wire new memory, and under the load
        // of a full run one of them can miss (D-137). M10 traces the rest of the wait.
        Self.expectNoLateFrame(leave.late, leave.text, accepted: "D-137")
    }
}
