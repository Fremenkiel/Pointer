import Model

/// The changed rows that wait for the next save (storage.md section 4).
///
/// A later change of the same row replaces the earlier one, so a save writes each row once.
struct PendingRows {
    private(set) var strokes: [StrokeID: Stroke] = [:]
    private(set) var erases: [StrokeID: EraseRecord] = [:]
    private(set) var cards: [CardID: Card] = [:]
    private(set) var textBoxes: [TextBoxID: TextBox] = [:]
    /// The largest clock value of the pending rows.
    private(set) var latest: HybridTimestamp?

    /// True if no row waits.
    var isEmpty: Bool { count == 0 }

    /// The number of waiting rows.
    var count: Int { strokes.count + erases.count + cards.count + textBoxes.count }

    /// Adds a changed row.
    mutating func add(_ change: LibraryChange) {
        switch change {
        case .stroke(let stroke):
            strokes[stroke.id] = stroke
            note(stroke.created)
        case .erase(let record):
            erases[record.strokeID] = record
            note(max(record.erased, record.modified))
        case .card(let card):
            cards[card.id] = card
            note(card.meta.modified)
        case .textBox(let textBox):
            textBoxes[textBox.id] = textBox
            note(textBox.meta.modified)
        }
        assert(!isEmpty, "A row was added, so the set is not empty")
        assert(latest != nil, "A row was added, so the set has a latest clock value")
    }

    private mutating func note(_ timestamp: HybridTimestamp) {
        latest = latest.map { max($0, timestamp) } ?? timestamp
    }
}
