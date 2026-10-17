/// One stroke in the draw list, 32 bytes. The layout matches `StrokeDrawEntry` in Shaders.metal.
struct StrokeDrawEntry: Equatable {
    /// The stroke origin minus the reference point, in canvas points.
    var origin: SIMD2<Float>
    /// The index of the first point in the arena.
    var firstPoint: UInt32
    /// The control points of the stroke.
    var pointCount: UInt32
    /// The step between used control points.
    var stride: UInt32
    /// The pieces per segment.
    var pieces: UInt32
    /// The first instance of the stroke in this draw.
    var firstInstance: UInt32
    /// Half the line width, in canvas points.
    var radius: Float
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
