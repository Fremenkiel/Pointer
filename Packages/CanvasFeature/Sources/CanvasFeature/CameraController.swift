import Foundation
import Geometry
import Model

/// Turns pan and pinch input into camera changes, with deceleration after a pan and a rubber
/// band past the zoom limits (architecture.md 6.1).
struct CameraController {
    /// The speed factor per millisecond of the deceleration, as `UIScrollView` normal.
    static let decelerationPerMillisecond = 0.998
    /// Below this speed, in view points per second, the deceleration stops.
    static let minimumSpeed = 10.0
    /// The resistance past a zoom limit: the zoom past the limit grows with this power.
    static let rubberBandExponent = 0.35
    /// The rate of the spring back to the zoom limit, per second.
    static let springRate = 14.0
    /// The spring stops when the zoom is this close to the limit, as a ratio.
    static let springTolerance = 0.001
    /// The largest time step of one animation frame. A longer pause does not jump.
    static let maximumStep: TimeInterval = 0.05
    /// The pinch-out exit leaves a card when the fingers lift at a raw zoom under this ratio of
    /// the minimum zoom (CARD-05, D-104). The raw zoom has no rubber band, so the threshold
    /// follows the fingers. Start value 0.6, to tune on the iPad (architecture.md 6.3).
    static let exitZoomRatio = 0.6
    /// The time of the open and the leave of a card (architecture.md 6.2, D-98).
    static let flightDuration: TimeInterval = 0.35
    /// The stiffness of the flight, times its duration: a critically damped spring that
    /// reaches 99.9 % of its way at the end, as (1 + 9.23) e^-9.23 = 0.001.
    static let flightStiffness = 9.23

    /// A camera flight in closed form: the progress is a critically damped spring of time.
    struct Flight: Equatable {
        let from: Camera
        let to: Camera
        let duration: TimeInterval
        var elapsed: TimeInterval = 0
    }

    private struct Pinch {
        let startCamera: Camera
        let startCentroid: Point
        var centroid: Point
        /// The zoom of the fingers without the rubber band.
        var rawZoom: Double
    }

    private enum Animation {
        case none
        case deceleration(velocity: Vector)
        case spring(targetZoom: Double, anchor: Point)
        case flight(Flight)
    }

    /// The camera.
    private(set) var camera: Camera
    /// The size of the view, in view points.
    var viewSize: Size
    /// The allowed zoom range.
    let zoomRange: ClosedRange<Double>
    private var pinch: Pinch?
    private var animation = Animation.none
    private var lastStepTime: TimeInterval?

    /// Makes a controller.
    ///
    /// - Precondition: The zoom range is above zero.
    init(camera: Camera, viewSize: Size, zoomRange: ClosedRange<Double> = Limits.zoomRange) {
        precondition(zoomRange.lowerBound > 0, "Zoom range \(zoomRange) must be above zero")
        self.camera = camera
        self.viewSize = viewSize
        self.zoomRange = zoomRange
    }

    /// `true` while a deceleration or a spring runs.
    var isAnimating: Bool {
        if case .none = animation { return false }
        return true
    }

    /// Stops a deceleration or a spring, for example when a finger or the pencil touches.
    mutating func stopAnimation() {
        animation = .none
        lastStepTime = nil
    }

    /// Moves the content with a finger.
    mutating func pan(byView delta: Vector) {
        stopAnimation()
        camera = camera.panned(byView: delta)
    }

    /// Starts the deceleration after a pan, with the finger speed in view points per second.
    mutating func endPan(velocity: Vector) {
        guard velocity.length >= Self.minimumSpeed, velocity.length.isFinite else { return }
        animation = .deceleration(velocity: velocity)
    }

    /// Starts a pinch at the midpoint of the fingers.
    mutating func beginPinch(centroid: Point) {
        stopAnimation()
        pinch = Pinch(
            startCamera: camera,
            startCentroid: centroid,
            centroid: centroid,
            rawZoom: camera.zoom
        )
    }

    /// Zooms about the start midpoint by `scale` and pans by the movement of the midpoint.
    ///
    /// - Precondition: `scale` is positive and a pinch runs.
    mutating func updatePinch(scale: Double, centroid: Point) {
        precondition(scale > 0 && scale.isFinite, "Pinch scale must be positive, got \(scale)")
        guard var current = pinch else { preconditionFailure("No pinch to update") }
        current.centroid = centroid
        current.rawZoom = current.startCamera.zoom * scale
        pinch = current
        let zoom = rubberBand(current.rawZoom)
        camera = current.startCamera
            .zoomed(to: zoom, anchor: current.startCentroid, viewSize: viewSize)
            .panned(byView: centroid - current.startCentroid)
    }

    /// The raw zoom under which a lift leaves a card (D-104).
    var exitZoom: Double { zoomRange.lowerBound * Self.exitZoomRatio }

    /// The progress of a pinch-out exit from 0 to 1: 0 at the minimum zoom and 1 where a lift
    /// leaves the card, measured on the shown zoom (D-109).
    var exitProgress: Double {
        let low = rubberBand(exitZoom)
        let span = zoomRange.lowerBound - low
        guard camera.zoom < zoomRange.lowerBound, span > 0 else { return 0 }
        return min(max((zoomRange.lowerBound - camera.zoom) / span, 0), 1)
    }

