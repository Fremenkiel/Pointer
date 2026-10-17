/// A displacement in a 2D space, in `Double`.
public struct Vector: Hashable, Codable, Sendable {
    /// The vector with zero length.
    public static let zero = Vector(dx: 0, dy: 0)

    /// The horizontal component.
    public var dx: Double
    /// The vertical component.
    public var dy: Double

    /// Makes a vector.
    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }

    /// The Euclidean length.
    public var length: Double { (dx * dx + dy * dy).squareRoot() }

    /// Returns the sum of two vectors.
    public static func + (left: Vector, right: Vector) -> Vector {
        Vector(dx: left.dx + right.dx, dy: left.dy + right.dy)
    }

    /// Returns the difference of two vectors.
    public static func - (left: Vector, right: Vector) -> Vector {
        Vector(dx: left.dx - right.dx, dy: left.dy - right.dy)
    }

    /// Returns the vector scaled by a factor.
    public static func * (vector: Vector, factor: Double) -> Vector {
        Vector(dx: vector.dx * factor, dy: vector.dy * factor)
    }

    /// Returns the vector divided by a factor.
    ///
    /// - Precondition: `divisor` is not zero.
    public static func / (vector: Vector, divisor: Double) -> Vector {
        precondition(divisor != 0, "Vector divisor must not be zero")
        return Vector(dx: vector.dx / divisor, dy: vector.dy / divisor)
    }
}
