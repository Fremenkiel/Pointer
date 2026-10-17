/// A point in a 2D space, in `Double`.
public struct Point: Hashable, Codable, Sendable {
    /// The origin, (0, 0).
    public static let zero = Point(x: 0, y: 0)

    /// The horizontal coordinate.
    public var x: Double
    /// The vertical coordinate. It grows downward, as in UIKit.
    public var y: Double

    /// Makes a point.
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// `true` if both coordinates are finite numbers.
    public var isFinite: Bool { x.isFinite && y.isFinite }

    /// Returns the point moved by a vector.
    public static func + (point: Point, vector: Vector) -> Point {
        Point(x: point.x + vector.dx, y: point.y + vector.dy)
    }

    /// Returns the point moved back by a vector.
    public static func - (point: Point, vector: Vector) -> Point {
        Point(x: point.x - vector.dx, y: point.y - vector.dy)
    }

    /// Returns the vector from the second point to the first point.
    public static func - (end: Point, start: Point) -> Vector {
        Vector(dx: end.x - start.x, dy: end.y - start.y)
    }

    /// Returns the distance between two points.
    public func distance(to other: Point) -> Double {
        (other - self).length
    }
}
