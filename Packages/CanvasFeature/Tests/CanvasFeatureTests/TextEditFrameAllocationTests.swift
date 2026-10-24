import Geometry
import Model
import QuartzCore
import UIKit
import XCTest

@testable import CanvasFeature
@testable import Rendering

/// A glide frame with an open text edit makes no new text layout (PERF-01). The work of UIKit
/// to move a view does not count, as the Metal work does not count (D-43), so the test counts
/// each allocation by its caller with `AllocationTracer`. Before the fix, a frame laid out the
/// text again and set the frame of the edit view: 73 allocations with 5 characters and 218 with
/// 984. An earlier form compared the largest count with a bare move of a text view, and failed
/// when UIKit made one extra allocation (m8-fix-plan.md section 3).
@MainActor
final class TextEditFrameAllocationTests: XCTestCase {
    /// The frame time of the display at 120 Hz.
    private static let frameTime = 1.0 / 120
    /// The most frames of one glide that the test steps.
    private static let maxFrames = 240

    func testGlideFramesWithAShortText() throws {
        try checkGlide(text: "node")
    }

    func testGlideFramesWithALongText() throws {
        try checkGlide(text: String(repeating: "let value = items.map { $0 * 2 }\n", count: 24))
    }

    func testTracerCountsAnAllocationOfPointerCode() throws {
        let result = try XCTUnwrap(
            AllocationTracer.trace { withExtendedLifetime(Self.makeArray()) {} }
        )
        XCTAssertEqual(result.pointer, 1, "The array of the test is a Pointer allocation")
        XCTAssertEqual(result.unrecorded, 0)
    }

    /// Counts the allocations of the glide frames with an open edit of `text`.
    private func checkGlide(text: String) throws {
        let canvas = try Self.makeCanvas(text: text)
        let box = try XCTUnwrap(canvas.content.textBoxes.values.first)
        canvas.startTextEdit(of: box)
        let onFrame = try XCTUnwrap(canvas.canvasView.inkView.onFrame)
        canvas.cameraController.pan(byView: Vector(dx: 10, dy: 0))
        canvas.cameraController.endPan(velocity: Vector(dx: 3_000, dy: 0))
        var time = CACurrentMediaTime()
        _ = onFrame(time)
        var results: [AllocationTracer.Result] = []
        while results.count < Self.maxFrames, canvas.cameraController.isAnimating {
            time += Self.frameTime
            results.append(try XCTUnwrap(AllocationTracer.trace { _ = onFrame(time) }))
        }
        let corner = canvas.camera.viewPoint(fromCanvas: box.origin, viewSize: canvas.viewSize)
        let frame = canvas.textEditing.view.frame
        XCTAssertEqual(frame.minX, corner.x, accuracy: 1e-6, "The edit view follows the box")
        XCTAssertEqual(frame.minY, corner.y, accuracy: 1e-6, "The edit view follows the box")
        let pointer = results.map(\.pointer).max() ?? 0
        let system = results.map(\.system).max() ?? 0
        let unrecorded = results.map(\.unrecorded).max() ?? 0
        let summary =
            "\(results.count) frames, Pointer allocations max \(pointer), system max \(system)"
        XCTContext.runActivity(named: summary) { _ in }
        XCTAssertGreaterThan(results.count, 10, summary)
        XCTAssertTrue(canvas.textEditing.isEditing, summary)
        // The move of the edit view allocates in UIKit, so 0 here means that the trace failed.
        XCTAssertGreaterThan(system, 0, "The trace saw no allocation: \(summary)")
        XCTAssertEqual(unrecorded, 0, summary)
        XCTAssertEqual(pointer, 0, "Pointer code allocated in a glide frame: \(summary)")
    }

    func testSpringFramesWithALongText() throws {
        try checkSpring(text: String(repeating: "let value = items.map { $0 * 2 }\n", count: 24))
    }

    /// Counts the allocations of the spring frames after a pinch past the zoom limit with an open
    /// edit of `text`. The spring ends the pinch, so the text lays out once, in the last frame
    /// (D-85). Before the fix, each spring frame laid out the text again: up to 231 allocations
    /// and 14.57 ms per frame with 984 characters.
    private func checkSpring(text: String) throws {
        let canvas = try Self.makeCanvas(text: text, zoom: 8)
        let box = try XCTUnwrap(canvas.content.textBoxes.values.first)
        canvas.startTextEdit(of: box)
        let onFrame = try XCTUnwrap(canvas.canvasView.inkView.onFrame)
        let centroid = Point(x: 200, y: 150)
        canvas.cameraController.beginPinch(centroid: centroid)
        canvas.cameraController.updatePinch(scale: 1.5, centroid: centroid)
        _ = canvas.cameraController.endPinch()
        XCTAssertTrue(canvas.cameraController.isSpringing, "The zoom springs back")
        var time = CACurrentMediaTime()
        _ = onFrame(time)
        var results: [AllocationTracer.Result] = []
        while results.count < Self.maxFrames, canvas.cameraController.isAnimating {
            time += Self.frameTime
            results.append(try XCTUnwrap(AllocationTracer.trace { _ = onFrame(time) }))
        }
        let spring = results.dropLast()
        let pointer = spring.map(\.pointer).max() ?? 0
        let summary = "\(results.count) frames, Pointer allocations max \(pointer) before the last"
        XCTContext.runActivity(named: summary) { _ in }
        XCTAssertGreaterThan(results.count, 10, summary)
        XCTAssertEqual(spring.map(\.unrecorded).max() ?? 0, 0, summary)
        XCTAssertEqual(pointer, 0, "Pointer code allocated in a spring frame: \(summary)")
        let view = canvas.textEditing.view
        XCTAssertEqual(view.layoutZoom, 8, "The text lays out at the limit at the end")
        XCTAssertTrue(view.transform.isIdentity, "The edit view has no scale at the end")
    }

    /// Makes an array on the heap in the code of the test.
    @inline(never)
    private static func makeArray() -> [Int] {
        Array(repeating: 7, count: 64)
    }

    /// A shown root canvas of 400 x 300 points at zoom 1, with one box of `text` at the origin.
    private static func makeCanvas(text: String, zoom: Double = 1) throws -> CanvasViewController {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        try content.add(try TextEditTests.box(text, at: .zero))
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: content
        )
        dependencies.camera = Camera(center: .zero, zoom: zoom)
        let canvas = CanvasViewController(dependencies: dependencies)
        canvas.isShownCanvas = true
        canvas.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        canvas.view.layoutIfNeeded()
        return canvas
    }
}
