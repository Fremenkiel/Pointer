import Foundation
import Geometry
import Metal
import Model
import QuartzCore
import Testing

@testable import Rendering

/// The text of the committed layer (architecture.md 5.4, D-29, D-82). The drawable has 400 x 240
/// pixels at scale 2, so the view shows 200 x 120 view points.
@MainActor
@Suite("Text rendering")
struct TextRenderingTests {
    /// The eraser radius in view points (architecture.md 4.4).
    private static let radius = 8.0

    /// Makes a text box at `origin`.
    static func box(_ text: String, at origin: Point, id: UInt8 = 1) throws -> TextBox {
        let device = DeviceID(
            rawValue: UUID(uuid: (9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        )
        return try TextBox(
            id: TextBoxID(rawValue: UUID(uuid: (8, id, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))),
            meta: RecordMeta(created: HybridTimestamp(wallMillis: 1, counter: 0, device: device)),
            canvasID: CanvasID(
                rawValue: UUID(uuid: (7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
            ),
            origin: origin,
            text: text,
            sortKey: FractionalIndex(rawValue: "V")
        )
    }

    private func makeLayer(renderer: CanvasRenderer) -> CAMetalLayer {
        let layer = CAMetalLayer()
        renderer.configure(layer)
        // The capture copies the drawable, so the layer must allow a blit.
        layer.framebufferOnly = false
        layer.drawableSize = CGSize(width: 400, height: 240)
        renderer.setViewport(viewSize: Size(width: 200, height: 120), displayScale: 2)
        return layer
    }

    /// Waits for the text layout of a load, which runs off the render thread (D-92), and draws
    /// the frames until the renderer needs no more.
    private func drain(_ renderer: CanvasRenderer, layer: CAMetalLayer) {
        for _ in 0..<2_000 where renderer.isLoadingText {
            _ = renderer.renderFrame(into: layer, deadline: nil)
            Thread.sleep(forTimeInterval: 0.001)
        }
        for _ in 0..<100 where renderer.renderFrame(into: layer, deadline: nil) {}
    }

    /// Draws one frame into a new drawable and reads it. The frame runs on the frame work
    /// itself, because the engine skips a frame without a change. It takes nothing from the
    /// inbox, so a test drains the frames first.
    private func capture(_ renderer: CanvasRenderer, layer: CAMetalLayer) throws -> RenderedImage {
        let drawable = try #require(layer.nextDrawable())
        let size = layer.drawableSize
        _ = renderer.engine.withRenderer { frames in
            frames.renderFrame(drawableSize: size, deadline: nil, drawable: .drawable(drawable))
        }
        let pixels = try DrawableCapture.read(drawable.texture, renderer: renderer)
        return RenderedImage(width: 400, height: 240, pixels: pixels)
    }

    @Test("A text box shows its text at the zoom of the camera", arguments: [0.5, 1.0, 4.0])
    func snapshot(zoom: Double) throws {
        let renderer = try CanvasRenderer()
        let box = try Self.box("let x = [1, 2]\nnode -> next", at: Point(x: -60, y: -18))
        let image = try renderer.renderImage(
            of: [],
            textBoxes: [box],
            camera: Camera(center: .zero, zoom: zoom),
            viewSize: Size(width: 200, height: 120),
            displayScale: 2
        )
        let lit = (0..<(image.width * image.height)).filter { image.pixels[$0 * 4 + 1] > 128 }
        #expect(!lit.isEmpty, "The text shows")
        Snapshot.assertMatches(image, named: "text-zoom\(zoom)")
    }

    @Test("The eraser mask hides the ink and leaves the text (D-82)")
    func underEraserMask() throws {
        let renderer = try CanvasRenderer()
        let layer = makeLayer(renderer: renderer)
        let line = StrokeBuilder.stroke(
            (0...60).map { Point(x: -60 + Double($0) * 2, y: 0) },
            seed: 1
        )
        renderer.load([line])
        // The text lies above the line, so that the ink and the text have pixels of their own.
        renderer.load([try Self.box("MMMMMMMMMM", at: Point(x: -50, y: -40))])
        drain(renderer, layer: layer)
        let before = try capture(renderer, layer: layer)
        renderer.setEraserReady(true)
        renderer.beginErase(radius: Self.radius)
        for step in 0...10 {
            renderer.addEraserSample(Point(x: 100, y: 10 + Double(step) * 7))
        }
        // The frames take the samples from the inbox, and the capture shows the mask.
        drain(renderer, layer: layer)
        let image = try capture(renderer, layer: layer)
        // The pixels of text in the eraser band keep their value.
        let textPixels = (0..<(400 * 240)).filter { pixel in
            abs(pixel % 400 - 200) < 10 && pixel / 400 < 100 && before.pixels[pixel * 4 + 1] > 200
        }
        #expect(!textPixels.isEmpty)
        for pixel in textPixels {
            #expect(image.pixels[pixel * 4 + 1] > 200)
        }
        #expect(before.gray(x: 200, y: 120) > 240, "The ink under the eraser shows before")
        #expect(image.gray(x: 200, y: 120) < 8, "The ink under the eraser is hidden")
        #expect(image.gray(x: 200 + 40, y: 120) > 240, "The ink beside the eraser stays")
        Snapshot.assertMatches(image, named: "text-under-eraser-mask")
    }

    @Test("A moved text box leaves no old pixels, and its new place equals a fresh draw")
    func moveRedraw() throws {
        let renderer = try CanvasRenderer()
        let layer = makeLayer(renderer: renderer)
        let start = try Self.box("node", at: Point(x: -60, y: -30))
        let moved = try Self.box("node", at: Point(x: 10, y: 10))
        renderer.load([start])
        drain(renderer, layer: layer)
        renderer.changeTextBoxes(removing: [], adding: [moved])
        drain(renderer, layer: layer)
        let image = try capture(renderer, layer: layer)
        let fresh = try renderer.renderImage(
            of: [],
            textBoxes: [moved],
            camera: Camera(center: .zero, zoom: 1),
            viewSize: Size(width: 200, height: 120),
            displayScale: 2
        )
        let limit = Int(Double(400 * 240) * Snapshot.tolerance)
        #expect(Snapshot.differingPixels(image, fresh) <= limit)
        Snapshot.assertMatches(image, named: "text-move-redraw")
    }

    @Test("A removed text box leaves the screen")
    func remove() throws {
        let renderer = try CanvasRenderer()
        let layer = makeLayer(renderer: renderer)
        let box = try Self.box("gone", at: Point(x: -20, y: -10))
        renderer.load([box])
        drain(renderer, layer: layer)
        renderer.changeTextBoxes(removing: [box.id], adding: [])
        drain(renderer, layer: layer)
        let image = try capture(renderer, layer: layer)
        #expect(image.pixels.enumerated().allSatisfy { $0.offset % 4 == 3 || $0.element < 4 })
    }
}
