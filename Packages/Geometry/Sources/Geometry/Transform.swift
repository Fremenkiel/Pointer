/// A 2D affine transform, in `Double`, with the conventions of `CGAffineTransform`.
///
/// A point (x, y) maps to (a x + c y + tx, b x + d y + ty).
public struct Transform: Hashable, Codable, Sendable {
    /// The transform that changes nothing.
    public static let identity = Transform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    /// The x factor of x.
    public var a: Double
    /// The y factor of x.
    public var b: Double
    /// The x factor of y.
    public var c: Double
    /// The y factor of y.
    public var d: Double
    /// The x translation.
    public var tx: Double
    /// The y translation.
    public var ty: Double

    /// Makes a transform from its six values.
    ///
    /// - Precondition: All six values are finite.
    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        precondition(
            a.isFinite && b.isFinite && c.isFinite && d.isFinite,
            "Transform linear part (\(a), \(b), \(c), \(d)) is not finite"
        )
        precondition(
            tx.isFinite && ty.isFinite,
            "Transform translation (\(tx), \(ty)) is not finite"
        )
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    /// Makes a transform that scales by `scale` and then translates by `translation`.
    public init(scale: Double, translation: Vector) {
        self.init(a: scale, b: 0, c: 0, d: scale, tx: translation.dx, ty: translation.dy)
    }

    /// The determinant of the linear part. Zero means that the transform has no inverse.
    public var determinant: Double { a * d - b * c }

    /// Returns the image of a point.
    public func apply(to point: Point) -> Point {
        Point(x: a * point.x + c * point.y + tx, y: b * point.x + d * point.y + ty)
    }

    /// Returns the transform that applies `self` first and `next` second.
    public func then(_ next: Transform) -> Transform {
        let result = Transform(
            a: a * next.a + b * next.c,
            b: a * next.b + b * next.d,
            c: c * next.a + d * next.c,
            d: c * next.b + d * next.d,
            tx: tx * next.a + ty * next.c + next.tx,
            ty: tx * next.b + ty * next.d + next.ty
        )
        let expected = determinant * next.determinant
        assert(result.determinant.isFinite, "Product of \(self) and \(next) is not finite")
        assert(
            abs(result.determinant - expected) <= 1e-9 * max(1, abs(expected)),
            "Determinant of a product must be the product of the determinants"
        )
        return result
    }

    /// Returns the inverse transform.
    ///
    /// - Precondition: The determinant is not zero.
    /// - Returns: The transform that maps each image back to its point.
    public func inverted() -> Transform {
        let determinant = determinant
        precondition(determinant != 0, "Transform \(self) has no inverse")
        precondition(determinant.isFinite, "Transform \(self) has a determinant that is not finite")
        return Transform(
            a: d / determinant,
            b: -b / determinant,
            c: -c / determinant,
            d: a / determinant,
            tx: (c * ty - d * tx) / determinant,
            ty: (b * tx - a * ty) / determinant
        )
    }
}
