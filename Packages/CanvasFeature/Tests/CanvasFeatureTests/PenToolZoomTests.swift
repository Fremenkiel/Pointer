import Geometry
import Model
import PencilKit
import QuartzCore
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

/// The pen width of the live canvas follows the zoom at a pencil down and at rest, not at each
/// frame of a zoom (the M7 plan task 3.1, FEEL-03, D-37, D-131).
@MainActor
@Suite("Pen tool at a zoom")
struct PenToolZoomTests {
    /// The frame time of the display at 120 Hz.
    private static let frameTime = 1.0 / 120
    /// The most frames that a spring takes in the test.
    private static let maxFrames = 240

    /// A shown root canvas of 400 x 300 points at zoom 1 in a spring back from a pinch past the
    /// minimum zoom, and the time of its first step.
    private func makeSpring() throws -> (CanvasViewController, TimeInterval) {
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
        let center = Point(x: 200, y: 150)
        controller.cameraController.beginPinch(centroid: center)
        controller.cameraController.updatePinch(scale: 0.05, centroid: center)
        _ = controller.cameraController.endPinch()
        let time = CACurrentMediaTime()
        _ = controller.canvasView.inkView.onFrame?(time)
        return (controller, time)
    }

    /// The width of the pen tool of the live canvas.
    private func toolWidth(of controller: CanvasViewController) throws -> CGFloat {
        try #require(controller.canvasView.liveCanvas.tool as? PKInkingTool).width
    }

    /// The width of the pen tool at the shown zoom.
    private func expectedWidth(of controller: CanvasViewController) -> CGFloat {
        PenTool.inkingTool(zoom: controller.camera.zoom).width
    }

    @Test("A new canvas has the pen width of its camera")
    func newCanvas() throws {
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: CanvasContent(canvasID: Fixtures.canvas)
        )
        dependencies.camera = Camera(center: .zero, zoom: 3)
        let controller = CanvasViewController(dependencies: dependencies)
        #expect(try toolWidth(of: controller) == PenTool.inkingTool(zoom: 3).width)
    }

    @Test("A pencil down during a spring gives the pen the width of the zoom at the pencil down")
    func pencilDownDuringSpring() throws {
        let (controller, start) = try makeSpring()
        let startWidth = try toolWidth(of: controller)
        var time = start
        for _ in 0..<10 {
            time += Self.frameTime
            _ = controller.canvasView.inkView.onFrame?(time)
        }
        #expect(controller.cameraController.isAnimating)
        #expect(try toolWidth(of: controller) == startWidth, "No new tool at a zoom frame")
        controller.pencilBegan()
        #expect(!controller.cameraController.isAnimating)
        #expect(try toolWidth(of: controller) == expectedWidth(of: controller))
        #expect(try toolWidth(of: controller) != startWidth)
        controller.pencilEnded(at: time, isCancelled: true)
    }

    @Test("The hit test of a new touch gives the pen the width of a pinch that still runs")
    func hitTestDuringPinch() throws {
        let (controller, _) = try makeSpring()
        controller.cameraController.stopAnimation()
        let center = Point(x: 200, y: 150)
        controller.cameraController.beginPinch(centroid: center)
        controller.cameraController.updatePinch(scale: 0.5, centroid: center)
        let before = try toolWidth(of: controller)
        _ = controller.canvasView.hitTest(CGPoint(x: 100, y: 100), with: HoverEvent())
        #expect(try toolWidth(of: controller) == before, "A hover sets no tool")
        _ = controller.canvasView.hitTest(CGPoint(x: 100, y: 100), with: TouchEvent())
        #expect(try toolWidth(of: controller) == expectedWidth(of: controller))
    }

    @Test("At the end of a spring, the pen gets the width of the zoom at rest")
    func springAtRest() throws {
        let (controller, start) = try makeSpring()
        var time = start
        var frames = 0
        while frames < Self.maxFrames, controller.cameraController.isAnimating {
            time += Self.frameTime
            frames += 1
            _ = controller.canvasView.inkView.onFrame?(time)
        }
        #expect(!controller.cameraController.isAnimating)
        #expect(controller.camera.zoom == Limits.minZoom)
        #expect(try toolWidth(of: controller) == expectedWidth(of: controller))
    }
}

/// An event of the type of a touch, as UIKit hit-tests it at a new touch. A plain `UIEvent` has
/// no type.
private final class TouchEvent: UIEvent {
    override var type: UIEvent.EventType { .touches }
}

/// An event of the type of a hover.
private final class HoverEvent: UIEvent {
    override var type: UIEvent.EventType { .hover }
}
