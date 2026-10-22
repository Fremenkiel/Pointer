import Testing

@testable import Geometry

@Suite("Camera flight")
struct CameraFlightTests {
    private static let start = Camera(center: Point(x: -100, y: 40), zoom: 0.5)
    private static let cover = Camera(center: Point(x: 300, y: 200), zoom: 4)
    private static let flight = CameraFlight(from: start, to: cover, start: 10)

    @Test("A flight starts at the camera, ends exactly at the target, and takes 0.35 s")
    func endpoints() {
        #expect(Self.flight.duration == 0.35)
        #expect(Self.flight.end == 10.35)
        #expect(Self.flight.camera(at: 10) == Self.start)
        #expect(Self.flight.camera(at: 10.35) == Self.cover)
        #expect(Self.flight.camera(at: 11) == Self.cover)
    }

    @Test("Before its start, a flight holds its first camera", arguments: [-1.0, 0, 9.99])
    func beforeStart(time: Double) {
        #expect(Self.flight.progress(at: time) == 0)
        #expect(Self.flight.camera(at: time) == Self.start)
    }

    @Test("The progress rises without a turn back and nears 1 at the end")
    func progress() {
        var last = -1.0
        for frame in 0...42 {
            let progress = Self.flight.progress(at: 10 + Double(frame) / 120)
            #expect(progress >= last)
            last = progress
        }
        #expect(last == 1)
    }

    @Test("The zoom of the middle of a flight lies between the two zooms on a log scale")
    func middle() {
        let camera = Self.flight.camera(at: 10.06)
        #expect(camera.zoom > Self.start.zoom && camera.zoom < Self.cover.zoom)
        #expect(camera.center.x > Self.start.center.x && camera.center.x < Self.cover.center.x)
    }

    @Test("A flight at one zoom moves the center by the progress")
    func pan() {
        let to = Camera(center: Point(x: 100, y: 40), zoom: 0.5)
        let flight = CameraFlight(from: Self.start, to: to, duration: 1, start: 0)
        let progress = flight.progress(at: 0.2)
        let camera = flight.camera(at: 0.2)
        #expect(camera.zoom == 0.5)
        #expect(abs(camera.center.x - (-100 + 200 * progress)) < 1e-9)
    }
}
