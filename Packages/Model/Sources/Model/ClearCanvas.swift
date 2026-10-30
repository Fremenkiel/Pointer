/// Removes all ink, text boxes, and cards of one canvas as one undo step (TOOL-10, D-200).
///
/// The strokes get erase records, as an erase gives them (D-30), and the nodes become
/// tombstones, as a delete does (data-model.md section 5). A card marks the card only: its child
/// content stays on disk and comes back with the undo (D-18). The undo puts every item back.
public struct ClearCanvas: CanvasCommand {
    /// The canvas of the items.
    public let canvasID: CanvasID
    /// The live strokes before the clear.
    public let strokes: [Stroke]
    /// The live text boxes before the clear.
    public let textBoxes: [TextBox]
    /// The live cards before the clear.
    public let cards: [Card]
    /// The bytes of the strokes, the texts, and the titles (D-76, D-88, D-183).
    public let heldByteCount: Int

    /// Makes the command from the live content of a canvas.
    ///
    /// - Precondition: The content holds at least one stroke, text box, or card.
    public init(clearing content: CanvasContent) {
        precondition(
            !content.strokes.isEmpty || content.nodeCount > 0,
            "ClearCanvas needs an item on canvas \(content.canvasID)"
        )
        canvasID = content.canvasID
        strokes = Array(content.strokes.values)
        textBoxes = Array(content.textBoxes.values)
        cards = Array(content.cards.values)
        let strokeBytes = strokes.reduce(0) { $0 + HistoryCost.bytes(ofStroke: $1.points.count) }
        let textBytes = textBoxes.reduce(0) { $0 + HistoryCost.bytes(ofText: $1.text) }
        let titleBytes = cards.reduce(0) { $0 + HistoryCost.bytes(ofText: $1.title) }
        heldByteCount = strokeBytes + textBytes + titleBytes
    }

    /// The number of strokes, text boxes, and cards.
    public var itemCount: Int { strokes.count + textBoxes.count + cards.count }

    /// Calls `body` with the ID of each stroke.
    public func forEachHeldStroke(_ body: (StrokeID) -> Void) {
        for stroke in strokes { body(stroke.id) }
    }

    /// Removes every stroke and makes every node a tombstone.
    ///
    /// - Precondition: The content is the canvas of the command.
    /// - Throws: `CommandError.strokeNotLive`, `CommandError.textBoxNotLive`, or
    ///   `CommandError.cardNotLive` if an item is not live. The content then stays as it was.
    /// - Returns: The erase records of the strokes and the tombstones of the nodes.
    public func apply(
        to content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        precondition(content.canvasID == canvasID, "The content of canvas \(canvasID)")
        // The nodes are checked first, so that a node that is not live changes no stroke.
        try checkNodes(areLive: true, in: content)
        let time = clock.now()
        var changes: [LibraryChange] = []
        changes.reserveCapacity(itemCount)
        var log = CanvasContent.ChangeLog(capacity: strokes.count)
        do {
            try content.remove(strokes, at: time, log: &log, changes: &changes)
        } catch {
            content.rollBack(log)
            throw error
        }
        for box in textBoxes { changes.append(try content.bury(box.id, at: time)) }
        for card in cards { changes.append(try content.bury(card.id, at: time)) }
        assert(changes.count == itemCount, "Each item gives one row")
        return changes
    }

    /// Puts every stroke and every node back.
    ///
    /// The undo takes the canvas up to `Limits.maxStrokesAfterErase`, because the state that it
    /// gives back existed one step before (D-159).
    ///
    /// - Precondition: The content is the canvas of the command.
    /// - Throws: `CommandError.strokeAlreadyLive`, `CommandError.textBoxAlreadyLive`, or
    ///   `CommandError.cardAlreadyLive` if an item is live, `CommandError.eraseRecordMissing` if
    ///   the content has no erase record of a stroke, `CommandError.strokeLimitReached` if the
    ///   strokes pass `Limits.maxStrokesAfterErase`, or `CommandError.nodeLimitReached` if the
    ///   nodes pass `Limits.maxNodesPerCanvas`. The content then stays as it was.
    /// - Returns: The tombstones of the erase records and the rows of the live nodes.
    public func revert(
        on content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        precondition(content.canvasID == canvasID, "The content of canvas \(canvasID)")
        guard content.strokes.count + strokes.count <= Limits.maxStrokesAfterErase else {
            throw .strokeLimitReached
        }
        guard content.nodeCount + textBoxes.count + cards.count <= Limits.maxNodesPerCanvas else {
            throw .nodeLimitReached
        }
        try checkNodes(areLive: false, in: content)
        let time = clock.now()
        var changes: [LibraryChange] = []
        changes.reserveCapacity(itemCount)
        var log = CanvasContent.ChangeLog(capacity: strokes.count)
        do {
            try content.restore(strokes, at: time, needsRecords: true, log: &log, changes: &changes)
        } catch {
            content.rollBack(log)
            throw error
        }
        for box in textBoxes { changes.append(try content.revive(box, at: time)) }
        for card in cards { changes.append(try content.revive(card, at: time)) }
        assert(changes.count == itemCount, "Each item gives one row")
        return changes
    }

    /// Makes sure that each node is live, or with `areLive` false that none is, so that a step
    /// changes nothing before it throws.
    ///
    /// - Throws: The `CommandError` of the first node that breaks the rule.
    private func checkNodes(areLive: Bool, in content: CanvasContent) throws(CommandError) {
        for box in textBoxes where (content.textBoxes[box.id] != nil) != areLive {
            throw areLive ? .textBoxNotLive(box.id) : .textBoxAlreadyLive(box.id)
        }
        for card in cards where (content.cards[card.id] != nil) != areLive {
            throw areLive ? .cardNotLive(card.id) : .cardAlreadyLive(card.id)
        }
    }
}
