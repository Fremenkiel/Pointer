import Foundation
import Geometry
import Model
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

/// The ring at the pencil tip during an erase gesture (TOOL-11, D-202).
@MainActor
@Suite("Eraser indicator")
struct EraserIndicatorTests {
    private static let tip = CGPoint(x: 120, y: 80)

    /// A shown canvas of 400 x 300 points with the eraser selected.
    private func makeController() throws -> CanvasViewController {
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: CanvasContent(canvasID: Fixtures.canvas)
        )
        dependencies.camera = Camera(center: .zero, zoom: 1)
        let controller = CanvasViewController(dependencies: dependencies)
        controller.isShownCanvas = true
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        controller.view.layoutIfNeeded()
        controller.select(.eraser)
        return controller
    }

    @Test("The ring follows the eraser samples, also with Show Hover Preview off")
    func followsSamples() throws {
        let controller = try makeController()
        let hover = controller.canvasView.hoverDot
        controller.hoverBegan(at: Self.tip, isPreviewOn: false)
        #expect(hover.shownCenter == nil)
        controller.pencilBegan()
        controller.pencilMoved(to: Point(x: 50, y: 60))
        #expect(hover.shownCenter == CGPoint(x: 50, y: 60))
        #expect(hover.showsRing)
        #expect(hover.shownRingRadius == CGFloat(EraserSize.standard.viewPoints))
        controller.pencilMoved(to: Point(x: 70.5, y: 61.25))
        #expect(hover.shownCenter == CGPoint(x: 70.5, y: 61.25))
        controller.pencilEnded(at: 0, isCancelled: true)
    }

    @Test("A hover sample during an erase keeps the ring at the last eraser sample")
    func hoverDuringErase() throws {
        let controller = try makeController()
        let hover = controller.canvasView.hoverDot
        controller.hoverBegan(at: Self.tip, isPreviewOn: true)
        controller.pencilBegan()
        controller.pencilMoved(to: Point(x: 50, y: 60))
        controller.hoverMoved(to: CGPoint(x: 10, y: 10))
        #expect(hover.shownCenter == CGPoint(x: 50, y: 60))
        controller.pencilEnded(at: 0, isCancelled: true)
    }

    @Test("The ring hides at the lift, and the next hover sample shows the hover dot again")
    func hidesAtLift() throws {
        let controller = try makeController()
        let hover = controller.canvasView.hoverDot
        controller.hoverBegan(at: Self.tip, isPreviewOn: true)
        controller.pencilBegan()
        controller.pencilMoved(to: Point(x: 50, y: 60))
        controller.pencilEnded(at: 0, isCancelled: false)
        #expect(hover.shownCenter == nil)
        controller.hoverMoved(to: Self.tip)
        #expect(hover.shownCenter == Self.tip)
        #expect(hover.showsRing)
    }

    @Test("A size picked during an erase keeps the ring of the gesture (D-70)")
    func sizeDuringErase() throws {
        let controller = try makeController()
        let hover = controller.canvasView.hoverDot
        controller.pencilBegan()
        controller.pencilMoved(to: Point(x: 50, y: 60))
        controller.select(eraserSize: .large)
        controller.pencilMoved(to: Point(x: 51, y: 60))
        #expect(hover.shownRingRadius == CGFloat(EraserSize.standard.viewPoints))
        controller.pencilEnded(at: 0, isCancelled: true)
        controller.pencilBegan()
        controller.pencilMoved(to: Point(x: 50, y: 60))
        #expect(hover.shownRingRadius == CGFloat(EraserSize.large.viewPoints))
        controller.pencilEnded(at: 0, isCancelled: true)
    }

    @Test("The pen and the text tool show no ring during a touch", arguments: [Tool.pen, .text])
    func noRingForOtherTools(tool: Tool) throws {
        let controller = try makeController()
        controller.select(tool)
        controller.pencilBegan()
        controller.pencilMoved(to: Point(x: 50, y: 60))
        #expect(controller.canvasView.hoverDot.shownCenter == nil)
        controller.pencilEnded(at: 0, isCancelled: true)
    }
}
