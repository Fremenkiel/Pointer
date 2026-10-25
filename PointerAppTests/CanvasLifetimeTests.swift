import Foundation
import Model
import XCTest
import os

@testable import CanvasFeature
@testable import Pointer
@testable import Rendering

/// The lifetime of the canvas screens of the card tree: a screen that leaves the container goes
/// away with its renderer, so a session of many opens and leaves holds one canvas at a time
/// (architecture.md section 6, PERF-01).
@MainActor
final class CanvasLifetimeTests: XCTestCase {
    /// The opens and leaves of one run.
    private static let rounds = 12
    /// The longest wait for the screens to go away after a leave.
    private static let releaseTimeout = Duration.seconds(5)
    /// The largest growth of the steady memory after the first round. A renderer that stays
    /// holds its two committed textures of about 32 MB each on the iPad Pro 11-inch (M4).
    private static let growthLimitMegabytes = 32.0

    /// Weak references to a canvas screen and its renderer.
    @MainActor
    private struct Watched {
        weak var canvas: CanvasViewController?
        weak var renderer: CanvasRenderer?
        weak var engine: RenderEngine?

        init(_ canvas: CanvasViewController) {
            self.canvas = canvas
            renderer = canvas.renderer
            engine = canvas.renderer.engine
        }

        var isAlive: Bool { canvas != nil || renderer != nil || engine != nil }
    }

    func testLeftCanvasesGoAwayWithTheirRenderers() async throws {
        let tree = try await NavigationTests.makeTree(depth: 1)
        defer { await tree.remove() }
        let composition = try NavigationTests.composition(for: tree)
        defer { composition.container.view.removeFromSuperview() }
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        try await NavigationTests.waitForCanvas(tree.workspace.canvasID, in: composition)
        var watched: [Watched] = []
        var used: [Double] = []
        for round in 1...Self.rounds {
            watched += try await Self.openAndLeave(tree.chain[0], of: tree, in: composition)
            let alive = try await Self.waitForRelease(of: watched)
            XCTAssertEqual(
                alive,
                0,
                "\(alive) left screens alive after round \(round): \(Self.describe(watched))"
            )
            // The system frees the textures of a renderer late, so the measure waits for it.
            try await OnScreenCanvas.waitForSteadyMemory()
            used.append(-Double(os_proc_available_memory()) / 1_048_576)
        }
        // The first round makes the caches of the process, so the growth counts after it.
        let grown = (used.last ?? 0) - (used.first ?? 0)
        let text = String(
            format: "canvas lifetime: %d screens watched, memory grew %.1f MB in rounds 2 to %d",
            watched.count,
            grown,
            Self.rounds
        )
        XCTContext.runActivity(named: text) { _ in }
        PerformanceRecord.attach(["growth.mb": grown])
        XCTAssertLessThan(grown, Self.growthLimitMegabytes, text)
    }

    /// Opens the card and leaves it, and returns the parent and the child that left. The screens
    /// are locals of this function, so the caller holds no reference to them after it.
    private static func openAndLeave(
        _ card: CardID,
        of tree: NavigationTests.Tree,
        in composition: AppComposition
    ) async throws -> [Watched] {
        let parent = try XCTUnwrap(composition.container.canvas)
        composition.openChild(try XCTUnwrap(parent.content.cards[card]))
        try await NavigationTests.waitForCanvas(CanvasID(card), in: composition)
        let child = try XCTUnwrap(composition.container.canvas)
        try await waitForFlight(of: child)
        composition.leave()
        try await NavigationTests.waitForCanvas(tree.workspace.canvasID, in: composition)
        try await waitForFlight(of: try XCTUnwrap(composition.container.canvas))
        return [Watched(parent), Watched(child)]
    }

    func testCompositionOfATestGoesAway() async throws {
        let tree = try await NavigationTests.makeTree(depth: 1)
        defer { await tree.remove() }
        weak var weakComposition: AppComposition?
        weak var weakCanvas: CanvasViewController?
        do {
            let composition = try NavigationTests.composition(for: tree)
            weakComposition = composition
            await composition.selector?.start(lastWorkspace: tree.workspace.id)
            try await NavigationTests.waitForCanvas(tree.workspace.canvasID, in: composition)
            weakCanvas = composition.container.canvas
            composition.container.view.removeFromSuperview()
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.releaseTimeout)
        while weakComposition != nil || weakCanvas != nil, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let text =
            "test composition: composition alive \(weakComposition != nil), "
            + "canvas alive \(weakCanvas != nil)"
        XCTContext.runActivity(named: text) { _ in }
        XCTAssertNil(weakComposition, text)
        XCTAssertNil(weakCanvas, text)
    }

    /// The index and the parts of each watched screen that stays.
    private static func describe(_ watched: [Watched]) -> String {
        watched.indices.filter { watched[$0].isAlive }.map { index in
            let item = watched[index]
            return "\(index): canvas \(item.canvas != nil), renderer \(item.renderer != nil), "
                + "engine \(item.engine != nil)"
        }.joined(separator: "; ")
    }

    /// Waits until a canvas ends its card flight.
    private static func waitForFlight(of canvas: CanvasViewController) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: NavigationTests.timeout)
        while canvas.isInCardTransition {
            guard clock.now < deadline else { throw OpenTimedOut() }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Waits until each watched screen goes away, and returns the number that stay.
    private static func waitForRelease(of watched: [Watched]) async throws -> Int {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: releaseTimeout)
        var alive = watched.count
        while clock.now < deadline {
            // The shown canvas came after the last leave, so the list does not hold it.
            alive = watched.filter(\.isAlive).count
            guard alive > 0 else { return 0 }
            try await Task.sleep(for: .milliseconds(20))
        }
        return alive
    }
}
