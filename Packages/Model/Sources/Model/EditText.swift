/// Changes the text of a text box (architecture.md sections 7 and 8, D-86).
///
/// The end of an edit that changed the text of a box records one `EditText`.
public struct EditText: CanvasCommand {
    /// The box before the edit.
    public let old: TextBox
    /// The box after the edit.
    public let new: TextBox
    /// The code points of both texts, counted as points of the history budget (D-88).
    public let heldPointCount: Int

    /// Makes the command.
    ///
    /// - Precondition: Both boxes have the same ID and origin, and neither is a tombstone.
    public init(old: TextBox, new: TextBox) {
        precondition(old.id == new.id, "EditText changes one text box")
        precondition(old.origin == new.origin, "EditText keeps the origin")
        precondition(!old.meta.isDeleted && !new.meta.isDeleted, "EditText needs live boxes")
        self.old = old
        self.new = new
        heldPointCount = TextLength.of(old.text) + TextLength.of(new.text)
    }

    /// Holds no stroke.
    public func forEachHeldStroke(_ body: (StrokeID) -> Void) {}

    /// Sets the new text.
    ///
    /// - Throws: `CommandError.textBoxNotLive` if the box is not live.
    /// - Returns: The row of the changed box.
    public func apply(
        to content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        let row = try content.change(to: new, at: clock.now())
        assert(content.textBoxes[new.id]?.text == new.text, "The box holds the new text")
        return [row]
    }

    /// Sets the old text.
    ///
    /// - Throws: `CommandError.textBoxNotLive` if the box is not live.
    /// - Returns: The row of the changed box.
    public func revert(
        on content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        let row = try content.change(to: old, at: clock.now())
        assert(content.textBoxes[old.id]?.text == old.text, "The box holds the old text")
        return [row]
    }
}
