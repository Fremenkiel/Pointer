/// The uniform cubic B-spline that PencilKit draws through the control points of a stroke (D-26).
///
/// The curve has one segment between each pair of neighbor control points. The parameter runs from
/// 0 at the first control point to `count - 1` at the last. The curve passes through both end
/// points, because each end uses a phantom point that mirrors the second point through the end
/// point. A test in the iPad simulator compared this rule with `PKStrokePath` (docs/m2-plan.md
/// section 1).
public struct StrokeCurve: Sendable {
    /// The control points.
    public let controlPoints: [Point]

    /// Makes a curve.
    ///
    /// - Precondition: At least 2 control points, all finite.
    public init(controlPoints: [Point]) {
        precondition(
            controlPoints.count >= 2,
            "A curve needs 2 control points, got \(controlPoints.count)"
        )
        precondition(controlPoints.allSatisfy(\.isFinite), "A curve control point is not finite")
        self.controlPoints = controlPoints
    }

    /// The number of segments, one less than the number of control points.
    public var segmentCount: Int { controlPoints.count - 1 }

    /// Returns the control point at `index`, with the phantom points at -1 and at `count`.
    ///
    /// - Precondition: `index` is in `-1...count`.
    public func extendedControlPoint(at index: Int) -> Point {
        let count = controlPoints.count
        assert(count >= 2, "A curve holds \(count) control points")
        precondition(
            index >= -1 && index <= count,
            "Control point index \(index) out of -1...\(count)"
        )
        if index == -1 {
            return controlPoints[0] + (controlPoints[0] - controlPoints[1])
        }
        if index == count {
            return controlPoints[count - 1] + (controlPoints[count - 1] - controlPoints[count - 2])
        }
        return controlPoints[index]
    }

    /// Returns the point of the curve at a parameter.
    ///
    /// - Precondition: `parameter` is in `0...segmentCount`.
    /// - Returns: The point on the curve. Parameter 0 gives the first control point.
    public func point(at parameter: Double) -> Point {
        precondition(
            parameter >= 0 && parameter <= Double(segmentCount),
            "Curve parameter \(parameter) out of 0...\(segmentCount)"
        )
        let segment = min(Int(parameter), segmentCount - 1)
        let local = parameter - Double(segment)
        assert(
            segment >= 0 && segment < segmentCount,
            "Segment \(segment) out of 0..<\(segmentCount)"
        )
        return Self.evaluate(
            extendedControlPoint(at: segment - 1),
            extendedControlPoint(at: segment),
            extendedControlPoint(at: segment + 1),
            extendedControlPoint(at: segment + 2),
            local
        )
    }

    /// Returns the point of one uniform cubic B-spline segment.
    ///
    /// - Precondition: `local` is in `0...1`.
    /// - Returns: The point at `local` on the segment between `p1` and `p2`.
    public static func evaluate(
        _ p0: Point,
        _ p1: Point,
        _ p2: Point,
        _ p3: Point,
        _ local: Double
    ) -> Point {
        precondition(local >= 0 && local <= 1, "Segment parameter \(local) out of 0...1")
        let t2 = local * local
        let t3 = t2 * local
        let inverse = 1 - local
        let w0 = inverse * inverse * inverse / 6
        let w1 = (3 * t3 - 6 * t2 + 4) / 6
        let w2 = (-3 * t3 + 3 * t2 + 3 * local + 1) / 6
        let w3 = t3 / 6
        assert(abs(w0 + w1 + w2 + w3 - 1) < 1e-9, "B-spline weights must sum to 1 at \(local)")
        return Point(
            x: w0 * p0.x + w1 * p1.x + w2 * p2.x + w3 * p3.x,
            y: w0 * p0.y + w1 * p1.y + w2 * p2.y + w3 * p3.y
        )
    }
}
