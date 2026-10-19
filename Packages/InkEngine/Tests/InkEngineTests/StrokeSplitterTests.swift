import Foundation
import Geometry
import Model
import Testing

@testable import InkEngine

@Suite("Hit test and stroke split")
struct StrokeSplitterTests {
    private func erase(
        _ stroke: Stroke,
        at samples: [Point],
        radius: Double = 5,
        factory: inout StrokeFactory
    ) -> [Stroke]? {
        let path = EraserPath(samples: samples, radius: radius)
        return Eraser.command(erasing: [stroke], along: path, factory: &factory)?.parts
    }

    @Test("Erasing the middle of a stroke leaves two parts")
    func middle() throws {
        var factory = InkFixtures.factory()
        let stroke = InkFixtures.line(from: 0, to: 100, factory: &factory)
        let parts = try #require(erase(stroke, at: [Point(x: 50, y: 0)], factory: &factory))
        #expect(parts.count == 2)
        let reach = 5 + Double(stroke.width) / 2
        let left = parts[0].curve
        let right = parts[1].curve
        #expect(left.point(at: 0) == Point(x: 0, y: 0))
        #expect(abs(left.point(at: Double(left.segmentCount)).x - (50 - reach)) < 1e-4)
        #expect(abs(right.point(at: 0).x - (50 + reach)) < 1e-4)
        #expect(abs(right.point(at: Double(right.segmentCount)).x - 100) < 1e-4)
    }

    @Test("Erasing the end of a stroke leaves one part")
    func end() throws {
        var factory = InkFixtures.factory()
        let stroke = InkFixtures.line(from: 0, to: 100, factory: &factory)
        let parts = try #require(erase(stroke, at: [Point(x: 100, y: 0)], factory: &factory))
        #expect(parts.count == 1)
        #expect(parts[0].origin == stroke.origin)
    }

    @Test("A path that misses the stroke leaves it as it is")
    func miss() {
        var factory = InkFixtures.factory()
        let stroke = InkFixtures.line(from: 0, to: 100, factory: &factory)
        #expect(erase(stroke, at: [Point(x: 50, y: 20)], factory: &factory) == nil)
        let path = EraserPath(samples: [Point(x: 50, y: 6.5)], radius: 5)
        #expect(StrokeHitTest.coveredRanges(of: stroke, by: path).isEmpty)
    }

    @Test("A path over the whole stroke leaves no part")
    func whole() throws {
        var factory = InkFixtures.factory()
        let stroke = InkFixtures.line(from: 0, to: 100, factory: &factory)
        let path = [Point(x: -10, y: 0), Point(x: 110, y: 0)]
        let parts = try #require(erase(stroke, at: path, factory: &factory))
        #expect(parts.isEmpty)
        let ranges = StrokeHitTest.coveredRanges(
            of: stroke,
            by: EraserPath(samples: path, radius: 5)
        )
        #expect(ranges == [0...Double(stroke.points.count - 1)])
    }

    @Test("A stroke of one sample, stored as the point twice, goes away whole")
    func dot() throws {
        var factory = InkFixtures.factory()
        let dot = InkFixtures.stroke([Point(x: 3, y: 4), Point(x: 3, y: 4)], factory: &factory)
        let parts = try #require(erase(dot, at: [Point(x: 5, y: 4)], factory: &factory))
        #expect(parts.isEmpty)
    }

    @Test("A fast pencil with two samples far apart cuts the stroke between them")
    func band() throws {
        var factory = InkFixtures.factory()
        let stroke = InkFixtures.line(from: 0, to: 100, factory: &factory)
        let path = [Point(x: 50, y: -40), Point(x: 50, y: 40)]
        let parts = try #require(erase(stroke, at: path, factory: &factory))
        #expect(parts.count == 2)
    }

    @Test("A path that crosses a stroke twice leaves three parts")
    func twoCrossings() throws {
        var factory = InkFixtures.factory()
        let down = (0...40).map { Point(x: 0, y: Double($0) * 2) }
        let up = (1...40).map { Point(x: Double($0) * 1.5, y: 80 - Double($0) * 2) }
        let stroke = InkFixtures.stroke(down + up, factory: &factory)
        let path = [Point(x: -20, y: 40), Point(x: 50, y: 40)]
        let parts = try #require(erase(stroke, at: path, factory: &factory))
        #expect(parts.count == 3)
        let eraser = EraserPath(samples: path, radius: 5)
        #expect(StrokeHitTest.coveredRanges(of: stroke, by: eraser).count == 2)
    }

    @Test("A path of one sample erases a circle, and the grid finds only near bands")
    func pathBands() {
        let path = EraserPath(samples: [Point(x: 0, y: 0), Point(x: 100, y: 0)], radius: 2)
        #expect(path.bands(touching: Rect(minX: 40, minY: -1, maxX: 41, maxY: 1)) == [0])
        #expect(path.bands(touching: Rect(minX: 40, minY: 10, maxX: 41, maxY: 11)).isEmpty)
        #expect(path.distance(from: Point(x: 50, y: 3), toBand: 0) == 3)
        #expect(path.distance(from: Point(x: -4, y: 3), toBand: 0) == 5)
        let dot = EraserPath(samples: [Point(x: 1, y: 1)], radius: 2)
        #expect(dot.distance(from: Point(x: 4, y: 5), toBand: 0) == 5)
        #expect(dot.bounds == Rect(minX: -1, minY: -1, maxX: 3, maxY: 3))
    }

