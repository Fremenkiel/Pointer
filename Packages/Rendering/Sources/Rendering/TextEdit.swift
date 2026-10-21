import Model

/// One change of the text boxes that the main actor sends to the render thread: an add, an edit,
/// a move, a delete, or the hide of a box under the edit view (architecture.md 5.4).
struct TextEdit: Sendable {
    /// The text boxes to remove.
    let removed: [TextBoxID]
    /// The text boxes to add, or to put in the place of the box with the same ID.
    let added: [TextBox]
}
