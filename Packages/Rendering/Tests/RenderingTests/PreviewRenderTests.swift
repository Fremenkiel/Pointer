import Foundation
import Geometry
import Model
import QuartzCore
import Synchronization
import Testing

@testable import Rendering

/// The preview render of a canvas at a leave (the M6 plan task 3.4, D-97, D-98).
@MainActor
@Suite("Preview render")
struct PreviewRenderTests {
    private func makeLayer(renderer: CanvasRenderer) -> CAMetalLayer {
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(width: 400, height: 240)
        renderer.setViewport(viewSize: Size(width: 200, height: 120), displayScale: 2)
        return layer
    }

    /// Draws frames until the preview arrives, and returns it.
    private func render(
        _ renderer: CanvasRenderer,
        layer: CAMetalLayer,
        camera: Camera,
        aspect: Double
    ) async throws -> PreviewImage {
        for _ in 0..<2_000 where renderer.isLoadingText || renderer.isLoadingCards {
            _ = renderer.renderFrame(into: layer, deadline: nil)
            try await Task.sleep(for: .milliseconds(1))
        }
        let result = Mutex<PreviewImage??>(nil)
        renderer.renderPreview(camera: camera, cardAspect: aspect) { image in
            result.withLock { $0 = .some(image) }
        }
        for _ in 0..<2_000 where result.withLock({ $0 == nil }) {
            _ = renderer.renderFrame(into: layer, deadline: nil)
            try await Task.sleep(for: .milliseconds(1))
        }
        let delivered = result.withLock { $0 }
        return try #require(delivered.flatMap { $0 }, "The preview arrived")
    }

    /// The image as an RGBA image of gray pixels, for the snapshot comparison.
    private static func rgba(_ image: PreviewImage) -> RenderedImage {
        var pixels: [UInt8] = []
        pixels.reserveCapacity(image.pixels.count * 4)
        for value in image.pixels {
            pixels += [value, value, value, 255]
        }
        return RenderedImage(width: image.width, height: image.height, pixels: pixels)
    }

    @Test("The region of a card covers the screen with the aspect of the card (D-98)")
    func region() {
        let view = Size(width: 200, height: 120)
        let camera = Camera(center: Point(x: 10, y: 20), zoom: 1)
        let wide = PreviewRenderer.region(camera: camera, cardAspect: 3, viewSize: view)
        #expect(wide.size == Size(width: 360, height: 120))
        #expect(wide.center == camera.center)
        let tall = PreviewRenderer.region(camera: camera, cardAspect: 0.5, viewSize: view)
        #expect(tall.size == Size(width: 200, height: 400))
        let zoomed = PreviewRenderer.region(
            camera: Camera(center: .zero, zoom: 2),
            cardAspect: 1,
            viewSize: view
        )
        #expect(zoomed.size == Size(width: 100, height: 100))
    }

    @Test("The preview of a known canvas matches its reference, with cards as frames only")
    func knownCanvas() async throws {
        let source = FakePreviews(data: try FakePreviews.png(width: 300, height: 150))
        let renderer = try CanvasRenderer(previews: source)
        let layer = makeLayer(renderer: renderer)
        let line = StrokeBuilder.stroke(
            (0...60).map { Point(x: -90 + Double($0) * 3, y: Double($0 % 7) * 4 - 40) },
            seed: 2
        )
        renderer.load([line])
        renderer.load([try TextRenderingTests.box("node -> next", at: Point(x: -80, y: 20))])
        let card = try CardStoreTests.card(
            1,
            frame: Rect(origin: Point(x: 20, y: -10), size: Size(width: 70, height: 50)),
            title: "Tree"
        )
        renderer.load([card])
        let image = try await render(
            renderer,
            layer: layer,
            camera: Camera(center: .zero, zoom: 1),
            aspect: 1.5
        )
        #expect(image.width == 512)
        #expect(image.height == 341)
        #expect(image.pixels.contains { $0 > 200 }, "The preview shows the content")
        Snapshot.assertMatches(Self.rgba(image), named: "preview-render")
    }

    @Test("The offscreen preview of a missing file equals the preview of the screen")
    func offscreen() async throws {
        let renderer = try CanvasRenderer()
        let layer = makeLayer(renderer: renderer)
        let line = StrokeBuilder.stroke(
            (0...40).map { Point(x: -60 + Double($0) * 3, y: Double($0 % 5) * 6 - 20) },
            seed: 3
        )
        renderer.load([line])
        var content = CanvasContent(canvasID: line.canvasID)
        try content.add(line)
        let camera = content.openCamera
        let screen = try await render(renderer, layer: layer, camera: camera, aspect: 1.25)
        let offscreen = try await PreviewMaker().render(
            content,
            camera: camera,
            cardAspect: 1.25,
            viewSize: Size(width: 200, height: 120)
        )
        #expect(offscreen.width == screen.width && offscreen.height == screen.height)
        let differing = zip(offscreen.pixels, screen.pixels).filter { abs(Int($0) - Int($1)) > 2 }
        #expect(differing.count <= offscreen.pixels.count / 200, "\(differing.count) pixels differ")
        #expect(offscreen.pixels.contains { $0 > 200 }, "The offscreen preview shows the ink")
    }

    @Test("A preview encodes to a PNG and decodes to the same pixels")
    func pngRoundTrip() async throws {
        let pixels = (0..<(64 * 48)).map { UInt8($0 % 256) }
        let image = PreviewImage(width: 64, height: 48, pixels: pixels)
        let data = try #require(image.pngData())
        var decoder = PreviewDecoder()
        guard let decoded = decoder.decode(data, step: 512) else {
            Issue.record("The PNG does not decode")
            return
        }
        #expect(decoded.width == 64 && decoded.height == 48)
        #expect(decoded.pixels == pixels)
    }

    @Test("A new preview shows in the parent without a read of its file")
    func showInParent() async throws {
        let source = FakePreviews(data: nil)
        let renderer = try CanvasRenderer(previews: source)
        let layer = makeLayer(renderer: renderer)
        let card = try CardStoreTests.card(1, title: "Tree")
        renderer.load([card])
        for _ in 0..<2_000 where renderer.isLoadingCards {
            _ = renderer.renderFrame(into: layer, deadline: nil)
            try await Task.sleep(for: .milliseconds(1))
        }
        let pixels = [UInt8](repeating: 255, count: 300 * 200)
        renderer.showPreview(PreviewImage(width: 300, height: 200, pixels: pixels), of: card.id)
        for _ in 0..<100 where renderer.renderFrame(into: layer, deadline: nil) {}
        let entry = renderer.engine.withRenderer { $0.previews?.entries[card.id] }
        #expect(entry?.width == 300)
        #expect(entry?.step == 512)
    }
}
