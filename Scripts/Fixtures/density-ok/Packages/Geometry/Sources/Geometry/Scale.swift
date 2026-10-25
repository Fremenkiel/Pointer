/// A fixture with one function of 11 code lines and three contract checks.
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
        let half = result / 2
        let doubled = half * 2
        let rest = result - doubled
        let unused = rest * 0
        return result + rest
    }

    /// A short function does not count.
    public static func identity(_ value: Double) -> Double { value }
}
