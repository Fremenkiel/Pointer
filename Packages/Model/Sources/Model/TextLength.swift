/// The length rule of titles and texts: Unicode code points, as SQLite `length()` counts (D-57).
enum TextLength {
    /// Returns the number of Unicode code points of `text`.
    static func of(_ text: String) -> Int {
        text.unicodeScalars.count
    }
}
