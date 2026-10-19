import Foundation
import Geometry
import Model

/// A wall clock that returns a fixed time (TEST-04).
struct FixedWallClock: WallClock {
    let millis: UInt64

    func nowMillis() -> UInt64 { millis }
}

/// A deterministic random source: SplitMix64.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

enum InkFixtures {
    static let device = DeviceID(
        rawValue: UUID(uuid: (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    )
    static let canvas = CanvasID(
        rawValue: UUID(uuid: (2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    )

    static func factory() -> StrokeFactory {
        let clock = FixedWallClock(millis: 1_700_000_000_000)
        return StrokeFactory(
            identifiers: IdentifierFactory(wallClock: clock, random: SeededRandom(state: 3)),
            clock: HybridClock(device: device, wallClock: clock)
        )
    }

    /// Makes a stroke through canvas points, with force 0.5 and 240 Hz times.
    static func stroke(
        _ points: [Point],
        width: Float = 2,
        factory: inout StrokeFactory
    ) -> Stroke {
        let origin = points[0]
        let values = points.enumerated().map { index, point in
            InkPoint(
                x: Float(point.x - origin.x),
                y: Float(point.y - origin.y),
                force: 0.5,
                time: Float(index) / 240
            )
        }
        return Stroke(
            id: factory.identifiers.make(StrokeID.self),
            canvasID: canvas,
            created: factory.clock.now(),
            origin: origin,
            width: width,
            points: InkPoints(values)
        )
    }

    /// Makes a straight line from `(x0, y)` to `(x1, y)` with a point every `spacing` points.
    static func line(
        from x0: Double,
        to x1: Double,
        y: Double = 0,
        spacing: Double = 2,
        factory: inout StrokeFactory
    ) -> Stroke {
        let count = Int(((x1 - x0) / spacing).rounded()) + 1
        let points = (0..<count).map { Point(x: x0 + Double($0) * spacing, y: y) }
        return stroke(points, factory: &factory)
    }

    /// Returns the largest distance from the points of `curve` to the polyline of `reference`.
    static func largestDistance(from curve: [Point], to reference: [Point]) -> Double {
        curve.map { point in
            zip(reference, reference.dropFirst()).map { start, end in
                distance(from: point, toSegment: start, end)
            }.min() ?? .infinity
        }.max() ?? 0
    }

    static func distance(from point: Point, toSegment start: Point, _ end: Point) -> Double {
        let direction = end - start
        let lengthSquared = direction.dx * direction.dx + direction.dy * direction.dy
        guard lengthSquared > 0 else { return point.distance(to: start) }
        let offset = point - start
        let along = (offset.dx * direction.dx + offset.dy * direction.dy) / lengthSquared
        return point.distance(to: start + direction * min(max(along, 0), 1))
    }

    /// Returns `count + 1` points of a curve, evenly spaced in its parameter.
    static func samples(of curve: StrokeCurve, count: Int) -> [Point] {
        (0...count).map { step in
            curve.point(at: Double(curve.segmentCount) * Double(step) / Double(count))
        }
    }
}
