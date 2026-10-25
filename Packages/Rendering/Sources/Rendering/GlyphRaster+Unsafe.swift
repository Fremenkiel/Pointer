import CoreGraphics
import CoreText
import Metal

extension GlyphRaster {
    /// Returns the bounding box of a glyph in the pixels of `font`, with y up.
    static func bounds(of glyph: CGGlyph, font: CTFont) -> CGRect {
        var glyphs = [glyph]
        var rects = [CGRect.zero]
        // Safe: both arrays hold one element, and the count is 1.
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyphs, &rects, 1)
        return rects[0]
    }

    /// Draws a glyph white on black into a gray bitmap whose bottom-left corner is `origin` in
    /// the glyph space.
    static func draw(
        _ glyph: CGGlyph,
        font: CTFont,
        width: Int,
        height: Int,
        at origin: (x: CGFloat, y: CGFloat)
    ) -> [UInt8] {
        precondition(width > 0 && height > 0, "A glyph bitmap holds pixels")
        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { bytes in
            // Safe: the buffer holds `width * height` bytes, one row of `width` bytes each.
            guard
                let context = CGContext(
                    data: bytes.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                )
            else { return }
            context.setFillColor(gray: 1, alpha: 1)
            context.setShouldAntialias(true)
            var glyphs = [glyph]
            var positions = [CGPoint(x: -origin.x, y: -origin.y)]
            // Safe: both arrays hold one element, and the count is 1.
            CTFontDrawGlyphs(font, &glyphs, &positions, 1, context)
        }
        return pixels
    }

    /// Copies the bitmap into a texture at `(x, y)`.
    ///
    /// - Precondition: The bitmap fits the texture there.
    func upload(into texture: any MTLTexture, x: Int, y: Int) {
        precondition(
            x >= 0 && y >= 0 && x + width <= texture.width && y + height <= texture.height,
            "Glyph bitmap at (\(x), \(y)) does not fit the page"
        )
        let region = MTLRegionMake2D(x, y, width, height)
        // Safe: `pixels` holds `width * height` bytes with rows of `width` bytes.
        pixels.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.replace(region: region, mipmapLevel: 0, withBytes: base, bytesPerRow: width)
        }
    }
}
