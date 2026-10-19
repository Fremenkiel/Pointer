import Geometry
import Model
import PencilKit
import Rendering
import Testing

@testable import CanvasFeature

@MainActor
@Suite("Canvas screen")
struct CanvasViewControllerTests {
    @Test("The live pen starts with the width of the stored zoom", arguments: [0.25, 1.0, 4.0])
    func penWidthOfStoredZoom(zoom: Double) throws {
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: CanvasContent(canvasID: Fixtures.canvas)
        )
        dependencies.camera = Camera(center: Point(x: 30, y: -20), zoom: zoom)
        let controller = CanvasViewController(dependencies: dependencies)
        let canvasView = try #require(controller.view as? CanvasView)
        let tool = try #require(canvasView.liveCanvas.tool as? PKInkingTool)
        #expect(tool.width == PenTool.inkingTool(zoom: zoom).width)
    }
}
