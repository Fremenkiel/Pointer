import Geometry
import Model
import QuartzCore
import UIKit
import XCTest

@testable import CanvasFeature
@testable import Rendering

/// The cost of the frame callback of the canvas screen during a zoom (the M7 plan task 3.1,
/// D-131). A spring after a pinch past the minimum zoom changes the zoom at each frame. A glide
/// after a pan runs the same callback at one zoom. Before D-131, the pen tool of the live canvas
/// made 139 allocations in each zoom frame.
@MainActor
final class ZoomFrameAllocationTests: XCTestCase {
    /// The frame time of the display at 120 Hz.
    private static let frameTime = 1.0 / 120
    /// The most frames of one animation that the test steps.
    private static let maxFrames = 240

    func testFramesOfASpringAndOfAGlide() throws {
        let spring = try measure { controller in
            controller.cameraController.beginPinch(centroid: Point(x: 200, y: 150))
            controller.cameraController.updatePinch(scale: 0.05, centroid: Point(x: 200, y: 150))
            _ = controller.cameraController.endPinch()
        }
        let glide = try measure { controller in
            controller.cameraController.pan(byView: Vector(dx: 10, dy: 0))
            controller.cameraController.endPan(velocity: Vector(dx: 3_000, dy: 0))
        }
        let tool = try measureTool()
        let line = "spring: \(spring.summary); glide: \(glide.summary); tool: \(tool)"
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertGreaterThan(spring.frames, 10, line)
        XCTAssertGreaterThan(glide.frames, 10, line)
        // A zoom frame makes no `PKInkingTool` and allocates nothing in Pointer code (PERF-01).
        // The last frame of the spring brings the camera to rest, and only it makes the pen tool
        // of the new zoom, once.
        XCTAssertEqual(spring.counts.dropLast().max(), 0, line)
        XCTAssertEqual(glide.counts.max(), 0, line)
    }

    /// The counts and the times of the frames of one animation.
    private struct Measure {
        var frames = 0
        var counts: [Int] = []
        var micros: [Double] = []

        var summary: String {
            let counts = counts.sorted()
            let micros = micros.sorted()
            guard let maxCount = counts.last, let maxMicros = micros.last else { return "none" }
            let medianCount = counts[counts.count / 2]
            let medianMicros = micros[micros.count / 2]
            return "\(frames) frames, allocations median \(medianCount) max \(maxCount), "
                + "main thread median \(String(format: "%.1f", medianMicros)) us "
                + "max \(String(format: "%.1f", maxMicros)) us"
        }
    }

    /// Starts an animation with `start`, then steps its frames twice: once to count the
    /// allocations, and once to time them.
    private func measure(
        _ start: (CanvasViewController) -> Void
    ) throws -> Measure {
        var result = Measure()
        for pass in 0..<2 {
            let controller = try Self.makeController()
            let onFrame = try XCTUnwrap(controller.canvasView.inkView.onFrame)
            start(controller)
            XCTAssertTrue(controller.cameraController.isAnimating)
            var time = CACurrentMediaTime()
            _ = onFrame(time)
            var frames = 0
            while frames < Self.maxFrames, controller.cameraController.isAnimating {
                time += Self.frameTime
                frames += 1
                if pass == 0 {
                    let count = try XCTUnwrap(
                        AllocationCounter.countMainThread { _ = onFrame(time) }
                    )
                    result.counts.append(count)
                } else {
                    let clock = ContinuousClock()
                    let elapsed = clock.measure { _ = onFrame(time) }
                    let parts = elapsed.components
                    result.micros.append(
                        Double(parts.seconds) * 1e6 + Double(parts.attoseconds) / 1e12
                    )
                }
            }
            result.frames = frames
        }
        return result
    }

    /// Counts the allocations of the pen tool line of `applyCamera()` alone, at 52 zooms.
    private func measureTool() throws -> String {
        let controller = try Self.makeController()
        let live = controller.canvasView.liveCanvas
        var counts: [Int] = []
        for index in 0..<52 {
            let zoom = 0.25 + Double(index) * 0.001
            let count = try XCTUnwrap(
                AllocationCounter.countMainThread {
                    live.tool = PenTool.inkingTool(zoom: zoom)
                }
            )
            counts.append(count)
        }
        counts.sort()
        return "allocations median \(counts[counts.count / 2]) max \(counts.last ?? 0)"
    }

    /// A shown root canvas of 400 x 300 points at zoom 1.
    private static func makeController() throws -> CanvasViewController {
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
        return controller
    }
}
