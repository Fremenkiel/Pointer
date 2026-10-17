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

    private struct Pinch {
        let startCamera: Camera
        let startCentroid: Point
        var centroid: Point
    }

    private enum Animation {
        case none
        case deceleration(velocity: Vector)
        case spring(targetZoom: Double, anchor: Point)
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
        pinch = Pinch(startCamera: camera, startCentroid: centroid, centroid: centroid)
    }

    /// Zooms about the start midpoint by `scale` and pans by the movement of the midpoint.
    ///
    /// - Precondition: `scale` is positive and a pinch runs.
    mutating func updatePinch(scale: Double, centroid: Point) {
        precondition(scale > 0 && scale.isFinite, "Pinch scale must be positive, got \(scale)")
        guard var current = pinch else { preconditionFailure("No pinch to update") }
        current.centroid = centroid
        pinch = current
        let zoom = rubberBand(current.startCamera.zoom * scale)
        camera = current.startCamera
            .zoomed(to: zoom, anchor: current.startCentroid, viewSize: viewSize)
            .panned(byView: centroid - current.startCentroid)
    }

    /// Ends a pinch. A zoom past a limit springs back to the limit (CARD-06).
    mutating func endPinch() {
        guard let current = pinch else { return }
        pinch = nil
        let target = min(max(camera.zoom, zoomRange.lowerBound), zoomRange.upperBound)
        if target != camera.zoom {
            animation = .spring(targetZoom: target, anchor: current.centroid)
        }
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
        }
        return isAnimating
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
