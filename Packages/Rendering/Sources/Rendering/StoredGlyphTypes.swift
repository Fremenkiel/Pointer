/// One stored glyph quad of a run (architecture.md 5.4.1, D-94): the baseline x and the line of
/// the glyph in its box, and the index of its placement in `GlyphPageTable.places`. The layout
/// matches `StoredGlyph` in Shaders.metal: 12 bytes, so that the runs of the D-56 text take
/// about 10 MB.
struct StoredGlyph {
    /// The baseline x of the glyph, in canvas points from the left side of the box.
    var x: Float
    /// The line of the glyph, from 0.
    var line: UInt16
    // The shaders read the padding, and the analyzer of Swift does not see it (SCOPE-01).
    // swiftlint:disable unused_declaration
    /// Keeps the size at 12 bytes.
    var padding: UInt16 = 0
    // swiftlint:enable unused_declaration
    /// The index of the placement of the bitmap.
    var place: UInt32
}

/// The place of one glyph bitmap for the stored runs. The layout matches `GlyphPlace` in
/// Shaders.metal: 24 bytes.
struct GlyphPlace {
    /// The top-left corner of the bitmap from the baseline point, in atlas pixels.
    var bearing: SIMD2<Float>
    /// The top-left corner of the bitmap in its page, in pixels.
    var atlasOrigin: SIMD2<UInt16>
    /// The size of the bitmap, in pixels.
    var atlasSize: SIMD2<UInt16>
    /// The index of the page in the atlas.
    var page: UInt32
    // The shaders read the padding, and the analyzer of Swift does not see it (SCOPE-01).
    // swiftlint:disable unused_declaration
    /// Keeps the size at 24 bytes.
    var padding: UInt32 = 0
    // swiftlint:enable unused_declaration
}

/// The record of one stored run in a text pass: where the run lies and where its box lies in
/// the target (architecture.md 5.4.1, D-190). The layout matches `GlyphRecord` in
/// Shaders.metal: 24 bytes.
struct GlyphRecord {
    /// The top-left corner of the box in target pixels.
    var base: SIMD2<Float>
    /// The first quad of the run in its buffer.
    var runStart: UInt32
    /// The quads of the run.
    var count: UInt32
    /// The quads of the records before this one in the pass.
    var prefix: UInt32
    /// The index of the buffer of the run in the run store.
    var buffer: UInt32
}

/// The values that turn the stored glyphs of a pass into quads in the vertex shader of the
/// paged glyph draw. The layout matches `StoredUniforms` in Shaders.metal.
struct StoredUniforms {
    /// The pixels per canvas point of the target.
    var scale: Float
    /// The target pixels per atlas pixel.
    var ratio: Float
    /// The records of the pass.
    var recordCount: UInt32
    /// The height of a line and the distance from its top to the baseline, in canvas points.
    var lineHeight: Float
    var ascent: Float
}

/// The values of one draw of stored glyphs. The layout matches `PagedGlyphUniforms` in
/// Shaders.metal.
struct PagedGlyphUniforms {
    /// The size of the target texture, in pixels.
    var targetSize: SIMD2<Float>
    /// The size of the atlas pages of the pass, in pixels.
    var atlasSize: SIMD2<Float>
    /// The target pixels per atlas pixel.
    var ratio: Float
}
