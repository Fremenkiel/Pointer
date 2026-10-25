/// A node on a canvas: a text box or a card (D-103).
///
/// `MoveNode` and `DeleteNode` hold a node, so one command type covers both kinds.
public enum CanvasNode: Hashable, Sendable {
    /// A text box.
    case textBox(TextBox)
    /// A card.
    case card(Card)

    /// The code points of the text or the title, the cost of the node in the history budget
    /// (D-88). A card without a title counts 0.
    var textLength: Int {
        switch self {
        case .textBox(let box): TextLength.of(box.text)
        case .card(let card): card.title.map(TextLength.of) ?? 0
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
