import Geometry

/// A camera flight that the render thread plays by itself (D-121). The render thread takes the
/// camera of each frame from the closed form of the flight at the target time of the frame, so a
/// blocked main thread does not stop the animation.
public struct RenderFlight: Sendable, Equatable {
    /// What the progress of a flight also drives.
    public enum Effect: Sendable, Equatable {
        /// Only the camera.
        case none
        /// The open of a card: the parent weight falls from 1 to 0 (D-98).
        case open
        /// The leave into a card: the parent weight rises from 0 to 1 (D-98).
        case leave
        /// The minimize animation of a pinch-out exit: the exit progress follows the zoom of the
        /// flight, from 0 at `minimumZoom` to 1 at `exitZoom` (CARD-05, D-104).
        case pinchExit(minimumZoom: Double, exitZoom: Double)
    }

    /// The flight of the camera.
    public let flight: CameraFlight
    /// What the progress also drives.
    public let effect: Effect
    /// The one zoom of a canvas inside a card, or `nil`. The screen then shows the center of the
    /// flight at this zoom, as the main thread does (D-119).
    public let fixedZoom: Double?

    /// Makes a flight for the render thread.
    ///
    /// - Precondition: `fixedZoom` is positive if it is set.
    public init(flight: CameraFlight, effect: Effect, fixedZoom: Double?) {
        precondition((fixedZoom ?? 1) > 0, "A fixed zoom is positive, got \(fixedZoom ?? 0)")
        self.flight = flight
        self.effect = effect
        self.fixedZoom = fixedZoom
    }

    /// The camera that the screen shows at `time`.
    func shownCamera(at time: Double) -> Camera {
        let camera = flight.camera(at: time)
        guard let fixedZoom else { return camera }
        return Camera(center: camera.center, zoom: fixedZoom)
    }
}
