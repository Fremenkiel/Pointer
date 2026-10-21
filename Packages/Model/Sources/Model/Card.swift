import Geometry

/// A rectangle on a canvas that opens into a child canvas of its own (data-model.md 7.2).
public struct Card: Identifiable, Hashable, Sendable {
    /// The ID of the card and of its child canvas.
    public let id: CardID
    /// The clock values and the tombstone flag.
    public let meta: RecordMeta
    /// The parent canvas.
    public let canvasID: CanvasID
    /// The frame in the space of the parent canvas.
    public let frame: Rect
    /// The optional title, with at most `Limits.maxTitleLength` code points.
    public let title: String?
    /// The drawing order within the card layer.
    public let sortKey: FractionalIndex

    /// Makes a card.
    ///
    /// - Throws: `ModelError.cardIsOwnCanvas` if `canvasID` is the child canvas of the card,
    ///   `ModelError.invalidGeometry` for a frame that is not finite or is smaller than
    ///   `Limits.minCardWidth` by `Limits.minCardHeight`, and `ModelError.invalidTitle` for a
    ///   title above `Limits.maxTitleLength` code points or `ModelError.nullCharacter` for a
    ///   title with U+0000.
    public init(
        id: CardID,
        meta: RecordMeta,
        canvasID: CanvasID,
        frame: Rect,
        title: String?,
        sortKey: FractionalIndex
    ) throws(ModelError) {
        guard canvasID != CanvasID(id) else { throw .cardIsOwnCanvas }
        try Self.check(frame)
        guard !(title.map(TextLength.hasNull) ?? false) else { throw .nullCharacter }
        let titleLength = title.map(TextLength.of) ?? 0
        guard titleLength <= Limits.maxTitleLength else {
            throw .invalidTitle(length: titleLength)
        }
        self.id = id
        self.meta = meta
        self.canvasID = canvasID
        self.frame = frame
        self.title = title
        self.sortKey = sortKey
    }

    /// Makes a copy with new fields, without the checks of the public initializer. The callers
    /// check the fields that they change.
    private init(_ card: Card, meta: RecordMeta, origin: Point, title: String?) {
        id = card.id
        self.meta = meta
        canvasID = card.canvasID
        frame = Rect(origin: origin, size: card.frame.size)
        self.title = title
        sortKey = card.sortKey
    }

    /// The ID of the child canvas.
    public var childCanvasID: CanvasID { CanvasID(id) }

    /// Returns a copy with its frame at a new origin and the change time `time`. The size stays.
    ///
    /// - Throws: `ModelError.invalidGeometry` if `newOrigin` is not finite.
    public func moving(to newOrigin: Point, at time: HybridTimestamp) throws(ModelError) -> Card {
        guard newOrigin.isFinite else { throw .invalidGeometry(reason: "card frame is not finite") }
        return Card(self, meta: meta.changed(at: time), origin: newOrigin, title: title)
    }

    /// Returns a copy with a new title and the change time `time`.
    ///
    /// - Throws: `ModelError.invalidTitle` for a title above `Limits.maxTitleLength` code points,
    ///   and `ModelError.nullCharacter` for a title with U+0000.
    public func retitling(
        _ newTitle: String?,
        at time: HybridTimestamp
    ) throws(ModelError) -> Card {
        guard !(newTitle.map(TextLength.hasNull) ?? false) else { throw .nullCharacter }
        let length = newTitle.map(TextLength.of) ?? 0
        guard length <= Limits.maxTitleLength else { throw .invalidTitle(length: length) }
        return Card(self, meta: meta.changed(at: time), origin: frame.origin, title: newTitle)
    }

    /// Returns a copy with the tombstone flag `isDeleted` and the change time `time`.
    public func marking(deleted isDeleted: Bool, at time: HybridTimestamp) -> Card {
        let copy = Card(
            self,
            meta: meta.changed(at: time, isDeleted: isDeleted),
            origin: frame.origin,
            title: title
        )
        assert(copy.meta.isDeleted == isDeleted, "The copy has the asked tombstone flag")
        return copy
    }

    private static func check(_ frame: Rect) throws(ModelError) {
        let size = frame.size
        guard frame.origin.isFinite, size.width.isFinite, size.height.isFinite else {
            throw .invalidGeometry(reason: "card frame is not finite")
        }
        guard size.width >= Limits.minCardWidth, size.height >= Limits.minCardHeight else {
            throw .invalidGeometry(reason: "card size \(size.width) by \(size.height)")
        }
    }
}
