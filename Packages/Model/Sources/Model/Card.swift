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

    /// The size of a new card in canvas points, the same at each zoom (D-101, D-118).
    static let defaultSize = Size(width: 320, height: 224)

    /// The ID of the child canvas.
    public var childCanvasID: CanvasID { CanvasID(id) }

    /// Returns the frame of a new card (D-101, D-118): `defaultSize`, centered on `point`. The
    /// size does not depend on the zoom.
    ///
    /// - Precondition: `point` is finite.
    /// - Returns: A frame in canvas points that the initializer of `Card` takes.
    public static func defaultFrame(at point: Point) -> Rect {
        precondition(point.isFinite, "The center of a new card must be finite, got \(point)")
        let frame = Rect(origin: point - defaultSize.halfDiagonal, size: defaultSize)
        return frame
    }

    /// Returns a copy with its frame at a new origin and the change time `time`. The size stays.
    ///
    /// - Throws: `ModelError.invalidGeometry` if `newOrigin` is not finite.
    public func moving(to newOrigin: Point, at time: HybridTimestamp) throws(ModelError) -> Card {
        guard newOrigin.isFinite else { throw .invalidGeometry(reason: "card frame is not finite") }
        return Card(self, meta: meta.changed(at: time), origin: newOrigin, title: title)
    }

    /// Returns a copy with a new title and the change time `time`. A title of 0 code points
    /// becomes `nil`, so `RenameCard` stores no empty title (the M6 plan task 1.2).
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
        let stored = length == 0 ? nil : newTitle
        return Card(self, meta: meta.changed(at: time), origin: frame.origin, title: stored)
    }

    /// Returns a copy with the tombstone flag `isDeleted` and the change time `time`.
    func marking(deleted isDeleted: Bool, at time: HybridTimestamp) -> Card {
        let copy = Card(
            self,
            meta: meta.changed(at: time, isDeleted: isDeleted),
            origin: frame.origin,
            title: title
        )
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
