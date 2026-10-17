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
}
