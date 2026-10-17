/// An axis-aligned rectangle, in `Double`.
public struct Rect: Hashable, Codable, Sendable {
    /// The top-left corner.
    public var origin: Point
    /// The width and the height. Both are zero or positive.
    public var size: Size

    /// Makes a rectangle.
    ///
    /// - Precondition: The width and the height are zero or positive.
    public init(origin: Point, size: Size) {
        precondition(size.width >= 0, "Rect width must not be negative, got \(size.width)")
        precondition(size.height >= 0, "Rect height must not be negative, got \(size.height)")
        self.origin = origin
        self.size = size
    }

    /// Makes a rectangle from its smallest and its largest coordinates.
    ///
    /// - Precondition: `minX <= maxX` and `minY <= maxY`.
    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        precondition(minX <= maxX, "Rect minX \(minX) is greater than maxX \(maxX)")
        precondition(minY <= maxY, "Rect minY \(minY) is greater than maxY \(maxY)")
        self.init(
            origin: Point(x: minX, y: minY),
            size: Size(width: maxX - minX, height: maxY - minY)
        )
    }

    /// The smallest x coordinate.
    public var minX: Double { origin.x }
    /// The smallest y coordinate.
    public var minY: Double { origin.y }
    /// The largest x coordinate.
    public var maxX: Double { origin.x + size.width }
    /// The largest y coordinate.
    public var maxY: Double { origin.y + size.height }
    /// The center point.
    public var center: Point { origin + size.halfDiagonal }

    /// Returns `true` if the two rectangles share at least one point. Touching edges count.
    public func intersects(_ other: Rect) -> Bool {
        minX <= other.maxX && other.minX <= maxX && minY <= other.maxY && other.minY <= maxY
    }

    /// Returns `true` if the point is inside the rectangle or on its edge.
    public func contains(_ point: Point) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    /// Returns the rectangle grown by `amount` on each side.
    ///
    /// - Precondition: `amount` is zero or positive.
    public func expanded(by amount: Double) -> Rect {
        precondition(amount >= 0, "Rect growth must not be negative, got \(amount)")
        precondition(amount.isFinite, "Rect growth must be finite, got \(amount)")
        return Rect(
            minX: minX - amount,
            minY: minY - amount,
            maxX: maxX + amount,
            maxY: maxY + amount
        )
    }

    /// Returns the smallest rectangle that holds all points.
    ///
    /// - Precondition: `points` is not empty, and each point is finite.
    /// - Returns: The bounding rectangle of the points.
    public static func bounding(_ points: [Point]) -> Rect {
        precondition(!points.isEmpty, "Bounding rectangle needs at least one point")
        var low = points[0]
        var high = points[0]
        for point in points {
            precondition(point.isFinite, "Bounding rectangle got a point that is not finite")
            low = Point(x: min(low.x, point.x), y: min(low.y, point.y))
            high = Point(x: max(high.x, point.x), y: max(high.y, point.y))
        }
        return Rect(minX: low.x, minY: low.y, maxX: high.x, maxY: high.y)
    }
}
