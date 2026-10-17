import Geometry
import Testing

@testable import Model

@Suite("Ink points and strokes")
struct StrokeTests {
    @Test("An ink point takes 16 bytes, as the point BLOB")
    func layout() {
        #expect(MemoryLayout<InkPoint>.size == 16)
        #expect(MemoryLayout<InkPoint>.stride == 16)
    }

    @Test("The bounds hold the control points plus half the width")
    func bounds() {
        let stroke = Fixtures.stroke(
            points: [
                InkPoint(x: 0, y: 0, force: 1, time: 0),
                InkPoint(x: 10, y: -4, force: 1, time: 0.1),
            ],
            width: 2
        )
        #expect(stroke.bounds == Rect(minX: 99, minY: 195, maxX: 111, maxY: 201))
        #expect(stroke.canvasPoint(at: 1) == Point(x: 110, y: 196))
    }

    @Test("The curve of a stroke starts at its origin")
    func curve() {
        let stroke = Fixtures.stroke(points: [
            InkPoint(x: 0, y: 0, force: 1, time: 0), InkPoint(x: 5, y: 5, force: 1, time: 0),
            InkPoint(x: 10, y: 0, force: 1, time: 0),
        ])
        let start = stroke.curve.point(at: 0)
        #expect(start.distance(to: stroke.origin) < 1e-9)
        #expect(stroke.curve.segmentCount == 2)
    }

    @Test("A copy of a stroke shares its points")
    func sharing() {
        let stroke = Fixtures.stroke(points: [
            InkPoint(x: 0, y: 0, force: 1, time: 0), InkPoint(x: 1, y: 1, force: 1, time: 0),
        ])
        let copy = stroke
        #expect(copy.points === stroke.points)
    }

    @Test(
        "Point storage accepts 2 points and the limit",
        arguments: [2, Limits.maxPointsPerStroke]
    )
    func pointLimits(count: Int) {
        let points = InkPoints(
            Array(repeating: InkPoint(x: 0, y: 0, force: 0, time: 0), count: count)
        )
        #expect(points.count == count)
    }
}
