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
    public internal(set) var cards: [CardID: Card] = [:]
    /// The live text boxes by ID.
    public private(set) var textBoxes: [TextBoxID: TextBox] = [:]

    /// Makes empty content.
    public init(canvasID: CanvasID) {
        self.canvasID = canvasID
    }

    /// The number of cards plus text boxes.
    public var nodeCount: Int { cards.count + textBoxes.count }

    /// Reserves room for the rows of a load, so that each table grows once (PERF-01,
    /// m10-plan.md task 3.6). A count past a limit of the canvas reserves the limit.
    ///
    /// - Precondition: The counts are not negative.
    public mutating func reserveCapacity(strokes: Int, cards: Int, textBoxes: Int) {
        precondition(strokes >= 0 && cards >= 0 && textBoxes >= 0, "A negative reserve")
        self.strokes.reserveCapacity(min(strokes, Limits.maxStrokesAfterErase))
        self.cards.reserveCapacity(min(cards, Limits.maxNodesPerCanvas))
        self.textBoxes.reserveCapacity(min(textBoxes, Limits.maxNodesPerCanvas))
    }

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
        // One lookup per dictionary: a lookup costs about 1 µs on the iPad at 20,000 strokes, and
        // an erase of 1,000 strokes makes 3,000 of these calls (M4 task 3.8).
        let removed = strokes.removeValue(forKey: id)
        precondition(removed != nil, "Canvas holds no live stroke \(id)")
        let record = EraseRecord(strokeID: id, erased: time, modified: time, isDeleted: false)
        guard let earlier = erased.updateValue(record, forKey: id) else { return record }
        assert(earlier.isDeleted, "Stroke \(id) was live and had a live erase record")
        // A stroke that the session erased before keeps the time of its first erase.
        let kept = EraseRecord(
            strokeID: id,
            erased: earlier.erased,
            modified: time,
            isDeleted: false
        )
        erased[id] = kept
        return kept
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
        guard ignoringLimit || strokes.count < Limits.maxStrokesPerCanvas else {
            throw .strokeLimitReached
        }
        let replaced = strokes.updateValue(stroke, forKey: stroke.id)
        precondition(replaced == nil, "Canvas already held stroke \(stroke.id)")
        guard let index = erased.index(forKey: stroke.id) else { return nil }
        let tombstone = EraseRecord(
            strokeID: stroke.id,
            erased: erased.values[index].erased,
            modified: time,
            isDeleted: true
        )
        erased.values[index] = tombstone
        return tombstone
    }

    /// Removes the erase records of the session of strokes that no step of the history holds
    /// any more (D-76). The repository keeps its rows.
    public mutating func forgetRecords(of ids: [StrokeID]) {
        for id in ids {
            erased.removeValue(forKey: id)
        }
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
        // One allocation for all records, not one per growth (P-12).
        erased.reserveCapacity(records.count)
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

/// The changes of a command in batches: each stroke is checked and changed with one lookup, and
/// a failed check takes the changes of the step back (P-07 of docs/m4-fix-plan.md).
extension CanvasContent {
    /// The strokes that a step changed, so that a failed step can take them back.
    struct ChangeLog {
        /// The removed strokes with the erase record that each one had before.
        fileprivate var removed: [(stroke: Stroke, earlier: EraseRecord?)] = []
        /// The restored or added strokes with the erase record that each one had before.
        fileprivate var restored: [(id: StrokeID, earlier: EraseRecord?)] = []

        /// Makes a log with room for `count` strokes.
        init(capacity count: Int) {
            precondition(count >= 0, "A log holds no negative count, got \(count)")
            removed.reserveCapacity(count)
            restored.reserveCapacity(count)
        }
    }

    /// Removes live strokes as `remove(_:at:)` does and adds their erase records to `changes`.
    ///
    /// - Throws: `CommandError.strokeNotLive` if a stroke is not live. The strokes before it are
    ///   in `log`, so `rollBack(_:)` takes them back.
    mutating func remove(
        _ list: [Stroke],
        at time: HybridTimestamp,
        log: inout ChangeLog,
        changes: inout [LibraryChange]
    ) throws(CommandError) {
        for stroke in list {
            guard strokes.removeValue(forKey: stroke.id) != nil else {
                throw .strokeNotLive(stroke.id)
            }
            // A stroke that the session erased before has a tombstone, which changes in place.
            // It keeps the time of its first erase, as `remove(_:at:)` does.
            let index = erased.index(forKey: stroke.id)
            let earlier = index.map { erased.values[$0] }
            assert(earlier?.isDeleted ?? true, "Stroke \(stroke.id) was live with a live record")
            let record = EraseRecord(
                strokeID: stroke.id,
                erased: earlier?.erased ?? time,
                modified: time,
                isDeleted: false
            )
            if let index {
                erased.values[index] = record
            } else {
                erased[stroke.id] = record
            }
            log.removed.append((stroke, earlier))
            changes.append(.erase(record))
        }
    }

    /// Puts strokes back or adds them as `restore(_:at:ignoringLimit:)` does, without a limit
    /// check, and adds their rows to `changes`: a tombstone, or the stroke without a record.
    ///
    /// - Throws: `CommandError.strokeAlreadyLive` if a stroke is live, or
    ///   `CommandError.eraseRecordMissing` if `needsRecords` and a stroke has no erase record.
    ///   The strokes before it are in `log`, so `rollBack(_:)` takes them back.
    mutating func restore(
        _ list: [Stroke],
        at time: HybridTimestamp,
        needsRecords: Bool,
        log: inout ChangeLog,
        changes: inout [LibraryChange]
    ) throws(CommandError) {
        for stroke in list {
            precondition(stroke.canvasID == canvasID, "Stroke \(stroke.id) is of another canvas")
            if let live = strokes.updateValue(stroke, forKey: stroke.id) {
                strokes[stroke.id] = live
                throw .strokeAlreadyLive(stroke.id)
            }
            guard let index = erased.index(forKey: stroke.id) else {
                guard !needsRecords else {
                    strokes.removeValue(forKey: stroke.id)
                    throw .eraseRecordMissing(stroke.id)
                }
                log.restored.append((stroke.id, nil))
                changes.append(.stroke(stroke))
                continue
            }
            let earlier = erased.values[index]
            let tombstone = EraseRecord(
                strokeID: stroke.id,
                erased: earlier.erased,
                modified: time,
                isDeleted: true
            )
            erased.values[index] = tombstone
            log.restored.append((stroke.id, earlier))
            changes.append(.erase(tombstone))
        }
    }

    /// Takes back the changes of a failed step, in the reverse order.
    mutating func rollBack(_ log: ChangeLog) {
        for (id, earlier) in log.restored.reversed() {
            strokes.removeValue(forKey: id)
            erased[id] = earlier
        }
        for (stroke, earlier) in log.removed.reversed() {
            strokes[stroke.id] = stroke
            erased[stroke.id] = earlier
        }
    }
}

/// The changes of the text boxes. `textBoxes` holds the live text boxes only, as `strokes` does
/// (D-68). A command keeps the `TextBox` value of a deleted box for its undo, and `add(_:)` puts
/// it back.
extension CanvasContent {
    /// Puts a changed text box in the place of the live box with the same ID.
    ///
    /// - Precondition: The canvas holds the box as a live box, and `textBox` is not a tombstone.
    /// - Returns: The box before the change.
    public mutating func replace(_ textBox: TextBox) -> TextBox {
        precondition(!textBox.meta.isDeleted, "Text box \(textBox.id) is a tombstone")
        guard let earlier = textBoxes.updateValue(textBox, forKey: textBox.id) else {
            preconditionFailure("Canvas holds no live text box \(textBox.id)")
        }
        assert(earlier.canvasID == textBox.canvasID, "A text box keeps its canvas")
        return earlier
    }

    /// Removes a live text box. The caller sends its tombstone to the library.
    ///
    /// - Precondition: The canvas holds the box as a live box.
    /// - Returns: The removed box.
    public mutating func removeTextBox(_ id: TextBoxID) -> TextBox {
        let removed = textBoxes.removeValue(forKey: id)
        guard let removed else { preconditionFailure("Canvas holds no live text box \(id)") }
        return removed
    }

    /// Puts `textBox` with the change time `time` in the place of its live box, for a command.
    ///
    /// - Throws: `CommandError.textBoxNotLive` if the box is not live.
    /// - Returns: The row of the changed box.
    mutating func change(
        to textBox: TextBox,
        at time: HybridTimestamp
    ) throws(CommandError) -> LibraryChange {
        guard textBoxes[textBox.id] != nil else { throw .textBoxNotLive(textBox.id) }
        let changed = textBox.marking(deleted: false, at: time)
        _ = replace(changed)
        return .textBox(changed)
    }

    /// Puts `textBox` back as a live box with the change time `time`, for a command.
    ///
    /// - Throws: `CommandError.textBoxAlreadyLive` if the box is live, or
    ///   `CommandError.nodeLimitReached` at the node limit.
    /// - Returns: The row of the live box.
    mutating func revive(
        _ textBox: TextBox,
        at time: HybridTimestamp
    ) throws(CommandError) -> LibraryChange {
        guard textBoxes[textBox.id] == nil else { throw .textBoxAlreadyLive(textBox.id) }
        let live = textBox.marking(deleted: false, at: time)
        do {
            try add(live)
        } catch {
            throw .nodeLimitReached
        }
        return .textBox(live)
    }

    /// Removes the live box `id` and returns its tombstone with the change time `time`, for a
    /// command.
    ///
    /// - Throws: `CommandError.textBoxNotLive` if the box is not live.
    /// - Returns: The row of the tombstone.
    mutating func bury(
        _ id: TextBoxID,
        at time: HybridTimestamp
    ) throws(CommandError) -> LibraryChange {
        guard textBoxes[id] != nil else { throw .textBoxNotLive(id) }
        return .textBox(removeTextBox(id).marking(deleted: true, at: time))
    }
}
