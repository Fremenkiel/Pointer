import Foundation
import Geometry
import Model
import Rendering

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
    /// follows the fingers. The start value was 0.6. The product owner asked for an earlier
    /// leave on the iPad on 2026-10-22, so the value is 0.7 (architecture.md 6.3).
    static let exitZoomRatio = 0.7

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
        case flight(CameraFlight)
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
    /// A spring back to a zoom limit that waits for the end of a pencil stroke (D-135).
    private var heldSpring: Animation?

    /// Makes a controller.
    ///
    /// - Precondition: The zoom range is above zero.
    init(camera: Camera, viewSize: Size, zoomRange: ClosedRange<Double> = Limits.zoomRange) {
        precondition(zoomRange.lowerBound > 0, "Zoom range \(zoomRange) must be above zero")
        self.camera = camera
        self.viewSize = viewSize
        self.zoomRange = zoomRange
    }

    /// The zoom range of a canvas: the root canvas zooms, and a canvas inside a card shows only
    /// zoom 1 (D-119).
    static func zoomRange(level: Int) -> ClosedRange<Double> {
        precondition(level >= 0, "Level \(level)")
        return level == 0 ? Limits.zoomRange : Limits.standardZoom...Limits.standardZoom
    }

    /// Makes the controller of a canvas at `level`, before its view has a size. A canvas inside a
    /// card shows only zoom 1, also from a camera of an older version (D-119), so the zoom of
    /// `camera` moves into the range. The center stays.
    init(_ camera: Camera, _ level: Int) {
        let range = Self.zoomRange(level: level)
        let zoom = min(max(camera.zoom, range.lowerBound), range.upperBound)
        self.init(
            camera: Camera(center: camera.center, zoom: zoom),
            viewSize: .zero,
            zoomRange: range
        )
    }

    /// `true` inside a card: the range holds one zoom, so a pinch shows no zoom and only drives
    /// the pinch-out exit (D-119).
    var isZoomFixed: Bool { zoomRange.lowerBound == zoomRange.upperBound }

    /// The camera that the screen shows. Inside a card, the zoom of a pinch does not show: the
    /// zoom stays at the one zoom of the range (D-119).
    var shownCamera: Camera {
        guard isZoomFixed else { return camera }
        return Camera(center: camera.center, zoom: zoomRange.lowerBound)
    }

    /// The center of the view, the anchor of a pinch inside a card.
    private var viewCenter: Point { Point(x: viewSize.width / 2, y: viewSize.height / 2) }

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

    /// `true` while a spring back waits for the end of a pencil stroke (D-135).
    var isSpringHeld: Bool { heldSpring != nil }

    /// Holds a running spring back until `releaseSpring()`, so that the camera stays while the
    /// pencil draws (D-135). Without a spring, it does nothing.
    mutating func holdSpring() {
        guard case .spring = animation else { return }
        heldSpring = animation
        stopAnimation()
    }

    /// Starts the spring that `holdSpring()` held. Without one, it does nothing.
    mutating func releaseSpring() {
        guard let held = heldSpring else { return }
        heldSpring = nil
        lastStepTime = nil
        animation = held
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
        // The new pinch springs back at its own end.
        heldSpring = nil
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
        // Inside a card, the zoom about the view center keeps the center, and the midpoint does
        // not pan (D-119).
        guard !isZoomFixed else {
            camera = current.startCamera.zoomed(to: zoom, anchor: viewCenter, viewSize: viewSize)
            return
        }
        camera = current.startCamera
            .zoomed(to: zoom, anchor: current.startCentroid, viewSize: viewSize)
            .panned(byView: centroid - current.startCentroid)
    }

    /// The raw zoom under which a lift leaves a card (D-104).
    var exitZoom: Double { zoomRange.lowerBound * Self.exitZoomRatio }

    /// The progress of a pinch-out exit from 0 to 1: 0 at the minimum zoom and 1 where a lift
    /// leaves the card, measured on the shown zoom (D-109).
    var exitProgress: Double {
        PinchExit.progress(
            zoom: camera.zoom,
            minimumZoom: zoomRange.lowerBound,
            exitZoom: rubberBand(exitZoom)
        )
    }

    /// The effect of the minimize flight of a pinch-out exit on the render thread, with the
    /// same zooms as `exitProgress` (D-121).
    var pinchExitEffect: RenderFlight.Effect {
        .pinchExit(minimumZoom: zoomRange.lowerBound, exitZoom: rubberBand(exitZoom))
    }

    /// The camera of a pinch-out exit at its end: the shown zoom where a lift leaves the card,
    /// about the midpoint of the fingers.
    var exitCamera: Camera {
        let anchor = isZoomFixed ? viewCenter : pinch?.centroid ?? viewCenter
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
            let anchor = isZoomFixed ? viewCenter : current.centroid
            animation = .spring(targetZoom: target, anchor: anchor)
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
        case .flight(let flight):
            // The camera comes from the time alone, as on the render thread (D-121).
            camera = flight.camera(at: time)
            if time >= flight.end { animation = .none }
        }
        return isAnimating
    }

    /// Starts a flight from the camera to `target`, for the open and the leave of a card
    /// (D-98). It starts at `start`, in the time base of the frame times, and ends exactly at
    /// `target`.
    ///
    /// - Precondition: `start` is finite.
    /// - Returns: The flight, for the render thread (D-121).
    mutating func fly(to target: Camera, start: TimeInterval) -> CameraFlight {
        precondition(start.isFinite, "A flight starts at a finite time, got \(start)")
        let flight = CameraFlight(from: camera, to: target, start: start)
        pinch = nil
        heldSpring = nil
        lastStepTime = nil
        animation = .flight(flight)
        return flight
    }

    /// The progress of a running flight from 0 to 1 at the last step, or `nil` without a
    /// flight.
    var flightProgress: Double? {
        guard case .flight(let flight) = animation else { return nil }
        return flight.progress(at: lastStepTime ?? flight.start)
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
