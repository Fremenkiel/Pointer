import Foundation
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

    @Test("A renamed stroke keeps its canvas, width, points, and bounds, with the new ID and time")
    func renamed() {
        var factory = Fixtures.factory()
        let points = InkPoints([
            InkPoint(x: 0, y: 0, force: 1, time: 0), InkPoint(x: 5, y: -3, force: 1, time: 0.1),
        ])
        let stroke = Stroke(
            id: factory.identifiers.make(StrokeID.self),
            canvasID: Fixtures.canvas,
            created: factory.clock.now(),
            origin: Point(x: 10, y: 20),
            width: 2,
            points: points
        )
        let id = factory.identifiers.make(StrokeID.self)
        let created = factory.clock.now()
        let copy = stroke.renamed(id: id, created: created)
        #expect(copy.id == id)
        #expect(copy.created == created)
        #expect(copy.canvasID == stroke.canvasID)
        #expect(copy.origin == stroke.origin)
        #expect(copy.width == stroke.width)
        #expect(copy.points === stroke.points)
        #expect(copy.bounds == stroke.bounds)
    }

    @Test(
        "The bounds equal the bounds of the pointwise minimum and maximum (P-04)",
        arguments: [2, 3, 300]
    )
    func boundsMatchPointwise(count: Int) {
        var random = SeededRandom(state: UInt64(count))
        let values = (0..<count).map { _ in
            InkPoint(
                x: Float.random(in: -500...500, using: &random),
                y: Float.random(in: -500...500, using: &random),
                force: 1,
                time: 0
            )
        }
        let stroke = Stroke(
            id: StrokeID(rawValue: UUID()),
            canvasID: Fixtures.canvas,
            created: Fixtures.time,
            origin: Point(x: -1_234.5, y: 678.25),
            width: 3,
            points: InkPoints(values)
        )
        var low = SIMD2<Float>(repeating: .infinity)
        var high = SIMD2<Float>(repeating: -.infinity)
        for value in values {
            low = pointwiseMin(low, SIMD2(value.x, value.y))
            high = pointwiseMax(high, SIMD2(value.x, value.y))
        }
        let expected = Rect(
            minX: -1_234.5 + Double(low.x),
            minY: 678.25 + Double(low.y),
            maxX: -1_234.5 + Double(high.x),
            maxY: 678.25 + Double(high.y)
        ).expanded(by: 1.5)
        #expect(stroke.bounds == expected)
    }
}
