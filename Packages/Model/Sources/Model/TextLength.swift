/// The length rule of titles and texts: Unicode code points, as SQLite `length()` counts (D-57).
///
/// SQLite `length()` stops at the first U+0000, so titles and texts must not hold it. Then the
/// count of Swift always equals the count of the `CHECK` constraints.
enum TextLength {
    /// Returns the number of Unicode code points of `text`.
    static func of(_ text: String) -> Int {
        text.unicodeScalars.count
    }

    /// Returns true if `text` holds U+0000.
    static func hasNull(_ text: String) -> Bool {
        text.unicodeScalars.contains("\u{0}")
    }
}
