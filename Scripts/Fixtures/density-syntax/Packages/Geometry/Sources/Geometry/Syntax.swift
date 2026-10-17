/// A fixture with three counted functions and four contract checks: average 1.33.
///
/// The old blanker skipped the nested generic clause, and the quote in the regex literal hid
/// the rest of the file. Checks in comments and strings do not count.
public enum Syntax {
    /// Has a nested generic clause and two checks.
    public static func total<T: Collection<Int>>(_ values: T) -> Int {
        precondition(!values.isEmpty, "values is empty")
        precondition(values.count < 100, "values has \(values.count) items")
        let first = values.first ?? 0
        let last = values.reversed().first ?? 0
        let sum = first + last
        return sum
    }

    /// Has a regex literal with a quote and no real checks.
    public static func quoted(_ text: String) -> Bool {
        let pattern = /"[a-z]+/
        // precondition(text.isEmpty, "a comment does not count")
        let note = "assert(false) in a string does not count"
        let hasNote = !note.isEmpty
        let hasMatch = text.contains(pattern)
        return hasNote && hasMatch
    }

    /// Has two checks after the regex literal.
    public static func half(_ value: Int) -> Int {
        precondition(value >= 0, "value is negative: \(value)")
        let result = value / 2
        assert(result <= value, "result \(result) is above \(value)")
        let doubled = result * 2
        let rest = value - doubled
        return result + rest - rest
    }
}
