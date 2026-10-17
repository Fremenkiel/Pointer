/// A fixture with one long function and one contract check: average 1.0.
public enum Scale {
    /// Scales a value.
    public static func scaled(_ value: Double, by factor: Double) -> Double {
        precondition(factor > 0, "factor must be positive, got \(factor)")
        // A comment with precondition( and assert( does not count.
        /* A block comment with assert( does not count. /* Nested. */ */
        let note = "assert(false) in a string does not count"
        let nested = "\(note.isEmpty ? "precondition(" : "x") assert("
        let raw = #"raw "assert(" \#(note)"#
        let block = """
            assert(true)
            """
        let doubled = value * factor
        let size = note.count + nested.count + raw.count + block.count
        return doubled + Double(size) * 0
    }
}
