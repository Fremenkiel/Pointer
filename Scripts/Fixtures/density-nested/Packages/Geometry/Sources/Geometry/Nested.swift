/// A fixture with an outer function whose only check sits in a nested function. The nested
/// function counts once, as a function of its own (D-173), so the outer function fails.
public enum Nested {
    /// Sums the values with a nested helper.
    public static func sum(_ values: [Int]) -> Int {
        func checked(_ value: Int) -> Int {
            precondition(value >= 0, "value is negative: \(value)")
            return value
        }
        var total = 0
        for value in values { total += checked(value) }
        let doubled = total * 2
        let half = doubled / 2
        let same = half == total
        let offset = same ? 0 : 1
        let result = total + offset
        let check = result - offset
        let final = check + 0
        let answer = final * 1
        return answer
    }
}
