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
}
