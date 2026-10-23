import Geometry
import Model
import Rendering

/// Makes the vector PDF of one canvas (architecture.md section 9, EXP-02, EXP-03).
public enum PDFExporter {
    /// The margin around the ink and the text on the page, in canvas points (architecture.md
    /// section 9).
    static let margin = 48.0

    /// Returns the canvas rectangle that the page shows (D-141).
    ///
    /// The rectangle is the union of the bounds of the strokes and of the full rectangle of each
    /// text box, plus `margin`. Cards do not count, because the PDF does not show them (D-13).
    ///
    /// - Returns: The page bounds in canvas points, or `nil` if the content has no stroke and no
    ///   text box (D-142).
    static func pageBounds(of content: CanvasContent) -> Rect? {
        guard !content.strokes.isEmpty || !content.textBoxes.isEmpty else { return nil }
        var low = Point(x: Double.infinity, y: Double.infinity)
        var high = Point(x: -Double.infinity, y: -Double.infinity)
        for stroke in content.strokes.values {
            low = Point(x: min(low.x, stroke.bounds.minX), y: min(low.y, stroke.bounds.minY))
            high = Point(x: max(high.x, stroke.bounds.maxX), y: max(high.y, stroke.bounds.maxY))
        }
        for box in content.textBoxes.values {
            let size = TextLayout(text: box.text).size
            low = Point(x: min(low.x, box.origin.x), y: min(low.y, box.origin.y))
            high = Point(
                x: max(high.x, box.origin.x + size.width),
                y: max(high.y, box.origin.y + size.height)
            )
        }
        assert(low.isFinite && high.isFinite, "The page bounds of \(content.canvasID) are finite")
        let bounds = Rect(minX: low.x, minY: low.y, maxX: high.x, maxY: high.y)
        return bounds.expanded(by: margin)
    }
}
