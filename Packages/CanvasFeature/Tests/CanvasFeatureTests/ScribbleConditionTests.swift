import Geometry
import Model
import UIKit
import XCTest

@testable import CanvasFeature
@testable import Rendering

/// M5 acceptance 1: Scribble writes into a text box (TOOL-05, D-90).
///
/// No public API writes with a pencil, so the test makes sure that the conditions of Scribble
/// hold, and inserts text through `UITextInput`, as Scribble does with its result. The pass of
/// the acceptance is the manual test with the pencil (D-90).
@MainActor
final class ScribbleConditionTests: XCTestCase {
    func testScribbleConditionsAndInsertedText() async throws {
        let host = try OnScreenCanvas.host()
        let library = RecordingLibrary()
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: CanvasContent(canvasID: Fixtures.canvas)
        )
        dependencies.repository = library
        let canvas = CanvasViewController(dependencies: dependencies)
        OnScreenCanvas.show(canvas, in: host)
        defer { OnScreenCanvas.close(canvas) }
        canvas.select(.text)
        canvas.startNewTextBox(at: .zero)
        let view = canvas.textEditing.view
        assertScribbleConditions(canvas: canvas, view: view)
        view.insertText("linked list")
        canvas.endTextEdit()
        let box = try XCTUnwrap(canvas.content.textBoxes.values.first)
        XCTAssertEqual(box.text, "linked list")
        for _ in 0..<100 where await library.rows.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        let rows = await library.rows
        XCTAssertTrue(
            rows.contains { if case .textBox(let row) = $0 { row.id == box.id } else { false } }
        )
        for _ in 0..<100 where canvas.renderer.needsMoreFrames {
            try await Task.sleep(for: .milliseconds(10))
        }
        let shown = canvas.renderer.engine.withRenderer { $0.texts.entries[box.id] != nil }
        XCTAssertTrue(shown, "The canvas shows the text after the edit")
    }

    /// The conditions of Scribble with the text tool (D-90).
    private func assertScribbleConditions(canvas: CanvasViewController, view: TextEditView) {
        XCTAssertTrue(view.isEditable, "Scribble writes only into an editable view")
        XCTAssertTrue(view.isFirstResponder, "The edit view takes the input")
        XCTAssertNotNil(view.textLayoutManager, "The edit view uses TextKit 2")
        XCTAssertFalse(
            canvas.canvasView.liveCanvas.drawingGestureRecognizer.isEnabled,
            "PencilKit does not take the pencil with the text tool (D-34)"
        )
        XCTAssertFalse(
            canvas.pencilObserver.receivesTouch(in: view),
            "The pencil observer leaves the touches of the edit view"
        )
        XCTAssertFalse(canvas.canvasView.isSurface(view), "The text recognizers leave the view")
        let refusing = view.interactions.compactMap { $0 as? UIScribbleInteraction }
            .filter { $0.delegate != nil }
        XCTAssertTrue(refusing.isEmpty, "No delegate can refuse Scribble")
    }

    /// A finger tap on a box with the pen tool lands on the live canvas of PencilKit. The live
    /// canvas must not take the first responder from the edit view, or the keyboard closes
    /// (manual test 4 of docs/m5-plan.md section 5.6).
    func testLiveCanvasLeavesTheEditViewFirstResponder() throws {
        let host = try OnScreenCanvas.host()
        let box = try TextEditTests.box("node", at: Point(x: 0, y: 0))
        var content = CanvasContent(canvasID: Fixtures.canvas)
        try content.add(box)
        let canvas = CanvasViewController(
            dependencies: CanvasDependencies(
                renderer: try CanvasRenderer(),
                clock: Fixtures.clock(),
                content: content
            )
        )
        OnScreenCanvas.show(canvas, in: host)
        defer { OnScreenCanvas.close(canvas) }
        canvas.startTextEdit(of: box)
        XCTAssertTrue(canvas.textEditing.view.isFirstResponder)
        _ = canvas.canvasView.liveCanvas.becomeFirstResponder()
        XCTAssertTrue(canvas.textEditing.view.isFirstResponder, "The edit view keeps the keyboard")
    }

    /// The selection of PencilKit takes finger taps on the live canvas and ends the focus of the
    /// edit view after the wait for a second tap (manual test 4 of docs/m5-plan.md section 5.6).
    /// Each recognizer in the live canvas that takes finger touches waits for the finger tap and
    /// the long press of the canvas to fail. The drawing recognizer of the pencil does not.
    func testLiveCanvasFingerRecognizersWaitForTheCanvas() throws {
        let host = try OnScreenCanvas.host()
        let canvas = CanvasViewController(
            dependencies: CanvasDependencies(
                renderer: try CanvasRenderer(),
                clock: Fixtures.clock(),
                content: CanvasContent(canvasID: Fixtures.canvas)
            )
        )
        OnScreenCanvas.show(canvas, in: host)
        defer { OnScreenCanvas.close(canvas) }
        let live = canvas.canvasView.liveCanvas
        var fingerRecognizers: [UIGestureRecognizer] = []
        var stack: [UIView] = [live]
        for _ in 0..<500 {
            guard let view = stack.popLast() else { break }
            let takesFinger = (view.gestureRecognizers ?? []).filter { recognizer in
                recognizer.isEnabled && CanvasViewController.takesFingerTouches(recognizer)
            }
            fingerRecognizers += takesFinger
            stack += view.subviews
        }
        XCTAssertFalse(fingerRecognizers.isEmpty, "PencilKit has recognizers for the finger")
        for own in [canvas.textEditing.fingerTap, canvas.textEditing.longPress] {
            for other in fingerRecognizers {
                XCTAssertTrue(
                    canvas.gestureRecognizer(own, shouldBeRequiredToFailBy: other),
                    "\(type(of: other)) waits for the canvas"
                )
            }
            let drawing = live.drawingGestureRecognizer
            XCTAssertFalse(
                canvas.gestureRecognizer(own, shouldBeRequiredToFailBy: drawing),
                "The pencil drawing waits for nothing"
            )
        }
    }
}
