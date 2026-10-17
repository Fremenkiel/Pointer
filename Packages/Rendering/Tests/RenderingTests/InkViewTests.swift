import Geometry
import Testing

@testable import Rendering

@MainActor
@Suite("Ink view frame loop")
struct InkViewTests {
    @Test("A display frame without a request or an animation needs no step")
    func idle() throws {
        let view = InkView(renderer: try CanvasRenderer())
        #expect(!view.needsStep(isAnimating: false))
    }

    @Test("A request or an animation needs a step")
    func work() throws {
        let view = InkView(renderer: try CanvasRenderer())
        #expect(view.needsStep(isAnimating: true))
        view.requestFrame()
        #expect(view.needsStep(isAnimating: false))
    }

    @Test("A renderer with a viewport but no texture yet needs a frame")
    func firstFrame() throws {
        let renderer = try CanvasRenderer()
        #expect(!renderer.needsMoreFrames)
        renderer.setViewport(viewSize: Geometry.Size(width: 100, height: 100), displayScale: 2)
        #expect(renderer.needsMoreFrames)
    }
}
