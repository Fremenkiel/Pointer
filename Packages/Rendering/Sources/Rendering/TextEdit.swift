import Model

/// One change of the text boxes that the main actor sends to the render thread: an add, an edit,
/// a move, a delete, or the hide of a box under the edit view (architecture.md 5.4).
enum TextEdit: Sendable {
    /// Removes the boxes of `removed`, then adds the boxes of `added`. An added box takes the
    /// place of the box with the same ID.
    case change(removed: [TextBoxID], added: [TextBox])
    /// Puts one box in the place of the box with the same ID, or adds it. A drag step posts
    /// it without an array (PERF-01, m10-plan.md task 3.1).
    case place(TextBox)
}
