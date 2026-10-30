import UIKit

/// The step that places one glyph of a layout in the atlas. The CPU path and the stored path of
/// the text encoder place the glyphs the same way, so the step exists once (review of 2026-10-28,
/// 3.4.4). The font of a glyph changes rarely, so its number is looked up once per change. The
/// loops stay in their callers with the arrays of the layout in local values, and the step inlines
/// into them: a walk that held the arrays and gave the glyph with its place back per call took the
/// text pass of D-56 from 0.86 to 1.12 ms and the stored build at zoom 1 from 1.8 to 3.4 ms, in
/// pairs on 2026-10-30, as a wide optional across a call did in the erase step (D-195).
struct GlyphPlacer {
    private let fonts: [UIFont]
    private let indices: [UInt8]
    private var fontIndex = UInt8(0)
    private var fontID: Int32

    /// Starts with the first font of `layout`.
    ///
    /// - Precondition: Each glyph has a font index.
    init(of layout: TextLayout, in atlas: GlyphAtlas) {
        precondition(layout.fontIndices.count == layout.glyphs.count, "Each glyph has a font")
        fonts = layout.fonts
        indices = layout.fontIndices
        fontID = atlas.fontID(of: fonts[0])
    }

    /// Returns the place of the glyph `index` of the layout, or `nil` if the atlas holds no room
    /// for it.
    ///
    /// - Precondition: `index` is below the glyph count of the layout.
    @inline(__always)
    mutating func place(
        _ glyph: TextLayout.Glyph,
        at index: Int,
        in atlas: GlyphAtlas,
        exponent: Int,
        frame: UInt64
    ) -> GlyphAtlas.Placement? {
        if indices[index] != fontIndex {
            fontIndex = indices[index]
            fontID = atlas.fontID(of: fonts[Int(fontIndex)])
        }
        assert(fontID >= 0, "Font \(fontIndex) of glyph \(index) has its number, got \(fontID)")
        return atlas.placement(
            of: glyph.glyph,
            font: fonts[Int(fontIndex)],
            fontID: fontID,
            exponent: exponent,
            frame: frame
        )
    }
}
