import Geometry
import Metal
import QuartzCore
import Testing

@testable import Rendering

/// The eraser mask texture exists only while the eraser is the tool (D-78, M-06 of
/// the M4 fix plan).
@MainActor
@Suite("Eraser mask lifetime")
struct EraserMaskLifetimeTests {
    /// The frames that the test may draw until the renderer needs no more.
    private static let maxFrames = 200

    @Test("No mask texture exists while the pen is the tool")
    func maskFollowsTheTool() throws {
        let renderer = try CanvasRenderer()
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(width: 400, height: 240)
        renderer.setViewport(viewSize: Size(width: 200, height: 120), displayScale: 2)
        renderer.load([StrokeBuilder.curve(at: .zero)])
        Self.drain(renderer, layer)
        #expect(!Self.hasMask(renderer))
        renderer.setEraserReady(true)
        Self.drain(renderer, layer)
        #expect(Self.hasMask(renderer))
        renderer.setEraserReady(false)
        Self.drain(renderer, layer)
        #expect(!Self.hasMask(renderer))
    }

    private static func hasMask(_ renderer: CanvasRenderer) -> Bool {
        renderer.engine.withRenderer { $0.layer?.mask != nil }
    }

    private static func drain(_ renderer: CanvasRenderer, _ layer: CAMetalLayer) {
        renderer.renderFrame(into: layer, deadline: nil)
        for _ in 0..<maxFrames where renderer.renderFrame(into: layer, deadline: nil) {}
    }
}
