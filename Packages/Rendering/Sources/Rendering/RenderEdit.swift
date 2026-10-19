import Geometry
import Model

/// One change of the strokes that the main actor sends to the render thread: a handoff of new
/// strokes, an erase, an undo, or a redo.
struct RenderEdit: Sendable {
    /// The strokes to remove. The renderer redraws the area that they covered (D-66).
    let removed: [StrokeID]
    /// The strokes to add.
    let added: [Stroke]
    /// The area to redraw, or `nil` for the area of the removed strokes. With an area, the added
    /// strokes show only inside it, because their ink outside it is on the screen already.
    var area: Rect?
}
