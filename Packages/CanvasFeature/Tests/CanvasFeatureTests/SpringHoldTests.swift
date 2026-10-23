import Geometry
import Model
import QuartzCore
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

/// A pencil that touches during a pinch past a zoom limit holds the camera: the spring back
/// starts after the stroke, so that the stroke keeps the shape and the width that the user saw
/// (D-135, CARD-06, D-36).
@MainActor
@Suite("Spring back after a pencil stroke")
struct SpringHoldTests {
    /// The frame time of the display at 120 Hz.
    private static let frameTime = 1.0 / 120
    /// The most frames that a spring takes in the test.
    private static let maxFrames = 240
    private static let center = Point(x: 200, y: 150)

    /// A shown root canvas of 400 x 300 points at zoom 1, in a pinch past the minimum zoom.
    private func makePinchedCanvas() throws -> CanvasViewController {
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
        controller.cameraController.beginPinch(centroid: Self.center)
        controller.cameraController.updatePinch(scale: 0.05, centroid: Self.center)
        #expect(controller.camera.zoom < Limits.minZoom)
        return controller
    }

    /// Steps the frame callback until the camera stops, and returns the frames.
    private func runFrames(of controller: CanvasViewController) -> Int {
        var time = CACurrentMediaTime()
        var frames = 0
        _ = controller.canvasView.inkView.onFrame?(time)
        while frames < Self.maxFrames, controller.cameraController.isAnimating {
            time += Self.frameTime
            frames += 1
            _ = controller.canvasView.inkView.onFrame?(time)
        }
        return frames
    }

    @Test("A pen stroke during the pinch holds the camera until its handoff")
    func penStroke() throws {
        let controller = try makePinchedCanvas()
        let pinched = controller.camera
        controller.pencilBegan()
        controller.endPinchGesture()
        #expect(!controller.cameraController.isAnimating, "The camera moves under the pencil")
        #expect(controller.camera == pinched)
        controller.pencilEnded(at: 1, isCancelled: false)
        #expect(!controller.cameraController.isAnimating, "The spring starts before the handoff")
        controller.canvasViewDrawingDidChange(controller.canvasView.liveCanvas)
        #expect(controller.cameraController.isAnimating)
        #expect(runFrames(of: controller) > 0)
        #expect(controller.camera.zoom == Limits.minZoom)
    }

    @Test(
        "A touch without a pen stroke releases the spring at the lift",
        arguments: [Tool.eraser, .text]
    )
    func otherTool(tool: Tool) throws {
        let controller = try makePinchedCanvas()
        controller.select(tool)
        controller.pencilBegan()
        controller.endPinchGesture()
        #expect(!controller.cameraController.isAnimating, "The camera moves under the pencil")
        controller.pencilEnded(at: 1, isCancelled: false)
        #expect(controller.cameraController.isAnimating)
        #expect(runFrames(of: controller) > 0)
        #expect(controller.camera.zoom == Limits.minZoom)
    }

    @Test("A cancelled pen touch releases the spring at its end")
    func cancelledTouch() throws {
        let controller = try makePinchedCanvas()
        controller.pencilBegan()
        controller.endPinchGesture()
        #expect(!controller.cameraController.isAnimating, "The camera moves under the pencil")
        controller.pencilEnded(at: 1, isCancelled: true)
        #expect(controller.cameraController.isAnimating)
    }

    @Test("Without the pencil, the pinch springs back at once")
    func withoutPencil() throws {
        let controller = try makePinchedCanvas()
        controller.endPinchGesture()
        #expect(controller.cameraController.isAnimating)
        #expect(!controller.cameraController.isSpringHeld)
    }

    @Test("A held spring goes at a new pinch, and a hold without a spring does nothing")
    func controllerRules() {
        var camera = CameraController(
            camera: Camera(center: .zero, zoom: 1),
            viewSize: Size(width: 400, height: 300)
        )
        camera.holdSpring()
        #expect(!camera.isSpringHeld)
        camera.beginPinch(centroid: Self.center)
        camera.updatePinch(scale: 0.05, centroid: Self.center)
        _ = camera.endPinch()
        camera.holdSpring()
        #expect(camera.isSpringHeld)
        #expect(!camera.isAnimating)
        camera.beginPinch(centroid: Self.center)
        #expect(!camera.isSpringHeld)
        camera.releaseSpring()
        #expect(!camera.isAnimating)
    }
}
