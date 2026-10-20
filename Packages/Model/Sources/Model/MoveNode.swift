/// Moves a text box (architecture.md section 8, CARD-07, D-10). Cards join in M6.
///
/// One drag records one `MoveNode`.
public struct MoveNode: CanvasCommand {
    /// The box before the move.
    public let from: TextBox
    /// The box after the move.
    public let to: TextBox
    /// The code points of the text, counted as points of the history budget (D-88). Both
    /// values share one text.
    public let heldPointCount: Int

    /// Makes the command.
    ///
    /// - Precondition: Both boxes have the same ID and text, and neither is a tombstone.
    public init(from: TextBox, to: TextBox) {
        precondition(from.id == to.id, "MoveNode moves one text box")
        precondition(from.text == to.text, "MoveNode keeps the text")
        precondition(!from.meta.isDeleted && !to.meta.isDeleted, "MoveNode needs live boxes")
        self.from = from
        self.to = to
        heldPointCount = TextLength.of(from.text)
    }

    /// Holds no stroke.
    public func forEachHeldStroke(_ body: (StrokeID) -> Void) {}

    /// Puts the box at its new origin.
    ///
    /// - Throws: `CommandError.textBoxNotLive` if the box is not live.
    /// - Returns: The row of the moved box.
    public func apply(
        to content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        let row = try content.change(to: to, at: clock.now())
        assert(content.textBoxes[to.id]?.origin == to.origin, "The box is at its new origin")
        return [row]
    }

    /// Puts the box back at its old origin.
    ///
    /// - Throws: `CommandError.textBoxNotLive` if the box is not live.
    /// - Returns: The row of the moved box.
    public func revert(
        on content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        let row = try content.change(to: from, at: clock.now())
        assert(content.textBoxes[from.id]?.origin == from.origin, "The box is at its old origin")
        return [row]
    }
}
