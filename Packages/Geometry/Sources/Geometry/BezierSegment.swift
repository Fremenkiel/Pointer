/// One cubic Bézier segment: a start point, two control points, and an end point.
public struct BezierSegment: Equatable, Sendable {
    /// The start point, on the curve.
    public let start: Point
    /// The first control point.
    public let control1: Point
    /// The second control point.
    public let control2: Point
    /// The end point, on the curve.
    public let end: Point

    /// Makes a segment.
    public init(start: Point, control1: Point, control2: Point, end: Point) {
        self.start = start
        self.control1 = control1
        self.control2 = control2
        self.end = end
    }

    /// Returns the point of the segment at a parameter.
    ///
    /// - Precondition: `local` is in `0...1`.
    /// - Returns: The start point at 0 and the end point at 1.
    public func point(at local: Double) -> Point {
        precondition(local >= 0 && local <= 1, "Bézier parameter \(local) out of 0...1")
        let inverse = 1 - local
        let w0 = inverse * inverse * inverse
        let w1 = 3 * inverse * inverse * local
        let w2 = 3 * inverse * local * local
        let w3 = local * local * local
        assert(abs(w0 + w1 + w2 + w3 - 1) < 1e-9, "Bézier weights must sum to 1 at \(local)")
        return Point(
            x: w0 * start.x + w1 * control1.x + w2 * control2.x + w3 * end.x,
            y: w0 * start.y + w1 * control1.y + w2 * control2.y + w3 * end.y
        )
    }
}
