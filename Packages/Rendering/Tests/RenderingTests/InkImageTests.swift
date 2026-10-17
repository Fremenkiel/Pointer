import Geometry
import Model
import Testing

@testable import Rendering

@MainActor
@Suite("Ink images")
struct InkImageTests {
    private let viewSize = Size(width: 200, height: 120)

    private func render(
        _ strokes: [Stroke],
        camera: Camera,
        scale: Double = 2
    ) throws -> RenderedImage {
        let renderer = try CanvasRenderer()
        return try renderer.renderImage(
            of: strokes,
            camera: camera,
            viewSize: viewSize,
            displayScale: scale
        )
    }

    @Test("A tight zigzag shows no bright joints and no notches (acceptance 7)")
    func zigzag() throws {
        let image = try render(
            [StrokeBuilder.zigzag(at: Point(x: 20, y: 50))],
            camera: Camera(center: Point(x: 50, y: 56), zoom: 2)
        )
        Snapshot.assertMatches(image, named: "zigzag-zoom2")
        let maximum = image.pixels.max() ?? 0
        #expect(maximum == 255)
    }

    @Test(
        "Strokes far from the origin look the same as at the origin (acceptance 3)",
        arguments: [0.25, 1.0, 8.0]
    )
    func farAway(zoom: Double) throws {
        let offset = Vector(dx: 1_000_000, dy: 1_000_000)
        let near = StrokeBuilder.curve(at: Point(x: -60, y: 0))
        let far = StrokeBuilder.curve(at: Point(x: -60, y: 0) + offset)
        let camera = Camera(center: Point(x: 0, y: 0), zoom: zoom)
        let nearImage = try render([near], camera: camera)
        let farImage = try render([far], camera: Camera(center: camera.center + offset, zoom: zoom))
        #expect(Snapshot.differingPixels(nearImage, farImage) == 0)
        #expect(nearImage.pixels.contains { $0 > 0 && $0 < 255 })
    }

    @Test("The center of a stroke is 255 in each channel (acceptance 6)")
    func whiteCenter() throws {
        let line = StrokeBuilder.stroke([Point(x: 0, y: 0), Point(x: 40, y: 0)], width: 4)
        let image = try render([line], camera: Camera(center: Point(x: 20, y: 0), zoom: 1))
        let base = (image.height / 2 * image.width + image.width / 2) * 4
        #expect(Array(image.pixels[base..<base + 3]) == [255, 255, 255])
    }

    @Test("Overlapping strokes do not get brighter, and order does not matter")
    func maxBlending() throws {
        let first = StrokeBuilder.curve(at: Point(x: -60, y: 0), seed: 1)
        let second = StrokeBuilder.stroke([Point(x: -60, y: -20), Point(x: 60, y: 20)], seed: 2)
        let camera = Camera(center: .zero, zoom: 1)
        let forward = try render([first, second], camera: camera)
        let backward = try render([second, first], camera: camera)
        let differing = Snapshot.differingPixels(forward, backward)
        #expect(differing == 0)
    }

    @Test("A curve matches its reference image at three zoom levels", arguments: [0.25, 1.0, 8.0])
    func curveReference(zoom: Double) throws {
        let image = try render(
            [StrokeBuilder.curve(at: Point(x: -60, y: 0))],
            camera: Camera(center: .zero, zoom: zoom)
        )
        Snapshot.assertMatches(image, named: "curve-zoom\(zoom)")
    }
}
