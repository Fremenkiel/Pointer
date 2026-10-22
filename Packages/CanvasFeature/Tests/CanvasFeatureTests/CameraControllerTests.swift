import Geometry
import Model
import Testing

@testable import CanvasFeature

@Suite("Camera controller")
struct CameraControllerTests {
    private let viewSize = Size(width: 1000, height: 800)

    private func controller(zoom: Double = 1) -> CameraController {
        CameraController(camera: Camera(center: .zero, zoom: zoom), viewSize: viewSize)
    }

    @Test("A pan moves the content with the finger")
    func pan() {
        var subject = controller(zoom: 2)
        subject.pan(byView: Vector(dx: 100, dy: 0))
        #expect(subject.camera.center == Point(x: -50, y: 0))
    }

    @Test("A pinch zooms about the finger midpoint")
    func pinchAnchor() {
        var subject = controller()
        let centroid = Point(x: 200, y: 300)
        let before = subject.camera.canvasPoint(fromView: centroid, viewSize: viewSize)
        subject.beginPinch(centroid: centroid)
        subject.updatePinch(scale: 2, centroid: centroid)
        let after = subject.camera.canvasPoint(fromView: centroid, viewSize: viewSize)
        #expect(subject.camera.zoom == 2)
        #expect(before.distance(to: after) < 1e-9)
    }

    @Test("A pinch pans with the midpoint")
    func pinchPan() {
        var subject = controller()
        subject.beginPinch(centroid: Point(x: 500, y: 400))
        subject.updatePinch(scale: 1, centroid: Point(x: 600, y: 400))
        #expect(subject.camera.center == Point(x: -100, y: 0))
    }

    @Test("A zoom past the limit meets resistance and springs back")
    func rubberBand() {
        var subject = controller(zoom: 0.25)
        subject.beginPinch(centroid: Point(x: 500, y: 400))
        subject.updatePinch(scale: 0.5, centroid: Point(x: 500, y: 400))
        #expect(subject.camera.zoom < 0.25)
        #expect(subject.camera.zoom > 0.125)
        _ = subject.endPinch()
        #expect(subject.isAnimating)
        var time = 0.0
        for _ in 0..<200 where subject.step(to: time) {
            time += 1.0 / 120
        }
        #expect(subject.camera.zoom == 0.25)
        #expect(!subject.isAnimating)
    }

    @Test("Above the largest zoom the band also resists", arguments: [16.0, 64.0])
    func upperBand(zoom: Double) {
        let subject = controller()
        let banded = subject.rubberBand(zoom)
        #expect(banded > 8 && banded < zoom)
        #expect(subject.rubberBand(1) == 1)
    }

    @Test("A pan with speed decelerates and stops")
    func deceleration() {
        var subject = controller()
        subject.pan(byView: .zero)
        subject.endPan(velocity: Vector(dx: 2000, dy: 0))
        var time = 0.0
        var frames = 0
        for _ in 0..<2000 where subject.step(to: time) {
            time += 1.0 / 120
            frames += 1
        }
        #expect(frames > 10)
        #expect(!subject.isAnimating)
        #expect(subject.camera.center.x < -100)
    }

    @Test("A slow release does not decelerate, and a touch stops the motion")
    func stop() {
        var subject = controller()
        subject.endPan(velocity: Vector(dx: 5, dy: 0))
        #expect(!subject.isAnimating)
        subject.endPan(velocity: Vector(dx: 500, dy: 0))
        subject.stopAnimation()
        #expect(!subject.isAnimating)
        let isStepping = subject.step(to: 1)
        #expect(!isStepping)
    }
}

@Suite("Camera flight of the controller")
struct CameraControllerFlightTests {
    private static let start = Camera(center: Point(x: -100, y: 40), zoom: 0.5)
    private static let cover = Camera(center: Point(x: 300, y: 200), zoom: 4)

    @Test("A flight steps from its start time, ends exactly at the target, and takes 0.35 s")
    func endpoints() {
        let viewSize = Size(width: 400, height: 300)
        var controller = CameraController(camera: Self.start, viewSize: viewSize)
        let flight = controller.fly(to: Self.cover, start: 1)
        #expect(flight.from == Self.start)
        #expect(controller.flightProgress == 0)
        var time = 1.0
        var steps = 0
        while controller.step(to: time), steps < 1_000 {
            #expect(controller.camera == flight.camera(at: time))
            time += 1.0 / 120
            steps += 1
        }
        #expect(controller.camera == Self.cover)
        #expect(controller.flightProgress == nil)
        // 42 frames of 1/120 s cover 0.35 s.
        #expect((42...43).contains(steps))
    }

    @Test("A step after a long pause jumps to the camera of its time")
    func pause() {
        let viewSize = Size(width: 400, height: 300)
        var controller = CameraController(camera: Self.start, viewSize: viewSize)
        let flight = controller.fly(to: Self.cover, start: 1)
        let isAnimating = controller.step(to: 1.2)
        #expect(isAnimating)
        #expect(controller.camera == flight.camera(at: 1.2))
        #expect(controller.flightProgress == flight.progress(at: 1.2))
    }
}

@Suite("Pinch-out exit")
struct PinchExitTests {
    private static let viewSize = Size(width: 400, height: 300)
    private static let center = Point(x: 200, y: 150)

