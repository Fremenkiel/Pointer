import Foundation
import Geometry
import Model
import Testing

@testable import Rendering

/// The text filter of the offscreen preview keeps each box whose layout touches the region
/// (the M10 plan task 3.4).
@Suite("Preview text filter")
@MainActor
struct PreviewTextFilterTests {
    nonisolated private static let texts = [
        "node",
        String(repeating: "word ", count: 400),
        String(repeating: "a\n", count: 300),
        String(repeating: "漢字", count: 500),
        String(repeating: "🌳", count: 300),
        String(repeating: "\u{FDFD}", count: 200),
        String(repeating: "x", count: 2_000),
    ]

    @Test("A box whose layout touches the region passes the filter", arguments: texts.indices)
    func keepsTouchingBoxes(index: Int) throws {
        let box = try TextRenderingTests.box(Self.texts[index], at: Point(x: 0, y: 0))
        let store = TextStore()
        store.add(box)
        let bounds = try #require(store.entries[box.id]?.bounds)
        // Regions of 100 by 100 points in a column from above the box to below it, and in a row
        // from the left of the box to its right, 5 points apart.
        var touching = 0
        var places: [Point] = []
        for step in 0..<Int((bounds.size.height + 600) / 5) {
            places.append(Point(x: 0, y: bounds.minY - 300 + Double(step) * 5))
        }
        for step in 0..<Int((bounds.size.width + 600) / 5) {
            places.append(Point(x: bounds.minX - 300 + Double(step) * 5, y: 0))
        }
        for place in places {
            let region = Rect(origin: place, size: Size(width: 100, height: 100))
            guard bounds.intersects(region) else { continue }
            touching += 1
            #expect(FrameRenderer.mayTouch(box, region), "Region at \(place)")
        }
        #expect(touching > 0, "The test regions touch the box")
    }

    @Test("A short box far above the region does not pass the filter")
    func dropsBoxAbove() throws {
        let box = try TextRenderingTests.box("node", at: Point(x: 0, y: 0))
        let region = Rect(origin: Point(x: 0, y: 500), size: Size(width: 100, height: 100))
        #expect(!FrameRenderer.mayTouch(box, region))
    }
}
