/// Changes the title of a card (architecture.md section 8, CARD-08, D-103).
///
/// The "Rename" alert records one `RenameCard` when the title changed. A title of 0 code points
/// is stored as `nil` (`Card.retitling(_:at:)`).
public struct RenameCard: CanvasCommand {
    /// The card before the rename.
    public let old: Card
    /// The card after the rename.
    public let new: Card
    /// The bytes of both titles (D-88, D-183).
    public let heldByteCount: Int

    /// Makes the command.
    ///
    /// - Precondition: Both cards have the same ID and frame, neither is a tombstone, and the
    ///   new title is not empty.
    public init(old: Card, new: Card) {
        precondition(old.id == new.id, "RenameCard changes one card")
        precondition(old.frame == new.frame, "RenameCard keeps the frame of card \(new.id)")
        precondition(!old.meta.isDeleted && !new.meta.isDeleted, "RenameCard needs live cards")
        precondition(new.title?.isEmpty != true, "RenameCard stores an empty title as nil")
        self.old = old
        self.new = new
        heldByteCount = CanvasNode.card(old).heldByteCount + CanvasNode.card(new).heldByteCount
    }

    /// Holds no stroke.
    public func forEachHeldStroke(_ body: (StrokeID) -> Void) {}

    /// Sets the new title.
    ///
    /// - Throws: `CommandError.cardNotLive` if the card is not live.
    /// - Returns: The row of the changed card.
    public func apply(
        to content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        let row = try content.change(to: new, at: clock.now())
        assert(content.cards[new.id]?.title == new.title, "The card holds the new title")
        return [row]
    }

    /// Sets the old title.
    ///
    /// - Throws: `CommandError.cardNotLive` if the card is not live.
    /// - Returns: The row of the changed card.
    public func revert(
        on content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        let row = try content.change(to: old, at: clock.now())
        assert(content.cards[old.id]?.title == old.title, "The card holds the old title")
        return [row]
    }
}
