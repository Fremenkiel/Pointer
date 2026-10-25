import Foundation
import Model
import XCTest

@testable import CanvasFeature
@testable import Pointer
@testable import Rendering

/// The flight of an open and of a leave keeps its frames while the main thread is blocked
/// (m6-fix-plan.md task 2.1, D-121, CAN-05): no late frame, and no frame that holds the camera
/// of the frame before. Each test blocks the main thread once, early in a flight. Only these
/// tests block it, because a blocked main actor broke other tests before.
@MainActor
final class FlightStallTests: XCTestCase {
    /// The block of the main thread: more than two frames at 120 Hz.
    private static let stall: TimeInterval = 0.02
    /// The block of an open starts this long after the tap, inside the first 50 ms of the flight.
    private static let openDelay = Duration.milliseconds(20)
    /// The poll of the start of the parent flight in a leave.
    private static let poll = Duration.milliseconds(1)

    func testOpenWithBlockedMainThreadHasNoLateFrame() async throws {
        let tree = try await NavigationTests.makeTree(depth: 1)
        defer { await tree.remove() }
        let composition = try NavigationTests.composition(for: tree)
        defer { composition.container.view.removeFromSuperview() }
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        let parent = try await OpenAnimationTests.waitForCanvas(
            tree.workspace.canvasID,
            in: composition
        )
        try await OpenAnimationTests.waitForDrawn(parent)
        let card = try XCTUnwrap(parent.content.cards[tree.chain[0]])
        // The open starts before the first suspension of `measureOpen`, so the block comes after
        // the tap.
        let block = Task { @MainActor in
            try await Task.sleep(for: Self.openDelay)
            Self.blockMainThread()
        }
        let open = try await OpenAnimationTests.measureOpen(
            of: card,
            from: parent,
            in: composition,
            name: "an empty card, main thread blocked"
        )
        try await block.value
        let samples = OpenAnimationTests.flightSamples("open", late: open.late, held: open.held)
        PerformanceRecord.attach(samples, line: open.text)
        XCTAssertEqual(open.late, 0, open.text)
        XCTAssertEqual(open.held, 0, open.text)
        try await OpenAnimationTests.waitForDrawn(open.child)
    }

    func testLeaveWithBlockedMainThreadHasNoLateFrame() async throws {
        let tree = try await NavigationTests.makeTree(depth: 1)
        defer { await tree.remove() }
        let composition = try NavigationTests.composition(for: tree)
        defer { composition.container.view.removeFromSuperview() }
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        let parent = try await OpenAnimationTests.waitForCanvas(
            tree.workspace.canvasID,
            in: composition
        )
        try await OpenAnimationTests.waitForDrawn(parent)
        let card = try XCTUnwrap(parent.content.cards[tree.chain[0]])
        composition.openChild(card)
        let child = try await OpenAnimationTests.waitForCanvas(card.childCanvasID, in: composition)
        try await OpenAnimationTests.waitForDrawn(child)
        let block = Task { @MainActor in
            try await Self.waitForParentFlight(of: card, in: composition)
            Self.blockMainThread()
        }
        let leave = try await OpenAnimationTests.measureLeave(
            of: child,
            card: card,
            in: composition,
            name: "an empty card, main thread blocked"
        )
        try await block.value
        let samples = OpenAnimationTests.flightSamples("leave", late: leave.late, held: leave.held)
        PerformanceRecord.attach(samples, line: leave.text)
        XCTAssertEqual(leave.late, 0, leave.text)
        XCTAssertEqual(leave.held, 0, leave.text)
    }

    /// Blocks the main thread for `stall`, as a long load or layout does.
    private static func blockMainThread() {
        Thread.sleep(forTimeInterval: stall)
    }

    /// Waits until the parent of a leave runs its flight and `measureLeave` watches its frames:
    /// the fade of the child ended, the parent has an observer, and its flight moved once. A
    /// block before the first move only starts the flight later.
    private static func waitForParentFlight(
        of card: Card,
        in composition: AppComposition
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: NavigationTests.timeout)
        while clock.now < deadline {
            if isParentFlying(card, in: composition) { return }
            try await Task.sleep(for: poll)
        }
        throw OpenTimedOut()
    }

    private static func isParentFlying(_ card: Card, in composition: AppComposition) -> Bool {
        guard !composition.container.isSwapping, let shown = composition.container.canvas else {
            return false
        }
        guard shown.canvasID == card.canvasID, shown.isInCardTransition,
            (shown.cameraController.flightProgress ?? 0) > 0
        else { return false }
        return shown.renderer.engine.inbox.withLock { $0.observer != nil }
    }
}
