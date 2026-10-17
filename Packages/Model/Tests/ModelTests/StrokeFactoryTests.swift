import Geometry
import Testing

@testable import Model

@Suite("Stroke factory")
struct StrokeFactoryTests {
    @Test("A path converts to canvas space with the transform and the width scale")
    func conversion() throws {
        var factory = Fixtures.factory()
        let toCanvas = Transform(scale: 0.5, translation: Vector(dx: 1_000_000, dy: 1_000_000))
        let path = PenPath(samples: Fixtures.samples(count: 4), toCanvas: toCanvas, width: 8)
        let strokes = try factory.makeStrokes(from: path, canvasID: Fixtures.canvas)
        let stroke = try #require(strokes.first)
        #expect(strokes.count == 1)
        #expect(stroke.width == 4)
        #expect(stroke.origin == Point(x: 1_000_000, y: 1_000_000))
        #expect(stroke.canvasPoint(at: 3) == Point(x: 1_000_001.5, y: 1_000_001.5))
        #expect(stroke.points.values[3].time == Float(3.0 / 240))
        #expect(stroke.points.values[0].force == 0.5)
    }

    @Test("One sample gives a dot with two equal points")
    func dot() throws {
        var factory = Fixtures.factory()
        let path = PenPath(samples: Fixtures.samples(count: 1), toCanvas: .identity, width: 2)
        let stroke = try #require(
            try factory.makeStrokes(from: path, canvasID: Fixtures.canvas).first
        )
        #expect(stroke.points.count == 2)
        #expect(stroke.points.values[0] == stroke.points.values[1])
    }

    @Test("A path without samples throws")
    func empty() {
        var factory = Fixtures.factory()
        let path = PenPath(samples: [], toCanvas: .identity, width: 2)
        #expect(throws: ModelError.emptyPath) {
            try factory.makeStrokes(from: path, canvasID: Fixtures.canvas)
        }
    }

    @Test("A path with a point that is not finite throws")
    func notFinite() {
        var factory = Fixtures.factory()
        let bad = ControlPointSample(location: Point(x: .nan, y: 0), force: 1, timeOffset: 0)
        let path = PenPath(samples: [bad], toCanvas: .identity, width: 2)
        #expect(throws: ModelError.self) {
            try factory.makeStrokes(from: path, canvasID: Fixtures.canvas)
        }
    }

    @Test("A width of zero throws")
    func zeroWidth() {
        var factory = Fixtures.factory()
        let path = PenPath(samples: Fixtures.samples(count: 2), toCanvas: .identity, width: 0)
        #expect(throws: ModelError.self) {
            try factory.makeStrokes(from: path, canvasID: Fixtures.canvas)
        }
    }

    @Test(
        "A path splits at the point limit with a 3-point overlap",
        arguments: [
            (Limits.maxPointsPerStroke, 1),
            (Limits.maxPointsPerStroke + 1, 2),
            (2 * Limits.maxPointsPerStroke - 3, 2),
            (2 * Limits.maxPointsPerStroke - 2, 3),
        ]
    )
    func split(count: Int, expectedStrokes: Int) throws {
        var factory = Fixtures.factory()
        let path = PenPath(samples: Fixtures.samples(count: count), toCanvas: .identity, width: 2)
        let strokes = try factory.makeStrokes(from: path, canvasID: Fixtures.canvas)
        #expect(strokes.count == expectedStrokes)
        #expect(Set(strokes.map(\.id)).count == strokes.count)
        let total = strokes.reduce(0) { $0 + $1.points.count }
        #expect(total == count + Limits.strokeOverlapPoints * (strokes.count - 1))
        for (first, second) in zip(strokes, strokes.dropFirst()) {
            let shared = first.points.count - Limits.strokeOverlapPoints
            #expect(first.canvasPoint(at: shared) == second.canvasPoint(at: 0))
            #expect(first.canvasPoint(at: first.points.count - 1) == second.canvasPoint(at: 2))
        }
    }

    @Test("The overlap keeps the original curve in both strokes")
    func overlapCurve() {
        let runs = StrokeFactory.runs(count: 10, limit: 6)
        #expect(runs == [0..<6, 3..<9, 6..<10])
    }
}
