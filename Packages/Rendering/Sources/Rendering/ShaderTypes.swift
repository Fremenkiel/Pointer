/// One stroke in the draw list, 32 bytes. The layout matches `StrokeDrawEntry` in Shaders.metal.
struct StrokeDrawEntry: Equatable {
    /// The stroke origin minus the reference point, in canvas points.
    var origin: SIMD2<Float>
    /// The index of the first point of the run in the arena.
    var firstPoint: UInt32
    /// The control points of the run, from its first point to its last point.
    var pointCount: UInt32
    /// The index of the first point of the run in its stroke in bits 0 to 13, and the offset back
    /// to the neighbor point before the run in bits 14 to 25, packed by
    /// `packStart(start:previousOffset:)`. An offset of 0 marks the start of the stroke.
    var firstSegment: UInt32
    /// The stride, the pieces, and the offset of the next real point, packed by
    /// `packDetail(stride:pieces:nextOffset:)`.
    var detail: UInt32
    /// The first instance of the run in this draw.
    var firstInstance: UInt32
    /// Half the line width, in canvas points.
    var radius: Float

    /// The bits of the stride and of the offset of the next point.
    static let offsetBits: UInt32 = 12
    /// The bits of the pieces minus one.
    static let pieceBits: UInt32 = 5

    /// The bits of the start index: the start is below `Limits.maxPointsPerStroke`.
    static let startBits: UInt32 = 14

    /// Packs the start of a run and the offset back to its previous neighbor point.
    ///
    /// - Precondition: Each value fits into its bits.
    static func packStart(start: Int, previousOffset: Int) -> UInt32 {
        precondition(start >= 0 && start < 1 << Int(startBits), "Start \(start) does not fit")
        precondition(
            previousOffset >= 0 && previousOffset < 1 << Int(offsetBits),
            "Offset \(previousOffset) does not fit"
        )
        return UInt32(start) | UInt32(previousOffset) << startBits
    }

    /// Packs the level of detail of a run into one value: the stride in bits 0 to 11, the pieces
    /// minus one in bits 12 to 16, and the offset from the last point of the run to the next
    /// point of the stroke in bits 17 to 28. An offset of 0 marks the end of the stroke.
    ///
    /// - Precondition: Each value fits into its bits, and `pieces` is positive.
    static func packDetail(stride: Int, pieces: Int, nextOffset: Int) -> UInt32 {
        let limit = 1 << Int(offsetBits)
        precondition(stride >= 1 && stride < limit, "Stride \(stride) does not fit")
        precondition(pieces >= 1 && pieces <= 1 << Int(pieceBits), "Pieces \(pieces) do not fit")
        precondition(nextOffset >= 0 && nextOffset < limit, "Offset \(nextOffset) does not fit")
        let piecesShift = offsetBits
        let offsetShift = offsetBits + pieceBits
        return UInt32(stride) | UInt32(pieces - 1) << piecesShift | UInt32(nextOffset)
            << offsetShift
    }
}

/// The values of one ink draw. The layout matches `InkUniforms` in Shaders.metal.
struct InkUniforms {
    /// The size of the target texture, in pixels.
    var targetSize: SIMD2<Float>
    /// The pixel position of the reference point.
    var offset: SIMD2<Float>
    /// Pixels per canvas point.
    var scale: Float
    /// The number of entries in the draw list.
    var entryCount: UInt32
    /// Half the width of the edge ramp, in pixels.
    var edge: Float
    /// Keeps the size at 32 bytes.
    var padding: Float = 0
}

/// The values of the composite pass. The layout matches `CompositeUniforms` in Shaders.metal.
struct CompositeUniforms {
    /// The factor from a drawable pixel to a committed texture pixel.
    var scale: SIMD2<Float>
    /// The offset from a drawable pixel to a committed texture pixel.
    var offset: SIMD2<Float>
    /// The size of the committed texture, in pixels.
    var textureSize: SIMD2<Float>
    /// The canvas color in sRGB, with alpha 1 (D-106).
    var background: SIMD4<Float>
}

