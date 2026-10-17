/// The content of one canvas in memory (data-model.md section 8).
///
/// Only the canvas controller holds it (review A-03). M2 holds strokes only. Cards, text boxes,
/// and erase records come with M4 to M6.
public struct CanvasContent: Sendable {
    /// The canvas that the content belongs to.
    public let canvasID: CanvasID
    /// The live strokes by ID.
    public private(set) var strokes: [StrokeID: Stroke] = [:]

    /// Makes empty content.
    public init(canvasID: CanvasID) {
        self.canvasID = canvasID
    }

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
}