    /// Pinches from `zoom` until the raw zoom is `factor` times the exit zoom, and lifts.
    private static func lift(from zoom: Double, at factor: Double, canLeave: Bool) -> Bool {
        var controller = CameraController(
            camera: Camera(center: .zero, zoom: zoom),
            viewSize: viewSize
        )
        controller.beginPinch(centroid: center)
        let raw = controller.exitZoom * factor
        controller.updatePinch(scale: raw / zoom, centroid: center)
        return controller.endPinch(canLeave: canLeave)
    }

    @Test(
        "A lift just under the threshold leaves the card, and just over it springs back (D-104)",
        arguments: [Limits.minZoom, Limits.standardZoom]
    )
    func threshold(zoom: Double) {
        #expect(Self.lift(from: zoom, at: 0.99, canLeave: true))
        #expect(!Self.lift(from: zoom, at: 1.01, canLeave: true))
    }

    @Test("On the root canvas, a lift under the threshold springs back (CARD-06)")
    func root() {
        var controller = CameraController(
            camera: Camera(center: .zero, zoom: Limits.minZoom),
            viewSize: Self.viewSize
        )
        controller.beginPinch(centroid: Self.center)
        controller.updatePinch(scale: 0.1, centroid: Self.center)
        let leaves = controller.endPinch(canLeave: false)
        #expect(!leaves)
        #expect(controller.isAnimating)
        var time = 1.0
        for _ in 0..<1_000 where controller.step(to: time) { time += 1.0 / 120 }
        #expect(controller.camera.zoom == Limits.minZoom)
    }

    @Test("The exit progress is 0 at the minimum zoom and 1 at the threshold")
    func progress() {
        var controller = CameraController(
            camera: Camera(center: .zero, zoom: Limits.minZoom),
            viewSize: Self.viewSize
        )
        #expect(controller.exitProgress == 0)
        controller.beginPinch(centroid: Self.center)
        controller.updatePinch(scale: CameraController.exitZoomRatio, centroid: Self.center)
        #expect(abs(controller.exitProgress - 1) < 1e-9)
        controller.updatePinch(scale: 0.8, centroid: Self.center)
        #expect(controller.exitProgress > 0 && controller.exitProgress < 1)
        #expect(
            abs(controller.exitCamera.zoom - controller.rubberBand(controller.exitZoom)) < 1e-12
        )
    }
}

@Suite("Fixed zoom inside a card")
struct FixedZoomTests {
    private static let viewSize = Size(width: 400, height: 300)
    private static let start = Camera(center: Point(x: 30, y: -20), zoom: 1)

    private static func controller() -> CameraController {
        CameraController(
            camera: start,
            viewSize: viewSize,
            zoomRange: Limits.standardZoom...Limits.standardZoom
        )
    }

    @Test("A pinch inside a card shows no zoom and no pan, and drives the exit (D-119)")
    func pinchShowsNoZoom() {
        var subject = Self.controller()
        subject.beginPinch(centroid: Point(x: 50, y: 60))
        subject.updatePinch(scale: 0.85, centroid: Point(x: 90, y: 100))
        #expect(subject.shownCamera == Self.start)
        #expect(subject.camera.center == Self.start.center)
        #expect(subject.exitProgress > 0 && subject.exitProgress < 1)
        subject.updatePinch(scale: CameraController.exitZoomRatio, centroid: Point(x: 90, y: 100))
        #expect(abs(subject.exitProgress - 1) < 1e-9)
        #expect(subject.exitCamera.center == Self.start.center)
    }

    @Test("A lift above the threshold springs back to zoom 1 at the same center")
    func springBack() {
        var subject = Self.controller()
        subject.beginPinch(centroid: Point(x: 50, y: 60))
        subject.updatePinch(scale: CameraController.exitZoomRatio * 1.05, centroid: .zero)
        let leaves = subject.endPinch(canLeave: true)
        #expect(!leaves)
        var time = 1.0
        for _ in 0..<1_000 where subject.step(to: time) { time += 1.0 / 120 }
        #expect(subject.camera == Self.start)
        #expect(subject.exitProgress == 0)
    }

    @Test("A lift under the threshold leaves, and a pinch-in shows nothing")
    func leaveAndPinchIn() {
        var subject = Self.controller()
        subject.beginPinch(centroid: Point(x: 50, y: 60))
        subject.updatePinch(scale: CameraController.exitZoomRatio * 0.95, centroid: .zero)
        let leaves = subject.endPinch(canLeave: true)
        #expect(leaves)
        var inside = Self.controller()
        inside.beginPinch(centroid: Point(x: 50, y: 60))
        inside.updatePinch(scale: 3, centroid: Point(x: 70, y: 60))
        #expect(inside.shownCamera == Self.start)
        #expect(inside.exitProgress == 0)
        let insideLeaves = inside.endPinch(canLeave: true)
        #expect(!insideLeaves)
    }

    @Test("A pan inside a card moves the camera at zoom 1")
    func pan() {
        var subject = Self.controller()
        subject.pan(byView: Vector(dx: 100, dy: 0))
        #expect(subject.shownCamera == Camera(center: Point(x: -70, y: -20), zoom: 1))
    }
}
