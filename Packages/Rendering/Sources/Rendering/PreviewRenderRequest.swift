import Dispatch
import Geometry

/// A request of the preview of the shown canvas, from the main actor to the render thread
/// (the M6 plan task 3.4).
struct PreviewRenderRequest: Sendable {
    /// The open camera of the canvas: the camera of CARD-03.
    let camera: Camera
    /// The width over the height of the card of the canvas.
    let cardAspect: Double
    /// The longer side of the preview in pixels.
    let size: Int
    /// Gets the image, or `nil` if the render failed. It runs off the main actor.
    let completion: @Sendable (PreviewImage?) -> Void

    /// Ends the request with `nil` on a queue of its own. The callers hold the inbox lock or the
    /// frame lock, so a completion that calls back into its renderer would lock twice (review
    /// after M9, section 3.2, item 2).
    func endWithoutImage() {
        let completion = completion
        DispatchQueue.global(qos: .utility).async { completion(nil) }
    }
}
