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
        // bounds equal the bounds of the canvas points. Scalar `min` and `max` vectorize, and
        // `pointwiseMin` on `SIMD2<Float>` did not (P-04).
        var lowX = Float.infinity
        var lowY = Float.infinity
        var highX = -Float.infinity
        var highY = -Float.infinity
        for point in points.values {
            lowX = min(lowX, point.x)
            lowY = min(lowY, point.y)
            highX = max(highX, point.x)
            highY = max(highY, point.y)
        }
        assert(lowX <= highX && lowY <= highY, "Stroke \(id) has no finite bounds")
        bounds = Rect(
            minX: origin.x + Double(lowX),
            minY: origin.y + Double(lowY),
            maxX: origin.x + Double(highX),
            maxY: origin.y + Double(highY)
        ).expanded(by: Double(width) / 2)
    }

    /// The memberwise form, for a copy whose bounds are known.
    private init(copying stroke: Stroke, id: StrokeID, created: HybridTimestamp) {
        self.id = id
        canvasID = stroke.canvasID
        self.created = created
        origin = stroke.origin
        width = stroke.width
        points = stroke.points
        bounds = stroke.bounds
    }

    /// Returns the same stroke with another ID and creation time. It keeps the points and the
    /// bounds, so it does not walk the points again (P-04).
    ///
    /// - Returns: A stroke equal to this one except for `id` and `created`.
    public func renamed(id: StrokeID, created: HybridTimestamp) -> Stroke {
        let copy = Stroke(copying: self, id: id, created: created)
        return copy
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
