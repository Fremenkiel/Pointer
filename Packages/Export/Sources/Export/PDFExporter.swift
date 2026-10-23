import Geometry
import Model
import Rendering

/// Makes the vector PDF of one canvas (architecture.md section 9, EXP-02, EXP-03).
public enum PDFExporter {
    /// The margin around the ink and the text on the page, in canvas points (architecture.md
    /// section 9).
    static let margin = 48.0

    /// The longest side of a PDF page, in points: 200 inches. ISO 32000-1, Annex C, gives this
    /// limit (D-142). Source:
    /// <https://kb.datalogics.com/article/how-large-can-a-pdf-document-be-in-inches-101.html>
    static let maxPageSide = 14_400.0

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

    /// Returns the media box and the scale of a page that shows `bounds` (D-142).
    ///
    /// - Precondition: `bounds` has a positive, finite width and height.
    /// - Returns: A scale of 1 if the longer side is at most `maxPageSide`. Otherwise, the scale
    ///   that makes the longer side `maxPageSide`. No side of the media box is over `maxPageSide`.
    static func pageLayout(for bounds: Rect) -> PageLayout {
        let size = bounds.size
        precondition(
            size.width > 0 && size.height > 0 && size.width.isFinite && size.height.isFinite,
            "Page bounds \(size.width) x \(size.height) are not positive and finite"
        )
        let longer = max(size.width, size.height)
        let scale = longer > maxPageSide ? maxPageSide / longer : 1
        let layout = PageLayout(
            width: min(size.width * scale, maxPageSide),
            height: min(size.height * scale, maxPageSide),
            scale: scale
        )
        assert(layout.scale > 0 && layout.scale <= 1, "Page scale \(layout.scale) is in 0...1")
        return layout
    }
}
