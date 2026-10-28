import Geometry
import QuartzCore
import Testing
import UIKit

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

    @Test("A layout with the same size posts no viewport and draws no frame (3.3.6)")
    func sameLayoutDrawsNothing() throws {
        let renderer = try CanvasRenderer()
        let view = InkView(renderer: renderer)
        view.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        view.layoutSubviews()
        #expect(renderer.needsMoreFrames, "The first layout posts the viewport")
        let layer = try #require(view.layer as? CAMetalLayer)
        for _ in 0..<20 where renderer.renderFrame(into: layer, deadline: nil) {}
        #expect(!renderer.needsMoreFrames)
        view.layoutSubviews()
        #expect(!renderer.needsMoreFrames, "The same layout posts nothing")
        view.frame = CGRect(x: 0, y: 0, width: 220, height: 100)
        view.layoutSubviews()
        #expect(renderer.needsMoreFrames, "A new size posts the viewport")
    }

    @Test("A renderer with a viewport but no texture yet needs a frame")
    func firstFrame() throws {
        let renderer = try CanvasRenderer()
        #expect(!renderer.needsMoreFrames)
        renderer.setViewport(viewSize: Geometry.Size(width: 100, height: 100), displayScale: 2)
        #expect(renderer.needsMoreFrames)
    }
}
