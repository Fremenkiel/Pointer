import CoreGraphics
import Foundation
import Geometry
import Model
import os

extension PDFExporter {
    /// The signposts of the export (PERF-03).
    private static let signposter = OSSignposter(
        subsystem: "dk.saarikivi.pointer",
        category: "Export"
    )

    /// Makes the one-page vector PDF of a canvas (architecture.md section 9, EXP-02, EXP-03).
    ///
    /// The page is white and shows the strokes and the text boxes in black, without cards (D-13).
    /// A page with a side over `maxPageSide` scales as a whole (D-142). The function reads only
    /// its argument and is not bound to an actor, so the canvas runs it off the main actor (D-138).
    ///
    /// - Returns: The PDF data.
    /// - Throws: `ExportError.emptyCanvas` if the content has no stroke and no text box, and
    ///   `ExportError.pdfContextFailed` if Core Graphics makes no PDF context.
    public static func pdfData(of content: CanvasContent) throws(ExportError) -> Data {
        let interval = signposter.beginInterval("Export")
        defer { signposter.endInterval("Export", interval) }
        guard let bounds = pageBounds(of: content) else { throw .emptyCanvas }
        let layout = pageLayout(for: bounds)
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: layout.width, height: layout.height)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { throw .pdfContextFailed }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(mediaBox)
        // The canvas has y down and the PDF has y up. One scale fits the whole page (D-142).
        context.translateBy(x: 0, y: layout.height)
        context.scaleBy(x: layout.scale, y: -layout.scale)
        drawStrokes(of: content, from: bounds.origin, in: context)
        drawText(of: content, from: bounds.origin, in: context)
        context.endPDFPage()
        context.closePDF()
        assert(data.length > 0, "The PDF of \(content.canvasID) is not empty")
        return Self.data(sharing: data)
    }
}
