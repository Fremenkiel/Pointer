/// Moves a text box or a card (architecture.md section 8, CARD-07, D-10, D-103).
///
/// One drag records one `MoveNode`.
public struct MoveNode: CanvasCommand {
    /// The node before the move.
    public let from: CanvasNode
    /// The node after the move.
    public let to: CanvasNode
    /// The bytes of the text or the title (D-88, D-183). Both values share one text.
    public let heldByteCount: Int

    /// Makes the command for a text box.
    ///
    /// - Precondition: Both boxes have the same ID and text, and neither is a tombstone.
    public init(from: TextBox, to: TextBox) {
        precondition(from.id == to.id, "MoveNode moves one text box")
        precondition(from.text == to.text, "MoveNode keeps the text")
        self.init(nodes: .textBox(from), .textBox(to))
    }

    /// Makes the command for a card.
    ///
    /// - Precondition: Both cards have the same ID, title, and size, and neither is a tombstone.
    public init(from: Card, to: Card) {
        precondition(from.id == to.id, "MoveNode moves one card")
        precondition(from.title == to.title, "MoveNode keeps the title")
        precondition(from.frame.size == to.frame.size, "MoveNode keeps the size of card \(to.id)")
        self.init(nodes: .card(from), .card(to))
    }

    private init(nodes from: CanvasNode, _ to: CanvasNode) {
        precondition(!from.isDeleted && !to.isDeleted, "MoveNode needs live nodes")
        self.from = from
        self.to = to
        heldByteCount = from.heldByteCount
    }

    /// Holds no stroke.
    public func forEachHeldStroke(_ body: (StrokeID) -> Void) {}

    /// Puts the node at its new place.
    ///
    /// - Throws: `CommandError.textBoxNotLive` or `CommandError.cardNotLive` if the node is not
    ///   live.
    /// - Returns: The row of the moved node.
    public func apply(
        to content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        let row = try Self.change(&content, to: to, at: clock.now())
        assert(Self.isLive(to, in: content), "The node is at its new place")
        return [row]
    }

    /// Puts the node back at its old place.
    ///
    /// - Throws: `CommandError.textBoxNotLive` or `CommandError.cardNotLive` if the node is not
    ///   live.
    /// - Returns: The row of the moved node.
    public func revert(
        on content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        let row = try Self.change(&content, to: from, at: clock.now())
        assert(Self.isLive(from, in: content), "The node is at its old place")
        return [row]
    }

    private static func change(
        _ content: inout CanvasContent,
        to node: CanvasNode,
        at time: HybridTimestamp
    ) throws(CommandError) -> LibraryChange {
        switch node {
        case .textBox(let box): try content.change(to: box, at: time)
        case .card(let card): try content.change(to: card, at: time)
        }
    }

    private static func isLive(_ node: CanvasNode, in content: CanvasContent) -> Bool {
        switch node {
        case .textBox(let box): content.textBoxes[box.id]?.origin == box.origin
        case .card(let card): content.cards[card.id]?.frame == card.frame
        }
    }
}
