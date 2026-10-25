/// A node on a canvas: a text box or a card (D-103).
///
/// `MoveNode` and `DeleteNode` hold a node, so one command type covers both kinds.
public enum CanvasNode: Hashable, Sendable {
    /// A text box.
    case textBox(TextBox)
    /// A card.
    case card(Card)

    /// The bytes of the text or the title, the cost of the node in the history budget (D-88,
    /// D-183). A card without a title counts the fixed bytes of an item.
    var heldByteCount: Int {
        switch self {
        case .textBox(let box): HistoryCost.bytes(ofText: box.text)
        case .card(let card): HistoryCost.bytes(ofText: card.title)
        }
    }

    /// The tombstone flag of the node.
    public var isDeleted: Bool {
        switch self {
        case .textBox(let box): box.meta.isDeleted
        case .card(let card): card.meta.isDeleted
        }
    }

    /// The canvas that holds the node.
    public var canvasID: CanvasID {
        switch self {
        case .textBox(let box): box.canvasID
        case .card(let card): card.canvasID
        }
    }
}
