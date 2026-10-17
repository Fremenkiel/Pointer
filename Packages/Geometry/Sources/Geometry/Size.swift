/// A width and a height, in `Double`.
public struct Size: Hashable, Codable, Sendable {
    /// The size with zero width and zero height.
    public static let zero = Size(width: 0, height: 0)

    /// The width.
    public var width: Double
    /// The height.
    public var height: Double

    /// Makes a size.
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// The vector from the top-left corner to the center of a rectangle of this size.
    public var halfDiagonal: Vector { Vector(dx: width / 2, dy: height / 2) }
}
