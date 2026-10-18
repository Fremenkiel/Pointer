import Geometry

/// One finished line of the pen. A stroke never changes after it is created (data-model.md 7.4).
public struct Stroke: Identifiable, Sendable {
    /// The ID of the stroke.
    public let id: StrokeID
    /// The canvas that holds the stroke.
    public let canvasID: CanvasID
    /// The clock value at creation.
    public let created: HybridTimestamp
    /// The canvas position of the first point. The point offsets are relative to it.
    public let origin: Point
    /// The line width in canvas points.
    public let width: Float
    /// The control points of the B-spline (D-26), shared between copies.
    public let points: InkPoints
    /// The canvas rectangle that holds the whole line, including its width.
    public let bounds: Rect

    /// Makes a stroke and computes its bounds.
    ///
    /// The curve stays inside the convex hull of its control points, also at the ends, so the
    /// bounds of the control points plus half the width hold the whole line.
    ///
    /// - Precondition: `width` is positive and finite, and `origin` is finite.
    public init(
        id: StrokeID,
        canvasID: CanvasID,
        created: HybridTimestamp,
        origin: Point,
        width: Float,
        points: InkPoints
    ) {
        precondition(
            width > 0 && width.isFinite,
            "Stroke \(id) width must be positive, got \(width)"
        )
        precondition(origin.isFinite, "Stroke \(id) origin is not finite")
        self.id = id
        self.canvasID = canvasID
        self.created = created
        self.origin = origin
        self.width = width
        self.points = points
        // One loop over the offsets, without a temporary array of points (docs/m2-fix-plan.md,
        // phase 5). The conversion to Double is exact and the addition keeps the order, so the
        // bounds equal the bounds of the canvas points.
        var low = SIMD2<Float>(repeating: .infinity)
        var high = SIMD2<Float>(repeating: -.infinity)
        for point in points.values {
            low = pointwiseMin(low, SIMD2(point.x, point.y))
            high = pointwiseMax(high, SIMD2(point.x, point.y))
        }
        assert(low.x <= high.x && low.y <= high.y, "Stroke \(id) has no finite bounds")
        bounds = Rect(
            minX: origin.x + Double(low.x),
            minY: origin.y + Double(low.y),
            maxX: origin.x + Double(high.x),
            maxY: origin.y + Double(high.y)
        ).expanded(by: Double(width) / 2)
    }

    /// Returns the canvas position of the control point at `index`.
    ///
    /// - Precondition: `index` is a valid point index.
    public func canvasPoint(at index: Int) -> Point {
        precondition(points.values.indices.contains(index), "Point \(index) out of stroke \(id)")
        let point = points.values[index]
        return Point(x: origin.x + Double(point.x), y: origin.y + Double(point.y))
    }

    /// The curve of the stroke in canvas space.
    public var curve: StrokeCurve {
        StrokeCurve(controlPoints: points.values.indices.map(canvasPoint(at:)))
    }
}
