/// A fault of the library that the app shows to the user (storage.md sections 4 and 9).
public enum LibraryFault: Equatable, Sendable {
    /// The saves failed `count` times in a row. The app stops new edits until a save works.
    case savesFailing(count: Int, reason: String)
    /// A save worked after a run of failed saves. The app allows edits again.
    case savesRecovered
    /// Rows of `table` did not load. The other rows of the canvas loaded.
    case rowsSkipped(table: String, count: Int)
}
