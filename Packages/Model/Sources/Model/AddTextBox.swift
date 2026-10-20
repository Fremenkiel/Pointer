/// Adds a new text box with its text (architecture.md sections 7 and 8, D-86).
///
/// The end of the edit of a new box with text records this command. The undo makes the box a
/// tombstone, and a redo makes it live again.
public struct AddTextBox: CanvasCommand {
    /// The new text box.
    public let textBox: TextBox
    /// The code points of the text, counted as points of the history budget (D-88).
    public let heldPointCount: Int

    /// Makes the command.
    ///
    /// - Precondition: `textBox` is not a tombstone.
    public init(textBox: TextBox) {
        precondition(!textBox.meta.isDeleted, "AddTextBox needs a live text box")
        self.textBox = textBox
        heldPointCount = TextLength.of(textBox.text)
    }

    /// Holds no stroke.
    public func forEachHeldStroke(_ body: (StrokeID) -> Void) {}

    /// Adds the box, or makes it live again after an undo.
    ///
    /// - Throws: `CommandError.textBoxAlreadyLive` if the box is live, or
    ///   `CommandError.nodeLimitReached` at the node limit.
    /// - Returns: The row of the live box.
    public func apply(
        to content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        precondition(textBox.canvasID == content.canvasID, "The box belongs to the canvas")
        return [try content.revive(textBox, at: clock.now())]
    }

    /// Makes the box a tombstone.
    ///
    /// - Throws: `CommandError.textBoxNotLive` if the box is not live.
    /// - Returns: The row of the tombstone.
    public func revert(
        on content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        let row = try content.bury(textBox.id, at: clock.now())
        assert(content.textBoxes[textBox.id] == nil, "The box left the live content")
        return [row]
    }
}
