import Geometry
import Metal
import Model
import QuartzCore
import Testing

@testable import Rendering

/// The redraw of an area lists only the strokes that touch the texture (P-01 of
/// docs/m4-fix-plan.md, phase 3, task 1).
@MainActor
@Suite("The redraw area")
struct RedrawAreaTests {
    /// The frames that the test may draw until the first build is done.
    private static let maxFrames = 400

    @Test("A redraw of the whole canvas at zoom 2 finds only the strokes of the texture")
    func wholeCanvasAtZoomTwo() throws {
        let strokes = PerformanceContent.handwriting(count: 200_000)
        let renderer = try CanvasRenderer()
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(width: 800, height: 600)
        renderer.setViewport(viewSize: Size(width: 400, height: 300), displayScale: 2)
        renderer.camera = Camera(center: .zero, zoom: 2)
        renderer.load(strokes)
        for _ in 0..<Self.maxFrames where renderer.renderFrame(into: layer, deadline: nil) {}
        renderer.change(
            removing: [],
            adding: [],
            area: Rect(minX: -7_200, minY: -4_200, maxX: 7_200, maxY: 4_200),
            onPresented: {}
        )
        renderer.renderFrame(into: layer, deadline: nil)
        let (found, rect) = renderer.engine.withRenderer { frameRenderer in
            let front = frameRenderer.layer?.front
            let margin = CommittedLayer.redrawMarginPixels / (front?.pixelsPerCanvasPoint ?? 1)
            return (
                frameRenderer.layer?.redrawSlots.count ?? 0,
                front?.canvasRect.expanded(by: margin)
            )
        }
        let texture = try #require(rect)
        let touching = strokes.filter { $0.bounds.intersects(texture) }.count
        #expect(touching > 0)
        #expect(found == touching, "The redraw found \(found) strokes, \(touching) touch")
    }
}
