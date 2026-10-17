import Geometry
import Testing

@testable import Rendering

@MainActor
@Suite("Ink view frame loop")
struct InkViewTests {
    @Test("A UI update without work draws no frame")
    func idle() throws {
        let view = InkView(renderer: try CanvasRenderer())
        #expect(!view.shouldDrawFrame(isAnimating: false))
    }

    @Test("A request or an animation draws a frame")
    func work() throws {
        let view = InkView(renderer: try CanvasRenderer())
        #expect(view.shouldDrawFrame(isAnimating: true))
        view.requestFrame()
        #expect(view.shouldDrawFrame(isAnimating: false))
    }

    @Test("A renderer with a viewport but no texture yet needs a frame")
    func firstFrame() throws {
        let renderer = try CanvasRenderer()
        #expect(!renderer.needsMoreFrames)
        renderer.setViewport(viewSize: Geometry.Size(width: 100, height: 100), displayScale: 2)
        #expect(renderer.needsMoreFrames)
    }
}
