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
}
