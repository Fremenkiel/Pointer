/// Adds a new card (architecture.md section 8, CARD-01, D-103).
///
/// "New card" records this command. The undo makes the card a tombstone, and a redo makes it
/// live again.
public struct AddCard: CanvasCommand {
    /// The new card.
    public let card: Card
    /// The code points of the title, counted as points of the history budget (D-88).
    public let heldPointCount: Int

    /// Makes the command.
    ///
    /// - Precondition: `card` is not a tombstone.
    public init(card: Card) {
        precondition(!card.meta.isDeleted, "AddCard needs a live card")
        self.card = card
        heldPointCount = CanvasNode.card(card).textLength
    }

    /// Holds no stroke.
    public func forEachHeldStroke(_ body: (StrokeID) -> Void) {}

    /// Adds the card, or makes it live again after an undo.
    ///
    /// - Throws: `CommandError.cardAlreadyLive` if the card is live, or
    ///   `CommandError.nodeLimitReached` at the node limit.
    /// - Returns: The row of the live card.
    public func apply(
        to content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        precondition(card.canvasID == content.canvasID, "The card belongs to the canvas")
        return [try content.revive(card, at: clock.now())]
    }

    /// Makes the card a tombstone.
    ///
    /// - Throws: `CommandError.cardNotLive` if the card is not live.
    /// - Returns: The row of the tombstone.
    public func revert(
        on content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        let row = try content.bury(card.id, at: clock.now())
        assert(content.cards[card.id] == nil, "The card left the live content")
        return [row]
    }
}
