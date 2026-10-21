import Geometry
import Metal
import Model
import QuartzCore
import Testing

@testable import Rendering

/// The eraser mask while the pencil moves (architecture.md 5.2, D-66). The drawable has
/// 400 x 240 pixels at scale 2, and the camera shows the canvas origin at zoom 1.
@MainActor
@Suite("Eraser mask")
struct EraserMaskTests {
    /// The eraser radius in view points (architecture.md 4.4).
    private static let radius = 8.0

    private func makeLayer(renderer: CanvasRenderer) -> CAMetalLayer {
        let layer = CAMetalLayer()
        renderer.configure(layer)
        // The capture copies the drawable, so the layer must allow a blit.
        layer.framebufferOnly = false
        layer.drawableSize = CGSize(width: 400, height: 240)
        renderer.setViewport(viewSize: Size(width: 200, height: 120), displayScale: 2)
        return layer
    }

    private func drain(_ renderer: CanvasRenderer, layer: CAMetalLayer) {
        for _ in 0..<100 where renderer.renderFrame(into: layer, deadline: nil) {}
    }

    /// A horizontal stroke through the view center.
    private static let line = StrokeBuilder.stroke(
        (0...60).map { Point(x: -60 + Double($0) * 2, y: 0) },
        seed: 1
    )

    /// Returns the view point of a canvas point at the standard camera.
    private static func view(_ x: Double, _ y: Double) -> Point {
        Point(x: 100 + x, y: 60 + y)
    }

    @Test("An eraser path across a stroke hides the ink under the stamps")
    func snapshot() throws {
        let renderer = try CanvasRenderer()
        let layer = makeLayer(renderer: renderer)
        renderer.load([Self.line])
        drain(renderer, layer: layer)
        renderer.beginErase(radius: Self.radius)
        for step in 0...8 {
            renderer.addEraserSample(Self.view(-2 + Double(step) * 0.5, -30 + Double(step) * 7.5))
        }
        let drawable = try #require(layer.nextDrawable())
        _ = renderer.engine.renderFrame(
            drawableSize: layer.drawableSize,
            deadline: nil,
            drawable: .drawable(drawable)
        )
        let pixels = try DrawableCapture.read(drawable.texture, renderer: renderer)
        let center = (120 * 400 + 200) * 4
        let ink = (120 * 400 + 200 + 2 * 40) * 4
        #expect(pixels[center] < 8, "The ink under the eraser is hidden")
        #expect(pixels[ink] > 240, "The ink beside the eraser stays")
        Snapshot.assertMatches(
            RenderedImage(width: 400, height: 240, pixels: pixels),
            named: "eraser-mask"
        )
    }

    @Test("The mask stops at the end of the gesture, and the frame loop can sleep again")
    func endAndSleep() throws {
        let renderer = try CanvasRenderer()
        let layer = makeLayer(renderer: renderer)
        renderer.load([Self.line])
        drain(renderer, layer: layer)
        renderer.beginErase(radius: Self.radius)
        renderer.addEraserSample(Self.view(0, 0))
        #expect(renderer.needsMoreFrames)
        drain(renderer, layer: layer)
        #expect(renderer.engine.withRenderer { $0.eraserMask.hasStamps })
        #expect(!renderer.needsMoreFrames)
        renderer.endErase()
        drain(renderer, layer: layer)
        #expect(renderer.engine.withRenderer { !$0.eraserMask.isActive })
        #expect(!renderer.needsMoreFrames)
        #expect(renderer.engine.sleepIfIdle())
    }
}
