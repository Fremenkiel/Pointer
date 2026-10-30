import Geometry
import Model
import PencilKit
import Rendering
import Testing
import UIKit

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
        #expect(tool.width == PenTool.inkingTool(width: .standard, zoom: zoom).width)
    }

    @Test("A closed canvas releases its view and its renderer")
    func closedCanvasIsReleased() async throws {
        weak var view: UIView?
        weak var renderer: CanvasRenderer?
        do {
            let made = try CanvasRenderer()
            let controller = CanvasViewController(
                dependencies: CanvasDependencies(
                    renderer: made,
                    clock: Fixtures.clock(),
                    content: CanvasContent(canvasID: Fixtures.canvas)
                )
            )
            controller.loadViewIfNeeded()
            view = controller.view
            renderer = made
            controller.willMove(toParent: nil)
        }
        // The render thread and the main queue drop their last references soon after.
        for _ in 0..<100 where view != nil || renderer != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(view == nil)
        #expect(renderer == nil)
    }
}
