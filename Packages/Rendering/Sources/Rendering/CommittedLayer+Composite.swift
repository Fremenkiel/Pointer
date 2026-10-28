import Geometry

/// The mapping of the composite: from a drawable pixel to a pixel of a committed texture or of a
/// frozen copy (architecture.md 5.2, D-109).
extension CommittedLayer {
    /// Returns the composite values that show the shown texture with `camera`.
    ///
    /// A drawable pixel p shows the texture pixel `p * scale + offset`.
    ///
    /// - Precondition: A texture is shown, and `displayScale` is positive.
    func compositeUniforms(
        camera: Camera,
        displayScale: Double,
        drawableSize: Size,
        background: SIMD3<Float>
    ) -> CompositeUniforms {
        precondition(displayScale > 0, "Display scale must be positive, got \(displayScale)")
        guard let front = shown else { preconditionFailure("No texture to composite") }
        return Self.compositeUniforms(
            of: front,
            camera: camera,
            displayScale: displayScale,
            drawableSize: drawableSize,
            background: background
        )
    }

    /// Returns the composite values that show the texture of `front` with `camera`: a drawable
    /// pixel p shows the texture pixel `p * scale + offset`.
    ///
    /// - Precondition: `displayScale` is positive.
    static func compositeUniforms(
        of front: InkTarget,
        camera: Camera,
        displayScale: Double,
        drawableSize: Size,
        background: SIMD3<Float>
    ) -> CompositeUniforms {
        precondition(displayScale > 0, "Display scale must be positive, got \(displayScale)")
        // Texture pixels per drawable pixel. A fallback can have another display scale.
        let ratio = front.pixelsPerCanvasPoint / (camera.zoom * displayScale)
        let pixelsPerPoint = front.pixelsPerCanvasPoint
        let shift = camera.center - front.camera.center
        let size = front.pixelSize
        var offsetX = size.width / 2 + shift.dx * pixelsPerPoint - ratio * drawableSize.width / 2
        var offsetY = size.height / 2 + shift.dy * pixelsPerPoint - ratio * drawableSize.height / 2
        assert(offsetX.isFinite && offsetY.isFinite, "Composite offset is not finite")
        // At a ratio of 1, a whole-pixel offset maps each drawable pixel to one texture pixel, so
        // the linear filter does not blur the ink during a pan (the M2 fix plan, phase 5).
        if ratio == 1 {
            offsetX.round()
            offsetY.round()
        }
        return CompositeUniforms(
            scale: SIMD2(Float(ratio), Float(ratio)),
            offset: SIMD2(Float(offsetX), Float(offsetY)),
            textureSize: SIMD2(Float(size.width), Float(size.height)),
            background: SIMD4(background, 1)
        )
    }
}
