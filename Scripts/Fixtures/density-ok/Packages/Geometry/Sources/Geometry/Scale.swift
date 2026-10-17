/// A fixture with one long function and three contract checks: average 3.0.
public enum Scale {
    /// The error of the fixture.
    public enum ScaleError: Error { case notFinite }

    /// Scales a value.
    public static func scaled(_ value: Double, by factor: Double) throws -> Double {
        precondition(factor > 0, "factor must be positive, got \(factor)")
        guard value.isFinite else {
            throw ScaleError.notFinite
        }
        let result = value * factor
        assert(result.isFinite, "result \(result) is not finite")
        return result
    }

    /// A short function does not count.
    public static func identity(_ value: Double) -> Double { value }
}
