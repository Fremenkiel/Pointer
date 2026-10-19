import Geometry
import Model

/// The B-spline of one stroke in canvas space, read straight from its points (D-26).
///
/// It follows the end rule of `StrokeCurve`: each end uses a phantom point that mirrors the second
/// point through the end point. It reads the points of the stroke without a copy.
struct StrokeSpline {
    /// The stroke.
    let stroke: Stroke
    /// The control points of the stroke, read once.
    let values: [InkPoint]

    /// Makes the spline of a stroke.
    init(stroke: Stroke) {
        self.stroke = stroke
        values = stroke.points.values
    }

    /// The largest curve parameter, one less than the number of points.
    var maxParameter: Double { Double(values.count - 1) }

    /// The number of segments.
    var segmentCount: Int { values.count - 1 }

    /// Returns the point at `index`, with the phantom points at -1 and at `count`.
    ///
    /// - Precondition: `index` is in `-1...count`.
    func point(at index: Int) -> InkPoint {
        precondition(index >= -1 && index <= values.count, "Point index \(index) out of range")
        assert(values.count >= 2, "A stroke holds \(values.count) points")
        if index == -1 { return Self.mirror(values[0], through: values[1]) }
        if index == values.count {
            return Self.mirror(values[values.count - 1], through: values[values.count - 2])
        }
        return values[index]
    }

    /// Returns the canvas position of the curve at a parameter.
    ///
    /// - Precondition: `parameter` is in `0...maxParameter`.
    func position(at parameter: Double) -> Point {
        let (segment, local) = locate(parameter)
        let offset = StrokeCurve.evaluate(
            Self.offset(point(at: segment - 1)),
            Self.offset(point(at: segment)),
            Self.offset(point(at: segment + 1)),
            Self.offset(point(at: segment + 2)),
            local
        )
        return Point(x: stroke.origin.x + offset.x, y: stroke.origin.y + offset.y)
    }

    /// Returns the force and the time of the curve at a parameter, with the weights of the curve.
    ///
    /// - Precondition: `parameter` is in `0...maxParameter`.
    func forceAndTime(at parameter: Double) -> (force: Float, time: Float) {
        let (segment, local) = locate(parameter)
        func value(_ index: Int) -> Point {
            let point = point(at: segment + index)
            return Point(x: Double(point.force), y: Double(point.time))
        }
        let value = StrokeCurve.evaluate(value(-1), value(0), value(1), value(2), local)
        assert(value.x.isFinite && value.y.isFinite, "Force or time at \(parameter) not finite")
        return (Float(value.x), Float(value.y))
    }

    /// The growth of a query box before its conversion to `Float` offsets, so that the rounding
    /// never drops a segment that touches the box.
    static let boxMargin = 0.01

    /// Returns the segments whose 4 shaping points have bounds that touch a box, in order.
    ///
    /// It makes one pass over the points with an outcode per point: one bit for each side of the
    /// box that the point lies beyond. A segment misses the box if all 4 of its points lie beyond
    /// the same side.
    func segments(near box: Rect) -> [Int] {
        let low = SIMD2<Float>(
            Float(box.minX - Self.boxMargin - stroke.origin.x),
            Float(box.minY - Self.boxMargin - stroke.origin.y)
        )
        let high = SIMD2<Float>(
            Float(box.maxX + Self.boxMargin - stroke.origin.x),
            Float(box.maxY + Self.boxMargin - stroke.origin.y)
        )
        func code(_ point: InkPoint) -> UInt8 {
            (point.x < low.x ? 1 : 0) | (point.x > high.x ? 2 : 0) | (point.y < low.y ? 4 : 0)
                | (point.y > high.y ? 8 : 0)
        }
        let end = code(point(at: values.count))
        var window = (code(point(at: -1)), code(values[0]), code(values[1]))
        var result: [Int] = []
        for segment in 0..<segmentCount {
            let next = segment + 2 < values.count ? code(values[segment + 2]) : end
            if window.0 & window.1 & window.2 & next == 0 { result.append(segment) }
            window = (window.1, window.2, next)
        }
        assert(result.count <= segmentCount, "More near segments than segments")
        return result
    }

    /// Returns the bounds of the 4 points that shape a segment. The segment stays inside them.
    ///
    /// - Precondition: `segment` is in `0..<segmentCount`.
    func hullBounds(ofSegment segment: Int) -> Rect {
        precondition(segment >= 0 && segment < segmentCount, "Segment \(segment) out of range")
        var low = SIMD2<Float>(repeating: .infinity)
        var high = SIMD2<Float>(repeating: -.infinity)
        for index in (segment - 1)...(segment + 2) {
            let value = point(at: index)
            low = pointwiseMin(low, SIMD2(value.x, value.y))
            high = pointwiseMax(high, SIMD2(value.x, value.y))
        }
        assert(low.x <= high.x && low.y <= high.y, "Segment \(segment) has no finite hull")
        return Rect(
            minX: stroke.origin.x + Double(low.x),
            minY: stroke.origin.y + Double(low.y),
            maxX: stroke.origin.x + Double(high.x),
            maxY: stroke.origin.y + Double(high.y)
        )
    }

    /// Returns the length of the hull polyline of a segment, an upper bound of its curve length.
    ///
    /// - Precondition: `segment` is in `0..<segmentCount`.
    func hullLength(ofSegment segment: Int) -> Double {
        precondition(segment >= 0 && segment < segmentCount, "Segment \(segment) out of range")
        var length = 0.0
        for index in (segment - 1)...(segment + 1) {
            length += Self.offset(point(at: index)).distance(to: Self.offset(point(at: index + 1)))
        }
        assert(length >= 0, "A length is never negative")
        return length
    }

    private func locate(_ parameter: Double) -> (segment: Int, local: Double) {
        precondition(
            parameter >= 0 && parameter <= maxParameter,
            "Curve parameter \(parameter) out of 0...\(maxParameter)"
        )
        let segment = min(Int(parameter), segmentCount - 1)
        return (segment, min(max(parameter - Double(segment), 0), 1))
    }

    private static func offset(_ point: InkPoint) -> Point {
        Point(x: Double(point.x), y: Double(point.y))
    }

    private static func mirror(_ end: InkPoint, through next: InkPoint) -> InkPoint {
        InkPoint(
            x: 2 * end.x - next.x,
            y: 2 * end.y - next.y,
            force: 2 * end.force - next.force,
            time: 2 * end.time - next.time
        )
    }
}
