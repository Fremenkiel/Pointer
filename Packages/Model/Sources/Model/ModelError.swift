/// The errors of the Model package.
public enum ModelError: Error, Equatable, Sendable {
    /// The canvas holds `Limits.maxStrokesPerCanvas` strokes.
    case strokeLimitReached
    /// The canvas holds `Limits.maxNodesPerCanvas` cards and text boxes.
    case nodeLimitReached
    /// The library holds `Limits.maxWorkspaces` workspaces.
    case workspaceLimitReached
    /// A pen path has no control points.
    case emptyPath
    /// A pen path has a point, a time, or a width that is not a finite number.
    case invalidPath(reason: String)
    /// A title has a length in Unicode code points outside its range (D-57).
    case invalidTitle(length: Int)
    /// A title or a text holds U+0000, which SQLite `length()` does not count (D-57).
    case nullCharacter
    /// A text has a length in Unicode code points outside `1...Limits.maxTextLength` (D-57).
    case invalidText(length: Int)
    /// A position or a frame is not finite, or a card is smaller than the card minimum.
    case invalidGeometry(reason: String)
    /// A card names its own child canvas as its parent.
    case cardIsOwnCanvas
    /// A sort key is empty, too long, has a character outside base 62, or ends with "0".
    case invalidSortKey(reason: String)
    /// No key fits between two keys within `Limits.maxSortKeyLength` (data-model.md section 6).
    case sortKeyNeedsRebalance
    /// A navigation path has more than `Limits.maxDepth` cards.
    case navigationPathTooLong(count: Int)
    /// The library has a newer schema than the app knows, so it opens read-only.
    case libraryIsReadOnly
    /// The storage failed. The reason holds the storage message, never user content.
    case storageFailed(reason: String)
}
