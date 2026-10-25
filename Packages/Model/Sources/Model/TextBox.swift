import Geometry

/// A block of typed text at a position on a canvas (data-model.md 7.3).
///
/// The width and the height come from the text layout. They are not stored.
public struct TextBox: Identifiable, Hashable, Sendable {
    /// The ID of the text box.
    public let id: TextBoxID
    /// The clock values and the tombstone flag.
    public let meta: RecordMeta
    /// The canvas that holds the text box.
    public let canvasID: CanvasID
    /// The top-left corner in canvas space.
    public let origin: Point
    /// The plain text, with 1 to `Limits.maxTextLength` code points.
    public let text: String
    /// The drawing order within the text layer.
    public let sortKey: FractionalIndex

    /// Makes a text box.
    ///
    /// - Throws: `ModelError.invalidGeometry` if `origin` is not finite, and
    ///   `ModelError.invalidText` if the text has a length outside `1...Limits.maxTextLength`
    ///   code points, and `ModelError.nullCharacter` if the text holds U+0000 (D-57).
    public init(
        id: TextBoxID,
        meta: RecordMeta,
        canvasID: CanvasID,
        origin: Point,
        text: String,
        sortKey: FractionalIndex
    ) throws(ModelError) {
        guard origin.isFinite else { throw .invalidGeometry(reason: "text box origin") }
        guard !TextLength.hasNull(text) else { throw .nullCharacter }
        let length = TextLength.of(text)
        guard length >= 1, length <= Limits.maxTextLength else {
            throw .invalidText(length: length)
        }
        self.id = id
        self.meta = meta
        self.canvasID = canvasID
        self.origin = origin
        self.text = text
        self.sortKey = sortKey
    }

    /// Makes a copy with new fields, without the checks of the public initializer. The callers
    /// check the fields that they change.
    private init(_ box: TextBox, meta: RecordMeta, origin: Point, text: String) {
        id = box.id
        self.meta = meta
        canvasID = box.canvasID
        self.origin = origin
        self.text = text
        sortKey = box.sortKey
    }

    /// Returns a copy with a new text and the change time `time`.
    ///
    /// - Throws: `ModelError.invalidText` or `ModelError.nullCharacter` for a text that the
    ///   initializer refuses.
    public func editing(
        text newText: String,
        at time: HybridTimestamp
    ) throws(ModelError) -> TextBox {
        guard !TextLength.hasNull(newText) else { throw .nullCharacter }
        let length = TextLength.of(newText)
        guard length >= 1, length <= Limits.maxTextLength else {
            throw .invalidText(length: length)
        }
        return TextBox(self, meta: meta.changed(at: time), origin: origin, text: newText)
    }

    /// Returns a copy at a new origin with the change time `time`.
    ///
    /// - Throws: `ModelError.invalidGeometry` if `newOrigin` is not finite.
    public func moving(
        to newOrigin: Point,
        at time: HybridTimestamp
    ) throws(ModelError) -> TextBox {
        guard newOrigin.isFinite else { throw .invalidGeometry(reason: "text box origin") }
        return TextBox(self, meta: meta.changed(at: time), origin: newOrigin, text: text)
    }

    /// Returns a copy with the tombstone flag `isDeleted` and the change time `time`.
    func marking(deleted isDeleted: Bool, at time: HybridTimestamp) -> TextBox {
        let copy = TextBox(
            self,
            meta: meta.changed(at: time, isDeleted: isDeleted),
            origin: origin,
            text: text
        )
        return copy
    }
}
