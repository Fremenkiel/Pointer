/// The control points of one stroke. A copy of a `Stroke` copies one reference, never the points.
///
/// This is the one reference type of `Model` (ARCH-06, data-model.md 7.4). It holds only `let`
/// properties, so the compiler checks that it is `Sendable`.
public final class InkPoints: Sendable {
    /// The points, in drawing order.
    public let values: [InkPoint]

    /// Makes the point storage.
    ///
    /// - Precondition: 2 to `Limits.maxPointsPerStroke` points.
    public init(_ values: [InkPoint]) {
        precondition(values.count >= 2, "A stroke needs 2 points, got \(values.count)")
        precondition(
            values.count <= Limits.maxPointsPerStroke,
            "A stroke holds at most \(Limits.maxPointsPerStroke) points, got \(values.count)"
        )
        self.values = values
    }

    /// The number of points.
    public var count: Int { values.count }
}
