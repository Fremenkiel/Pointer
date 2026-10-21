import CoreGraphics
import CoreText
import UIKit

/// The bitmap of one glyph at one scale, drawn by Core Text (D-29).
struct GlyphRaster {
    /// The width in pixels.
    let width: Int
    /// The height in pixels.
    let height: Int
    /// The top-left corner of the bitmap from the baseline point of the glyph, in pixels, with y
    /// down.
    let bearing: SIMD2<Float>
    /// The coverage of the pixels, one byte each, top row first.
    let pixels: [UInt8]

    /// Draws a glyph of a font at `scale` pixels per point of the font.
    ///
    /// - Precondition: `scale` is positive.
    init(glyph: CGGlyph, font: UIFont, scale: Double) {
        precondition(scale > 0, "A glyph scale is positive, got \(scale)")
        let sized = CTFontCreateCopyWithAttributes(
            font as CTFont,
            font.pointSize * scale,
            nil,
            nil
        )
        let bounds = Self.bounds(of: glyph, font: sized)
        guard !bounds.isEmpty, bounds.width.isFinite, bounds.height.isFinite else {
            self.init(width: 0, height: 0, bearing: .zero, pixels: [])
            return
        }
        let left = bounds.minX.rounded(.down)
        let bottom = bounds.minY.rounded(.down)
        let width = Int((bounds.maxX - left).rounded(.up)) + 1
        let height = Int((bounds.maxY - bottom).rounded(.up)) + 1
        let pixels = Self.draw(glyph, font: sized, width: width, height: height, at: (left, bottom))
        self.init(
            width: width,
            height: height,
            bearing: SIMD2(Float(left), -Float(bottom) - Float(height)),
            pixels: pixels
        )
        assert(self.pixels.count == width * height, "One byte per pixel")
    }

    private init(width: Int, height: Int, bearing: SIMD2<Float>, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.bearing = bearing
        self.pixels = pixels
    }
}