/// The values of one transition frame (D-98, D-108). The layout matches `TransitionUniforms` in
/// Shaders.metal.
struct TransitionUniforms {
    /// The canvas color in sRGB, with alpha 1 (D-106).
    var background: SIMD4<Float>
    /// The opened card: min x, min y, max x, max y, in drawable pixels.
    var cardRect: SIMD4<Float>
    /// The preview in the atlas: origin and size from 0 to 1. A size of 0 shows no preview.
    var previewRect: SIMD4<Float>
    /// The factor from a drawable pixel to a source texture pixel.
    var scale: SIMD2<Float>
    /// The offset from a drawable pixel to a source texture pixel.
    var offset: SIMD2<Float>
    /// The size of the source texture, in pixels.
    var textureSize: SIMD2<Float>
    /// The weight of the parent image, from 0 to 1.
    var parentWeight: Float
    /// The coverage of the card border (D-96).
    var borderCoverage: Float
    /// Half the width of the border, in pixels.
    var borderHalfWidth: Float
    /// The corner radius of the card, in pixels.
    var cornerRadius: Float
    /// 1 if a parent image exists, else 0.
    var hasSource: Float
    /// The coverage of the card body (D-116).
    var fillCoverage: Float
}

/// The values of one frame of a pinch-out exit (D-109). The layout matches `PinchUniforms` in
/// Shaders.metal.
struct PinchUniforms {
    /// The canvas color in sRGB, with alpha 1 (D-106).
    var background: SIMD4<Float>
    /// The shrinking card: min x, min y, max x, max y, in drawable pixels.
    var cardRect: SIMD4<Float>
    /// The factor from a drawable pixel to a pixel of the frozen parent.
    var parentScale: SIMD2<Float>
    /// The offset from a drawable pixel to a pixel of the frozen parent.
    var parentOffset: SIMD2<Float>
    /// The size of the frozen parent, in pixels.
    var parentSize: SIMD2<Float>
    /// The factor from a child screen pixel to a pixel of its committed texture.
    var childScale: SIMD2<Float>
    /// The offset from a child screen pixel to a pixel of its committed texture.
    var childOffset: SIMD2<Float>
    /// The size of the committed texture, in pixels.
    var childSize: SIMD2<Float>
    /// The center of the drawable, in pixels.
    var screenCenter: SIMD2<Float>
    /// The weight of the parent image, from 0 to 1.
    var parentWeight: Float
    /// The coverage of the card border (D-96).
    var borderCoverage: Float
    /// Half the width of the border, in pixels.
    var borderHalfWidth: Float
    /// The corner radius of the card, in pixels.
    var cornerRadius: Float
    /// The width of the card over its width at the start of the exit.
    var shrink: Float
    /// The coverage of the card body (D-116).
    var fillCoverage: Float
}

/// The values of one preview draw. The layout matches `CardPreviewUniforms` in Shaders.metal.
struct CardPreviewUniforms {
    /// The size of the target texture, in pixels.
    var targetSize: SIMD2<Float>
    /// The size of the preview atlas, in pixels.
    var atlasSize: SIMD2<Float>
    /// The corner radius of the cards of the pass, in pixels.
    var radius: Float
}

/// One eraser stamp in mask pixels. The layout matches `EraserStamp` in Shaders.metal.
struct EraserStamp {
    /// The pixel position of the earlier sample.
    var start: SIMD2<Float>
    /// The pixel position of the newer sample.
    var end: SIMD2<Float>
    /// The size of the mask, in pixels.
    var targetSize: SIMD2<Float>
    /// The eraser radius, in pixels.
    var radius: Float
    /// Half the width of the anti-aliased edge, in pixels.
    var edge: Float
}

/// One glyph quad of the text pass. The layout matches `GlyphInstance` in Shaders.metal.
struct GlyphInstance {
    /// The top-left corner in the target, in pixels.
    var position: SIMD2<Float>
    /// The size in the target, in pixels.
    var size: SIMD2<Float>
    /// The top-left corner in the atlas page, in pixels.
    var atlasOrigin: SIMD2<Float>
    /// The size in the atlas page, in pixels.
    var atlasSize: SIMD2<Float>
}

/// The values of one glyph draw. The layout matches `GlyphUniforms` in Shaders.metal.
struct GlyphUniforms {
    /// The size of the target texture, in pixels.
    var targetSize: SIMD2<Float>
    /// The size of the atlas page, in pixels.
    var atlasSize: SIMD2<Float>
}
