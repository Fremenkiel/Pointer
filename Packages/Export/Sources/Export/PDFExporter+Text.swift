import CoreGraphics
import CoreText
import Geometry
import Model
import Rendering

extension PDFExporter {
    /// Draws the text of each text box in black, line by line, at the baselines of the screen.
    ///
    /// `TextLayout` gives the lines, so the PDF breaks the lines where the screen does. Each line
    /// draws with `CTLineDraw`, so that the PDF keeps the text for selection and search. Drawn
    /// glyph IDs would lose it (D-140). Color emoji stay bitmaps with searchable text (D-142).
    ///
    /// - Precondition: `pageOrigin` is finite, and the context has a flipped page: y grows down.
    static func drawText(of content: CanvasContent, from pageOrigin: Point, in context: CGContext) {
        precondition(pageOrigin.isFinite, "Page origin of \(content.canvasID) is not finite")
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        // The page is flipped, so the text matrix flips the glyphs upright again (D-140).
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for box in content.textBoxes.values {
            let left = box.origin.x - pageOrigin.x
            let top = box.origin.y - pageOrigin.y
            for (index, line) in TextLayout.lines(of: box.text).enumerated() {
                let baseline = top + Double(index) * TextLayout.lineHeight + TextLayout.ascent
                context.textPosition = CGPoint(x: left, y: baseline)
                CTLineDraw(line.line, context)
            }
        }
        assert(context.textMatrix.d == -1, "The text matrix of \(content.canvasID) stays flipped")
    }
}
