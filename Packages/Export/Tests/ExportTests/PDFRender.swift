import CoreGraphics
import Foundation
import Rendering
import UIKit

/// Renders the first page of a PDF into an image (TEST-07, docs/m8-plan.md section 1.2).
enum PDFRender {
    /// Returns the first page of the PDF data.
    static func firstPage(of data: Data) -> CGPDFPage? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGPDFDocument(provider)?.page(at: 1)
    }

    /// Renders the first page at one pixel per PDF point, times `scale`, cut to whole pixels.
    static func image(of data: Data, scale: Double = 1) -> RenderedImage? {
        guard let page = firstPage(of: data) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        // Whole pixels only: a partial last column lies outside the page and reads as black.
        let size = CGSize(
            width: (box.width * scale).rounded(.down),
            height: (box.height * scale).rounded(.down)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cgContext = context.cgContext
            cgContext.translateBy(x: 0, y: size.height)
            cgContext.scaleBy(x: scale, y: -scale)
            cgContext.drawPDFPage(page)
        }
        return image.pngData().flatMap(Snapshot.decode)
    }

    /// Returns the number of pixels with a gray value below 128.
    static func darkPixelCount(of image: RenderedImage) -> Int {
        var count = 0
        for y in 0..<image.height {
            for x in 0..<image.width where image.gray(x: x, y: y) < 128 { count += 1 }
        }
        return count
    }
}
