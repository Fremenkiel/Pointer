/// A fixture with one function of 11 code lines whose checks are all in comments and strings.
/// The lines of the multi-line string count as code, and the blank line does not (D-176).
public enum Scale {
    /// Scales a value.
    public static func scaled(_ value: Double, by factor: Double) -> Double {
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
        let unused = size * 2
        let more = unused + 1
        return doubled + Double(size + more) * 0
    }
}
