/// The control points of one stroke. A copy of a `Stroke` copies one reference, never the points.
///
/// This is the one reference type of `Model` (ARCH-06, data-model.md 7.4). It holds only `let`
/// properties, so the compiler checks that it is `Sendable`.
public final class InkPoints: Sendable {
    /// The points, in drawing order.
    public let values: [InkPoint]

    /// Makes the point storage.
    ///
    /// The producers check their input first: the pencil converter refuses a sample that is not
    /// finite, and the row reader refuses such a point as a damaged row. The precondition names
    /// the fault for a third producer (review of 2026-10-28, 3.2.17).
    ///
    /// - Precondition: 2 to `Limits.maxPointsPerStroke` points, each with finite coordinates.
    public init(_ values: [InkPoint]) {
        precondition(values.count >= 2, "A stroke needs 2 points, got \(values.count)")
        precondition(
            values.count <= Limits.maxPointsPerStroke,
            "A stroke holds at most \(Limits.maxPointsPerStroke) points, got \(values.count)"
        )
        precondition(
            values.allSatisfy { $0.x.isFinite && $0.y.isFinite },
            "A stroke point is not finite"
        )
        self.values = values
    }

    /// The number of points.
    public var count: Int { values.count }
}
