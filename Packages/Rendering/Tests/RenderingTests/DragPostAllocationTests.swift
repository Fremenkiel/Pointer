import Geometry
import Model
import QuartzCore
import XCTest

@testable import Rendering

/// The heap allocations on the main thread of one drag step of a text box and of a card: the
/// post of the moved item to the inbox (review M9 section 3.3, item 1, the M10 plan task 3.1). A
/// frame takes the inbox after each step, as the display link does in the app.
@MainActor
final class DragPostAllocationTests: XCTestCase {
    private static let steps = 20

    private func renderer() throws -> (CanvasRenderer, CAMetalLayer) {
        let renderer = try CanvasRenderer(configuration: RendererConfiguration())
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(width: 400, height: 240)
        renderer.setViewport(viewSize: Size(width: 200, height: 120), displayScale: 2)
        return (renderer, layer)
    }

    /// Returns the median count of `post` over the items, with a frame after each step. The
    /// items exist before the count, so that it holds the post alone.
    private func medianCount<Item>(
        renderer: CanvasRenderer,
        layer: CAMetalLayer,
        items: [Item],
        post: (Item) -> Void
    ) throws -> Int {
        var counts: [Int] = []
        for item in items {
            let count = AllocationCounter.countMainThread { post(item) }
            counts.append(try XCTUnwrap(count))
            _ = renderer.renderFrame(into: layer, deadline: nil)
        }
        return counts.sorted()[counts.count / 2]
    }

    func testTextDragStepAllocatesNothing() throws {
        let (renderer, layer) = try renderer()
        let box = try TextRenderingTests.box("node", at: .zero)
        renderer.load([box])
        let items = try (1...Self.steps).map { step in
            try box.moving(to: Point(x: Double(step), y: 0), at: box.meta.modified)
        }
        let median = try medianCount(renderer: renderer, layer: layer, items: items) { moved in
            renderer.placeTextBox(moved)
        }
        let line = "allocations of a text drag step: median \(median)"
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertEqual(median, 0, line)
    }

    func testCardDragStepAllocatesNothing() throws {
        let (renderer, layer) = try renderer()
        let card = try CardStoreTests.card(1)
        renderer.load([card])
        let items = try (1...Self.steps).map { step in
            let target = Point(x: card.frame.minX + Double(step), y: card.frame.minY)
            return try card.moving(to: target, at: card.meta.modified)
        }
        let median = try medianCount(renderer: renderer, layer: layer, items: items) { moved in
            renderer.placeCard(moved)
        }
        let line = "allocations of a card drag step: median \(median)"
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertEqual(median, 0, line)
    }
}
