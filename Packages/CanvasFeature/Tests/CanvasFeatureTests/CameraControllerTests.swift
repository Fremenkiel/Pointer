import Geometry
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
        subject.endPinch()
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

@Suite("Camera flight")
struct CameraFlightTests {
    private static let start = Camera(center: Point(x: -100, y: 40), zoom: 0.5)
    private static let cover = Camera(center: Point(x: 300, y: 200), zoom: 4)

    @Test("A flight starts at the camera, ends exactly at the target, and takes 0.35 s")
    func endpoints() {
        let viewSize = Size(width: 400, height: 300)
        var controller = CameraController(camera: Self.start, viewSize: viewSize)
        controller.fly(to: Self.cover)
        #expect(controller.flightProgress == 0)
        var time = 1.0
        var steps = 0
        while controller.step(to: time), steps < 1_000 {
            time += 1.0 / 120
            steps += 1
        }
        #expect(controller.camera == Self.cover)
        #expect(controller.flightProgress == nil)
        // The first step only notes the time, so 42 frames of 1/120 s cover 0.35 s.
        #expect((42...43).contains(steps))
    }

    @Test("The progress rises without a turn back and nears 1 at the end")
    func progress() {
        var last = -1.0
        for frame in 0...42 {
            let flight = CameraController.Flight(
                from: Self.start,
                to: Self.cover,
                duration: 0.35,
                elapsed: Double(frame) / 120
            )
            let progress = CameraController.progress(of: flight)
            #expect(progress >= last)
            last = progress
        }
        #expect(last == 1)
    }

    @Test("The zoom of the middle of a flight lies between the two zooms on a log scale")
    func middle() {
        let flight = CameraController.Flight(
            from: Self.start,
            to: Self.cover,
            duration: 0.35,
            elapsed: 0.35
        )
        #expect(CameraController.camera(of: flight) == Self.cover)
        let half = CameraController.Flight(
            from: Self.start,
            to: Self.cover,
            duration: 0.35,
            elapsed: 0.06
        )
        let camera = CameraController.camera(of: half)
        #expect(camera.zoom > Self.start.zoom && camera.zoom < Self.cover.zoom)
        #expect(camera.center.x > Self.start.center.x && camera.center.x < Self.cover.center.x)
    }
}
