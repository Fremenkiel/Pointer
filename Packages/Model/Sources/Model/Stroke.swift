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
        let offsets = points.values.map {
            Point(x: origin.x + Double($0.x), y: origin.y + Double($0.y))
        }
        bounds = Rect.bounding(offsets).expanded(by: Double(width) / 2)
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
