/// The level of detail of a stroke at a zoom (architecture.md 5.3).
///
/// At low zoom, the draw list skips control points so that the points it uses are at least
/// `minimumPixelSpacing` apart on the screen. At high zoom, each segment is cut into pieces so
/// that the curve stays smooth.
struct LevelOfDetail: Equatable {
    /// The smallest screen distance between two used control points. 1.0 pixel halved the GPU
    /// time of dense content at zoom 0.25 against the 0.5 of M2, with a largest pixel difference
    /// of 12 of 255. 2.0 gave a difference of 58 (docs/m2-fix-plan.md, phase 3).
    static let minimumPixelSpacing = 1.0
    /// The target screen length of one piece. A piece of 6 pixels with a turn of 0.5 radians
    /// differs from the curve by less than 0.4 pixels.
    static let targetPiecePixels = 6.0
    /// The upper bound of pieces per segment.
    static let maxPiecesPerSegment = 32

    /// The step between used control points. 1 uses every point.
    let stride: Int
    /// The number of control points that the draw uses.
    let effectivePointCount: Int
    /// The pieces per segment.
    let piecesPerSegment: Int

    /// The number of draw instances: one per piece.
    var instanceCount: Int { (effectivePointCount - 1) * piecesPerSegment }

    /// Computes the level of detail of a stroke. Tests pass another `minimumPixelSpacing` to
    /// compare values (docs/m2-fix-plan.md, phase 0).
    ///
    /// - Precondition: `pointCount >= 2`, the spacings are zero or positive, and
    ///   `pixelsPerCanvasPoint` and `minimumPixelSpacing` are positive.
    init(
        pointCount: Int,
        meanSpacing: Double,
        maxSpacing: Double,
        pixelsPerCanvasPoint: Double,
        minimumPixelSpacing: Double = Self.minimumPixelSpacing
    ) {
        precondition(pointCount >= 2, "A stroke has 2 points at least, got \(pointCount)")
        precondition(
            meanSpacing >= 0 && maxSpacing >= meanSpacing,
            "Spacing \(meanSpacing) is invalid"
        )
        precondition(
            pixelsPerCanvasPoint > 0,
            "Pixel scale must be positive, got \(pixelsPerCanvasPoint)"
        )
        precondition(minimumPixelSpacing > 0, "Spacing \(minimumPixelSpacing) is not positive")
        let meanPixels = meanSpacing * pixelsPerCanvasPoint
        var stride = pointCount - 1
        if meanPixels >= minimumPixelSpacing {
            stride = 1
        } else if meanPixels > 0 {
            stride = min(pointCount - 1, Int((minimumPixelSpacing / meanPixels).rounded(.up)))
        }
        self.stride = stride
        effectivePointCount = (pointCount - 1 + stride - 1) / stride + 1
        let segmentPixels = maxSpacing * Double(stride) * pixelsPerCanvasPoint
        let pieces = (segmentPixels / Self.targetPiecePixels).rounded(.up)
        piecesPerSegment = Int(min(max(pieces, 1), Double(Self.maxPiecesPerSegment)))
        assert(effectivePointCount >= 2, "A draw needs 2 points")
    }
}
