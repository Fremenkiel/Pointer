/// The content of one canvas in memory (data-model.md section 8).
///
/// Only the canvas controller holds it (review A-03). Cards and text boxes get no UI in M3 (D-50),
/// and erase records come with the eraser in M4.
public struct CanvasContent: Sendable {
    /// The canvas that the content belongs to.
    public let canvasID: CanvasID
    /// The live strokes by ID.
    public private(set) var strokes: [StrokeID: Stroke] = [:]
    /// The erase records of the current session by stroke ID.
    public private(set) var erased: [StrokeID: EraseRecord] = [:]
    /// The live cards by ID.
    public private(set) var cards: [CardID: Card] = [:]
    /// The live text boxes by ID.
    public private(set) var textBoxes: [TextBoxID: TextBox] = [:]

    /// Makes empty content.
    public init(canvasID: CanvasID) {
        self.canvasID = canvasID
    }

    /// The number of cards plus text boxes.
    public var nodeCount: Int { cards.count + textBoxes.count }

    /// Adds a stroke.
    ///
    /// - Precondition: The stroke belongs to this canvas, and its ID is new.
    /// - Throws: `ModelError.strokeLimitReached` if the canvas holds `Limits.maxStrokesPerCanvas`.
    public mutating func add(_ stroke: Stroke) throws(ModelError) {
        precondition(stroke.canvasID == canvasID, "Stroke \(stroke.id) belongs to another canvas")
        precondition(strokes[stroke.id] == nil, "Canvas already holds stroke \(stroke.id)")
        guard strokes.count < Limits.maxStrokesPerCanvas else { throw .strokeLimitReached }
        strokes[stroke.id] = stroke
    }

    /// Adds a card.
    ///
    /// - Precondition: The card belongs to this canvas, and its ID is new.
    /// - Throws: `ModelError.nodeLimitReached` if the canvas holds `Limits.maxNodesPerCanvas`.
    public mutating func add(_ card: Card) throws(ModelError) {
        precondition(card.canvasID == canvasID, "Card \(card.id) belongs to another canvas")
        precondition(cards[card.id] == nil, "Canvas already holds card \(card.id)")
        guard nodeCount < Limits.maxNodesPerCanvas else { throw .nodeLimitReached }
        cards[card.id] = card
    }

    /// Adds a text box.
    ///
    /// - Precondition: The text box belongs to this canvas, and its ID is new.
    /// - Throws: `ModelError.nodeLimitReached` if the canvas holds `Limits.maxNodesPerCanvas`.
    public mutating func add(_ textBox: TextBox) throws(ModelError) {
        precondition(
            textBox.canvasID == canvasID,
            "Text box \(textBox.id) belongs to another canvas"
        )
        precondition(textBoxes[textBox.id] == nil, "Canvas already holds text box \(textBox.id)")
        guard nodeCount < Limits.maxNodesPerCanvas else { throw .nodeLimitReached }
        textBoxes[textBox.id] = textBox
    }
}
