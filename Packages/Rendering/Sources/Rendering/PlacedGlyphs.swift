import UIKit

/// The glyphs of a layout with the place of each one in the atlas, in order. The CPU path and
/// the stored path of the text encoder walk the glyphs the same way, so the loop exists once
/// (review of 2026-10-28, 3.4.4). The font of a glyph changes rarely, so its number is looked
/// up once per change.
struct PlacedGlyphs {
    /// One glyph with its place, or `nil` if the atlas holds no room for it.
    struct Item {
        let glyph: TextLayout.Glyph
        let place: GlyphAtlas.Placement?
    }

    private let layout: TextLayout
    private let atlas: GlyphAtlas
    private let exponent: Int
    private let frame: UInt64
    private var index = 0
    private var fontIndex = UInt8(0)
    private var fontID: Int32

    /// Starts at the first glyph of `layout`.
    ///
    /// - Precondition: Each glyph has a font index.
    init(of layout: TextLayout, in atlas: GlyphAtlas, exponent: Int, frame: UInt64) {
        precondition(layout.fontIndices.count == layout.glyphs.count, "Each glyph has a font")
        self.layout = layout
        self.atlas = atlas
        self.exponent = exponent
        self.frame = frame
        fontID = atlas.fontID(of: layout.fonts[0])
    }

    /// Returns the next glyph with its place, or `nil` after the last glyph.
    mutating func next() -> Item? {
        guard index < layout.glyphs.count else { return nil }
        let glyph = layout.glyphs[index]
        if layout.fontIndices[index] != fontIndex {
            fontIndex = layout.fontIndices[index]
            fontID = atlas.fontID(of: layout.fonts[Int(fontIndex)])
        }
        index += 1
        let place = atlas.placement(
            of: glyph.glyph,
            font: layout.fonts[Int(fontIndex)],
            fontID: fontID,
            exponent: exponent,
            frame: frame
        )
        return Item(glyph: glyph, place: place)
    }
}
