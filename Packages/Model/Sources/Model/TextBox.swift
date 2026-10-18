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
}