    /// The camera of a pinch-out exit at its end: the shown zoom where a lift leaves the card,
    /// about the midpoint of the fingers.
    var exitCamera: Camera {
        let anchor = pinch?.centroid ?? Point(x: viewSize.width / 2, y: viewSize.height / 2)
        return camera.zoomed(to: rubberBand(exitZoom), anchor: anchor, viewSize: viewSize)
    }

    /// Ends a pinch. Inside a card (`canLeave`), a lift at a raw zoom under the threshold leaves
    /// the card, and the camera stays for the minimize animation (CARD-05, D-104). Otherwise, a
    /// zoom past a limit springs back to the limit (CARD-06).
    ///
    /// - Returns: `true` if the lift leaves the card.
    mutating func endPinch(canLeave: Bool = false) -> Bool {
        guard let current = pinch else { return false }
        pinch = nil
        if canLeave, current.rawZoom < exitZoom {
            return true
        }
        let target = min(max(camera.zoom, zoomRange.lowerBound), zoomRange.upperBound)
        if target != camera.zoom {
            animation = .spring(targetZoom: target, anchor: current.centroid)
        }
        return false
    }

    /// Advances an animation to `time`.
    ///
    /// - Returns: `true` while the animation needs more frames.
    mutating func step(to time: TimeInterval) -> Bool {
        guard isAnimating else { return false }
        let delta = min(max(time - (lastStepTime ?? time), 0), Self.maximumStep)
        lastStepTime = time
        switch animation {
        case .none:
            return false
        case .deceleration(let velocity):
            decelerate(velocity: velocity, delta: delta)
        case .spring(let targetZoom, let anchor):
            spring(to: targetZoom, anchor: anchor, delta: delta)
        case .flight(var flight):
            flight.elapsed += delta
            camera = Self.camera(of: flight)
            animation = flight.elapsed >= flight.duration ? .none : .flight(flight)
        }
        return isAnimating
    }

    /// Starts a flight from the camera to `target` in `duration` seconds, for the open and the
    /// leave of a card (D-98). It ends exactly at `target`.
    ///
    /// - Precondition: `duration` is positive.
    mutating func fly(to target: Camera, duration: TimeInterval = flightDuration) {
        precondition(duration > 0 && duration.isFinite, "A flight takes time, got \(duration)")
        pinch = nil
        lastStepTime = nil
        animation = .flight(Flight(from: camera, to: target, duration: duration))
    }

    /// The progress of a running flight from 0 to 1, or `nil` without a flight.
    var flightProgress: Double? {
        guard case .flight(let flight) = animation else { return nil }
        return Self.progress(of: flight)
    }

    /// The progress of a flight: a critically damped spring, scaled to end at 1.
    static func progress(of flight: Flight) -> Double {
        let time = min(max(flight.elapsed / flight.duration, 0), 1)
        return min(reach(at: time) / reach(at: 1), 1)
    }

    /// The way of a critically damped spring at a time from 0 to 1 of the flight.
    private static func reach(at time: Double) -> Double {
        1 - (1 + flightStiffness * time) * exp(-flightStiffness * time)
    }

    /// The camera of a flight at its progress. The zoom moves on a log scale, and the center
    /// moves so that the fixed point of the zoom stays in place on the screen.
    static func camera(of flight: Flight) -> Camera {
        let progress = progress(of: flight)
        let (from, to) = (flight.from, flight.to)
        let zoom = from.zoom * pow(to.zoom / from.zoom, progress)
        let share =
            from.zoom == to.zoom
            ? progress : (1 / from.zoom - 1 / zoom) / (1 / from.zoom - 1 / to.zoom)
        let center = from.center + (to.center - from.center) * share
        return progress >= 1 ? to : Camera(center: center, zoom: zoom)
    }

    private mutating func decelerate(velocity: Vector, delta: TimeInterval) {
        camera = camera.panned(byView: velocity * delta)
        let next = velocity * pow(Self.decelerationPerMillisecond, delta * 1000)
        animation = next.length < Self.minimumSpeed ? .none : .deceleration(velocity: next)
    }

    private mutating func spring(to target: Double, anchor: Point, delta: TimeInterval) {
        let zoom = target + (camera.zoom - target) * exp(-Self.springRate * delta)
        let isDone = abs(zoom / target - 1) < Self.springTolerance
        camera = camera.zoomed(to: isDone ? target : zoom, anchor: anchor, viewSize: viewSize)
        if isDone {
            animation = .none
        }
    }

    /// Returns the zoom with resistance past the limits.
    func rubberBand(_ zoom: Double) -> Double {
        if zoom < zoomRange.lowerBound {
            return zoomRange.lowerBound * pow(zoom / zoomRange.lowerBound, Self.rubberBandExponent)
        }
        if zoom > zoomRange.upperBound {
            return zoomRange.upperBound * pow(zoom / zoomRange.upperBound, Self.rubberBandExponent)
        }
        return zoom
    }
}
