import Geometry
import Model
import QuartzCore
import UIKit
import XCTest

@testable import CanvasFeature
@testable import Rendering

/// A glide frame with an open text edit makes no new text layout (PERF-01). The work of UIKit
/// to move a view does not count, as the Metal work does not count (D-43), so the test compares
/// the frames with a bare move of a text view. Before the fix, a frame laid out the text again
/// and set the frame of the edit view: 73 allocations with 5 characters and 218 with 984.
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

    /// Counts the glide frames with an open edit of `text`, and a bare move of a text view.
    private func checkGlide(text: String) throws {
        let canvas = try Self.makeCanvas(text: text)
        let box = try XCTUnwrap(canvas.content.textBoxes.values.first)
        canvas.startTextEdit(of: box)
        let onFrame = try XCTUnwrap(canvas.canvasView.inkView.onFrame)
        canvas.cameraController.pan(byView: Vector(dx: 10, dy: 0))
        canvas.cameraController.endPan(velocity: Vector(dx: 3_000, dy: 0))
        var time = CACurrentMediaTime()
        _ = onFrame(time)
        var counts: [Int] = []
        while counts.count < Self.maxFrames, canvas.cameraController.isAnimating {
            time += Self.frameTime
            counts.append(try XCTUnwrap(AllocationCounter.countMainThread { _ = onFrame(time) }))
        }
        let corner = canvas.camera.viewPoint(fromCanvas: box.origin, viewSize: canvas.viewSize)
        let frame = canvas.textEditing.view.frame
        XCTAssertEqual(frame.minX, corner.x, accuracy: 1e-6, "The edit view follows the box")
        XCTAssertEqual(frame.minY, corner.y, accuracy: 1e-6, "The edit view follows the box")
        let bare = UITextView(frame: canvas.textEditing.view.frame)
        canvas.canvasView.addSubview(bare)
        var bareCounts: [Int] = []
        for index in 0..<counts.count {
            let center = CGPoint(x: Double(index), y: 100)
            let count = AllocationCounter.countMainThread { bare.center = center }
            bareCounts.append(try XCTUnwrap(count))
        }
        let edit = counts.max() ?? 0
        let move = bareCounts.max() ?? 0
        let summary = "\(counts.count) frames, edit frame max \(edit), bare move max \(move)"
        XCTContext.runActivity(named: summary) { _ in }
        XCTAssertGreaterThan(counts.count, 10, summary)
        XCTAssertTrue(canvas.textEditing.isEditing, summary)
        XCTAssertLessThanOrEqual(edit, move, "Pointer code allocated in a glide frame: \(summary)")
    }

    /// A shown root canvas of 400 x 300 points at zoom 1, with one box of `text` at the origin.
    private static func makeCanvas(text: String) throws -> CanvasViewController {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        try content.add(try TextEditTests.box(text, at: .zero))
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: content
        )
        dependencies.camera = Camera(center: .zero, zoom: 1)
        let canvas = CanvasViewController(dependencies: dependencies)
        canvas.isShownCanvas = true
        canvas.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        canvas.view.layoutIfNeeded()
        return canvas
    }
}
