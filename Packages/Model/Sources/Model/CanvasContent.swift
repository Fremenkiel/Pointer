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
    /// The load of a canvas passes `Limits.maxStrokesAfterErase`, because an erase can pass the
    /// stroke limit (D-73).
    ///
    /// - Precondition: The stroke belongs to this canvas, its ID is new, and the limit is at most
    ///   `Limits.maxStrokesAfterErase`.
    /// - Throws: `ModelError.strokeLimitReached` if the canvas holds `limit` strokes.
    public mutating func add(
        _ stroke: Stroke,
        limit: Int = Limits.maxStrokesPerCanvas
    ) throws(ModelError) {
        precondition(stroke.canvasID == canvasID, "Stroke \(stroke.id) belongs to another canvas")
        precondition(strokes[stroke.id] == nil, "Canvas already holds stroke \(stroke.id)")
        precondition(limit <= Limits.maxStrokesAfterErase, "Stroke limit \(limit) is too large")
        guard strokes.count < limit else { throw .strokeLimitReached }
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

    /// Takes the erase records of the session back after a new load of the canvas, so that an
    /// undo after a workspace switch finds them (D-12).
    ///
    /// The library loads no erased stroke, so a stroke with a live record is not in `strokes`,
    /// and a stroke with a tombstone is. A record that does not fit the loaded strokes is skipped:
    /// the history step of its stroke then fails with a `CommandError`.
    ///
    /// - Precondition: The content holds no erase record yet.
    /// - Returns: The number of skipped records.
    public mutating func adoptSessionRecords(_ records: [StrokeID: EraseRecord]) -> Int {
        precondition(erased.isEmpty, "The content already holds erase records")
        var skipped = 0
        for (id, record) in records {
            guard record.strokeID == id, record.isDeleted == (strokes[id] != nil) else {
                skipped += 1
                continue
            }
            erased[id] = record
        }
        assert(erased.count + skipped == records.count, "Each record is taken or skipped")
        return skipped
    }
}
