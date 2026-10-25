/// Deletes a text box or a card (architecture.md sections 7 and 8, D-86, D-89, D-103).
///
/// A delete leaves a tombstone, so the undo only clears the flag (data-model.md section 5). A
/// delete of a card marks the card only, and its child content stays (D-18).
public struct DeleteNode: CanvasCommand {
    /// The node before the delete.
    public let node: CanvasNode
    /// The bytes of the text or the title (D-88, D-183).
    public let heldByteCount: Int

    /// Makes the command for a text box.
    ///
    /// - Precondition: `textBox` is not a tombstone.
    public init(textBox: TextBox) {
        self.init(node: .textBox(textBox))
    }

    /// Makes the command for a card.
    ///
    /// - Precondition: `card` is not a tombstone.
    public init(card: Card) {
        self.init(node: .card(card))
    }

    private init(node: CanvasNode) {
        precondition(!node.isDeleted, "DeleteNode needs a live node")
        self.node = node
        heldByteCount = node.heldByteCount
    }

    /// Holds no stroke.
    public func forEachHeldStroke(_ body: (StrokeID) -> Void) {}

    /// Makes the node a tombstone.
    ///
    /// - Throws: `CommandError.textBoxNotLive` or `CommandError.cardNotLive` if the node is not
    ///   live.
    /// - Returns: The row of the tombstone.
    public func apply(
        to content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        let time = clock.now()
        switch node {
        case .textBox(let box):
            let row = try content.bury(box.id, at: time)
            assert(content.textBoxes[box.id] == nil, "The box left the live content")
            return [row]
        case .card(let card):
            let row = try content.bury(card.id, at: time)
            assert(content.cards[card.id] == nil, "The card left the live content")
            return [row]
        }
    }

    /// Makes the node live again.
    ///
    /// - Throws: `CommandError.textBoxAlreadyLive` or `CommandError.cardAlreadyLive` if the node
    ///   is live, or `CommandError.nodeLimitReached` at the node limit.
    /// - Returns: The row of the live node.
    public func revert(
        on content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        precondition(node.canvasID == content.canvasID, "The node belongs to the canvas")
        let time = clock.now()
        switch node {
        case .textBox(let box): return [try content.revive(box, at: time)]
        case .card(let card): return [try content.revive(card, at: time)]
        }
    }
}
