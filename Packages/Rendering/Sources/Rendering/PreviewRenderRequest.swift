import Geometry

/// A request of the preview of the shown canvas, from the main actor to the render thread
/// (m6-plan.md task 3.4).
struct PreviewRenderRequest: Sendable {
    /// The open camera of the canvas: the camera of CARD-03.
    let camera: Camera
    /// The width over the height of the card of the canvas.
    let cardAspect: Double
    /// The longer side of the preview in pixels.
    let size: Int
    /// Gets the image, or `nil` if the render failed. It runs off the main actor.
    let completion: @Sendable (PreviewImage?) -> Void
}
