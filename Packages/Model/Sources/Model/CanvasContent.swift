/// The content of one canvas in memory (data-model.md section 8).
///
/// Only the canvas controller holds it (review A-03). `strokes` holds the live strokes only. An
/// erase, or an undo of an added stroke, moves a stroke out of `strokes` and gives it a live erase
/// record of the session (D-68).
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

    /// Removes a live stroke and gives it a live erase record of the session (D-68).
    ///
    /// A stroke that the session erased before keeps the time of its first erase, because the
    /// stored row keeps it too (storage.md 3.3).
    ///
    /// - Precondition: The canvas holds the stroke as a live stroke.
    /// - Returns: The new or changed erase record.
    public mutating func remove(_ id: StrokeID, at time: HybridTimestamp) -> EraseRecord {
        precondition(strokes[id] != nil, "Canvas holds no live stroke \(id)")
        let earlier = erased[id]
        assert(earlier?.isDeleted ?? true, "Stroke \(id) is live and has a live erase record")
        strokes[id] = nil
        let record = EraseRecord(
            strokeID: id,
            erased: earlier?.erased ?? time,
            modified: time,
            isDeleted: false
        )
        erased[id] = record
        return record
    }

    /// Puts a stroke back into the live strokes, or adds a new one, and turns its erase record of
    /// the session into a tombstone (data-model.md 7.5).
    ///
    /// Only the parts of an erase can go past `Limits.maxStrokesPerCanvas`, because an erase never
    /// fails (D-71). Their callers pass `ignoringLimit`.
    ///
    /// - Precondition: The stroke belongs to this canvas and is not live.
    /// - Throws: `ModelError.strokeLimitReached` at the limit, unless `ignoringLimit` is true.
    /// - Returns: The tombstone, or `nil` if the session holds no erase record of the stroke.
    public mutating func restore(
        _ stroke: Stroke,
        at time: HybridTimestamp,
        ignoringLimit: Bool
    ) throws(ModelError) -> EraseRecord? {
        precondition(stroke.canvasID == canvasID, "Stroke \(stroke.id) belongs to another canvas")
        precondition(strokes[stroke.id] == nil, "Canvas already holds stroke \(stroke.id)")
        guard ignoringLimit || strokes.count < Limits.maxStrokesPerCanvas else {
            throw .strokeLimitReached
        }
        strokes[stroke.id] = stroke
        guard let earlier = erased[stroke.id] else { return nil }
        let tombstone = EraseRecord(
            strokeID: stroke.id,
            erased: earlier.erased,
            modified: time,
            isDeleted: true
        )
        erased[stroke.id] = tombstone
        return tombstone
    }
}
