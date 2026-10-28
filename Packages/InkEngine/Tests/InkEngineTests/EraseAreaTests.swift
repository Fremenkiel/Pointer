import Foundation
import Geometry
import Model
import Testing

@testable import InkEngine

/// The area of an erase covers each change of the ink (F-07 of the M4 fix plan, D-65,
/// D-72): outside it, the parts show the same curve as the old stroke.
@Suite("The area of an erase")
struct EraseAreaTests {
    /// The largest difference of the curves outside the area, in canvas points.
    private static let tolerance = 0.01
    /// The random strokes and eraser paths of each spacing.
    private static let strokeCount = 30
    private static let pathCount = 12
    /// The length of a stroke in canvas points, and its largest point count.
    private static let strokeLength = 160.0
    private static let maxPointsPerStroke = 80
    /// The samples per segment of a curve.
    private static let samplesPerSegment = 16

    @Test(
        "Outside the area, each part and its old stroke differ by at most 0.01 points",
        arguments: [2.0, 5.0, 10.0, 20.0, 40.0]
    )
    func areaCoversTheChange(spacing: Double) throws {
        var factory = InkFixtures.factory()
        var random = SeededRandom(state: UInt64(spacing * 13))
        let strokes = (0..<Self.strokeCount).map { _ in
            Self.randomStroke(spacing: spacing, random: &random, factory: &factory)
        }
        var checked = 0
        for _ in 0..<Self.pathCount {
            let path = Self.randomPath(random: &random)
            for stroke in strokes {
                // One stroke per command, so that the parts belong to it.
                guard
                    let command = Eraser.command(erasing: [stroke], along: path, factory: &factory)
                else { continue }
                let area = try #require(command.area)
                let difference = Self.largestDifference(stroke, command.parts, outside: area)
                #expect(
                    difference <= Self.tolerance,
                    "Spacing \(spacing): the ink differs by \(difference) outside the area"
                )
                checked += 1
            }
        }
        #expect(checked > Self.pathCount, "The paths cut too few strokes: \(checked)")
    }

    /// A random walk of control points `spacing` apart that turns by up to 0.8 radians per step.
    private static func randomStroke(
        spacing: Double,
        random: inout SeededRandom,
        factory: inout StrokeFactory
    ) -> Stroke {
        var point = Point(x: Double.random(in: -60...60, using: &random), y: -100)
        var heading = Double.random(in: 1.2...1.9, using: &random)
        var points: [Point] = []
        let count = min(Int(strokeLength / spacing) + 2, maxPointsPerStroke)
        for _ in 0..<count {
            points.append(point)
            heading += Double.random(in: -0.8...0.8, using: &random)
            point = Point(x: point.x + cos(heading) * spacing, y: point.y + sin(heading) * spacing)
        }
        return InkFixtures.stroke(points, factory: &factory)
    }

    /// A short horizontal eraser path with a random radius.
    private static func randomPath(random: inout SeededRandom) -> EraserPath {
        let y = Double.random(in: -90...40, using: &random)
        let x = Double.random(in: -100...60, using: &random)
        return EraserPath(
            samples: (0...10).map { Point(x: x + Double($0) * 4, y: y) },
            radius: Double.random(in: 3...15, using: &random)
        )
    }

    /// Returns the largest distance between the curves of the parts and of the old stroke, for
    /// the curve points whose ink can reach outside the area.
    private static func largestDifference(
        _ stroke: Stroke,
        _ parts: [Stroke],
        outside area: Rect
    ) -> Double {
        let half = Double(stroke.width) / 2
        let inner = Rect(
            minX: area.minX + half,
            minY: area.minY + half,
            maxX: area.maxX - half,
            maxY: area.maxY - half
        )
        let old = samples(of: stroke)
        let new = parts.map(samples(of:))
        let oldOutside = old.filter { !inner.contains($0) }
        var largest = 0.0
        for part in new {
            let outside = part.filter { !inner.contains($0) }
            largest = max(largest, InkFixtures.largestDistance(from: outside, to: old))
        }
        // The old curve outside the area must still show, in one of the parts.
        for point in oldOutside {
            let nearest = new.map { InkFixtures.largestDistance(from: [point], to: $0) }.min()
            largest = max(largest, nearest ?? .infinity)
        }
        return largest
    }

    private static func samples(of stroke: Stroke) -> [Point] {
        let points = (0..<stroke.points.count).map { stroke.canvasPoint(at: $0) }
        let curve = StrokeCurve(controlPoints: points)
        return InkFixtures.samples(of: curve, count: curve.segmentCount * samplesPerSegment)
    }
}
