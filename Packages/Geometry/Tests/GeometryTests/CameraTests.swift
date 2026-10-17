import Testing

@testable import Geometry

@Suite("Camera")
struct CameraTests {
    private let viewSize = Size(width: 1000, height: 800)

    @Test("The view center shows the camera center")
    func center() {
        let camera = Camera(center: Point(x: 50, y: -20), zoom: 2)
        #expect(
            camera.canvasPoint(fromView: Point(x: 500, y: 400), viewSize: viewSize)
                == Point(x: 50, y: -20)
        )
    }

    @Test("View to canvas and back gives the same point", arguments: [0.25, 1.0, 8.0])
    func roundTrip(zoom: Double) {
        let camera = Camera(center: Point(x: 1_000_000, y: 1_000_000), zoom: zoom)
        let view = Point(x: 123.25, y: 777.5)
        let canvas = camera.canvasPoint(fromView: view, viewSize: viewSize)
        let back = camera.viewPoint(fromCanvas: canvas, viewSize: viewSize)
        #expect(abs(back.x - view.x) < 1e-6)
        #expect(abs(back.y - view.y) < 1e-6)
    }

    @Test("The view-to-canvas transform matches the point conversion")
    func transform() {
        let camera = Camera(center: Point(x: 30, y: 40), zoom: 4)
        let view = Point(x: 10, y: 20)
        let expected = camera.canvasPoint(fromView: view, viewSize: viewSize)
        #expect(camera.viewToCanvas(viewSize: viewSize).apply(to: view) == expected)
    }

    @Test("The visible rectangle has the view size divided by the zoom")
    func visibleRect() {
        let rect = Camera(center: .zero, zoom: 0.5).visibleRect(viewSize: viewSize)
        #expect(rect == Rect(minX: -1000, minY: -800, maxX: 1000, maxY: 800))
    }

    @Test("A pan moves the content with the finger")
    func pan() {
        let camera = Camera(center: .zero, zoom: 2).panned(byView: Vector(dx: 100, dy: -50))
        #expect(camera.center == Point(x: -50, y: 25))
    }

    @Test("A zoom keeps the canvas point under the anchor")
    func zoomAnchor() {
        let camera = Camera(center: Point(x: 10, y: 10), zoom: 1)
        let anchor = Point(x: 200, y: 600)
        let before = camera.canvasPoint(fromView: anchor, viewSize: viewSize)
        let zoomed = camera.zoomed(to: 3, anchor: anchor, viewSize: viewSize)
        let after = zoomed.canvasPoint(fromView: anchor, viewSize: viewSize)
        #expect(zoomed.zoom == 3)
        #expect(abs(after.x - before.x) < 1e-9)
        #expect(abs(after.y - before.y) < 1e-9)
    }

    @Test("A clamp keeps the zoom in the range", arguments: [(0.1, 0.25), (1.0, 1.0), (20.0, 8.0)])
    func clamp(zoom: Double, expected: Double) {
        let camera = Camera(center: .zero, zoom: zoom).clamped(to: 0.25...8)
        #expect(camera.zoom == expected)
    }
}
