import Geometry
import Metal

/// A texture that ink passes draw into, with the camera that it shows.
///
/// The center of the texture shows the camera center. One canvas point covers
/// `pixelsPerCanvasPoint` pixels.
struct InkTarget {
    /// The texture.
    let texture: any MTLTexture
    /// The camera of the texture.
    let camera: Camera
    /// Pixels per view point, the display scale.
    let displayScale: Double

    /// Pixels per canvas point.
    var pixelsPerCanvasPoint: Double { displayScale * camera.zoom }

    /// The size of the texture, in pixels.
    var pixelSize: Size { Size(width: Double(texture.width), height: Double(texture.height)) }

    /// The canvas rectangle that the texture covers.
    var canvasRect: Rect {
        let size = Size(
            width: pixelSize.width / pixelsPerCanvasPoint,
            height: pixelSize.height / pixelsPerCanvasPoint
        )
        return Rect(origin: camera.center - size.halfDiagonal, size: size)
    }

    /// Returns the pixel of the texture under a canvas point, for the corner of a box or a card.
    /// The subtraction runs in Double before the conversion to Float (architecture.md 5.3). One
    /// computation for the text and the cards (review 3.4.4).
    ///
    /// - Precondition: `point` is finite.
    func pixelCorner(of point: Point) -> SIMD2<Float> {
        precondition(point.isFinite, "A corner needs a finite point, got \(point)")
        let delta = point - camera.center
        let pixels = pixelsPerCanvasPoint
        let size = pixelSize
        let corner = SIMD2(
            Float(size.width / 2 + delta.dx * pixels),
            Float(size.height / 2 + delta.dy * pixels)
        )
        assert(corner.x.isFinite && corner.y.isFinite, "A point maps to finite pixels")
        return corner
    }
}