    @Test("A part shorter than the pen width is dropped (D-71)")
    func shortPart() throws {
        var factory = InkFixtures.factory()
        let stroke = InkFixtures.line(from: 0, to: 100, factory: &factory)
        // The eraser reaches 6 points: it covers 1 to 13, so the part from 0 to 1 is too short.
        let parts = try #require(erase(stroke, at: [Point(x: 7, y: 0)], factory: &factory))
        #expect(parts.count == 1)
        #expect(abs(parts[0].origin.x - 13) < 1e-4)
    }

    @Test("A part gets a new ID and clock value and keeps the width and the canvas")
    func partFields() throws {
        var factory = InkFixtures.factory()
        let stroke = InkFixtures.line(from: 0, to: 100, factory: &factory)
        let parts = try #require(erase(stroke, at: [Point(x: 51, y: 0)], factory: &factory))
        #expect(Set(parts.map(\.id)).count == 2)
        #expect(!parts.contains { $0.id == stroke.id })
        #expect(parts.allSatisfy { $0.created > stroke.created })
        #expect(parts.allSatisfy { $0.width == stroke.width && $0.canvasID == stroke.canvasID })
        let right = parts[1].points.values
        #expect(right[0].time == 0)
        #expect(abs(right[0].force - 0.5) < 1e-6)
        #expect(abs(right[1].time - (Float(29) / 240 - 57.0 / 2 / 240)) < 1e-3)
        #expect(parts[0].points.values.last?.force ?? 0 > 0.49)
    }

    @Test("A cut changes the curve only in the two segments next to the cut (D-65)")
    func shapeKeptAwayFromCut() throws {
        var factory = InkFixtures.factory()
        let stroke = InkFixtures.stroke(Self.wave, factory: &factory)
        let center = stroke.curve.point(at: 40.4) + Vector(dx: 0.3, dy: 1.1)
        let path = EraserPath(samples: [center], radius: 6)
        let covered = StrokeHitTest.coveredRanges(of: stroke, by: path)
        let parts = StrokeSplitter.parts(of: stroke, outside: covered, factory: &factory)
        try #require(parts.count == 2)
        let right = parts[1].curve
        let shift = Double(Int(covered[0].upperBound))
        for step in 0...200 {
            let parameter = 2 + Double(right.segmentCount - 2) * Double(step) / 200
            let old = stroke.curve.point(at: parameter + shift)
            #expect(right.point(at: parameter).distance(to: old) < 1e-3)
        }
    }

    @Test("A cut changes the curve by at most half the distance to the dropped point (D-72)")
    func shapeChange() throws {
        var factory = InkFixtures.factory()
        let stroke = InkFixtures.stroke(Self.wave, factory: &factory)
        let old = InkFixtures.samples(of: stroke.curve, count: 6_000)
        for parameter in [30.4, 70.7, 100.2, 2.5] {
            let center = stroke.curve.point(at: parameter) + Vector(dx: 0.3, dy: 1.1)
            let path = EraserPath(samples: [center], radius: 6)
            let covered = StrokeHitTest.coveredRanges(of: stroke, by: path)
            try #require(!covered.isEmpty)
            let parts = StrokeSplitter.parts(of: stroke, outside: covered, factory: &factory)
            let free = StrokeSplitter.freeRanges(
                outside: covered,
                upTo: Double(stroke.points.count - 1)
            )
            for (part, range) in zip(parts, free) {
                let bound = dropBound(of: stroke, part: part, range: range)
                let change = InkFixtures.largestDistance(
                    from: InkFixtures.samples(of: part.curve, count: 300),
                    to: old
                )
                #expect(change <= bound + 1e-6, "change \(change), bound \(bound)")
            }
        }
    }

    /// A wave with a small zigzag, 120 points about 1.7 points apart.
    private static let wave = (0..<120).map { index in
        let x = Double(index) * 1.7
        return Point(x: x, y: 12 * sin(x / 15) + Double(index % 3) * 0.6)
    }

    /// Half the larger distance from a new end point to its dropped control point (D-72).
    private func dropBound(of stroke: Stroke, part: Stroke, range: ClosedRange<Double>) -> Double {
        var distances = [0.0]
        let last = Double(stroke.points.count - 1)
        if range.lowerBound > 0 {
            let dropped = stroke.canvasPoint(at: Int(range.lowerBound.rounded(.down)))
            distances.append(part.canvasPoint(at: 0).distance(to: dropped))
        }
        if range.upperBound < last {
            let dropped = stroke.canvasPoint(at: Int(range.upperBound.rounded(.up)))
            distances.append(part.canvasPoint(at: part.points.count - 1).distance(to: dropped))
        }
        return (distances.max() ?? 0) / 2
    }
}
