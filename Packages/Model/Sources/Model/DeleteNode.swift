/// Deletes a text box (architecture.md sections 7 and 8, D-86, D-89). Cards join in M6.
///
/// A delete leaves a tombstone, so the undo only clears the flag (data-model.md section 5).
public struct DeleteNode: CanvasCommand {
    /// The text box before the delete.
    public let textBox: TextBox
    /// The code points of the text, counted as points of the history budget (D-88).
    public let heldPointCount: Int

    /// Makes the command.
    ///
    /// - Precondition: `textBox` is not a tombstone.
    public init(textBox: TextBox) {
        precondition(!textBox.meta.isDeleted, "DeleteNode needs a live text box")
        self.textBox = textBox
        heldPointCount = TextLength.of(textBox.text)
    }

    /// Holds no stroke.
    public func forEachHeldStroke(_ body: (StrokeID) -> Void) {}

    /// Makes the box a tombstone.
    ///
    /// - Throws: `CommandError.textBoxNotLive` if the box is not live.
    /// - Returns: The row of the tombstone.
    public func apply(
        to content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        let row = try content.bury(textBox.id, at: clock.now())
        assert(content.textBoxes[textBox.id] == nil, "The box left the live content")
        return [row]
    }

    /// Makes the box live again.
    ///
    /// - Throws: `CommandError.textBoxAlreadyLive` if the box is live, or
    ///   `CommandError.nodeLimitReached` at the node limit.
    /// - Returns: The row of the live box.
    public func revert(
        on content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        precondition(textBox.canvasID == content.canvasID, "The box belongs to the canvas")
        return [try content.revive(textBox, at: clock.now())]
    }
}
