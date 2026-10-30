import Foundation
import Geometry
import Model
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

/// The clear of the shown canvas: one step behind a question, with the pending card and a
/// running edit (TOOL-10, D-200).
@MainActor
@Suite("Clear canvas of the screen")
struct ClearCanvasFlowTests {
    /// A view of 400 x 300 points at the standard camera.
    private func makeController(content: CanvasContent) throws -> CanvasViewController {
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: content
        )
        dependencies.sessions = CanvasSessions()
        let controller = CanvasViewController(dependencies: dependencies)
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        controller.view.layoutIfNeeded()
        return controller
    }

    /// Content with one stroke, one text box, and one card.
    private func fullContent() throws -> CanvasContent {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        try content.add(CanvasHistoryTests.line())
        let time = HybridTimestamp(wallMillis: 1, counter: 0, device: Fixtures.device)
        try content.add(
            TextBox(
                id: TextBoxID(rawValue: UUID()),
                meta: RecordMeta(created: time),
                canvasID: Fixtures.canvas,
                origin: Point(x: 10, y: 10),
                text: "note",
                sortKey: FractionalIndex(rawValue: "V")
            )
        )
        try content.add(
            Card(
                id: CardID(rawValue: UUID()),
                meta: RecordMeta(created: time),
                canvasID: Fixtures.canvas,
                frame: Rect(origin: Point(x: 50, y: 50), size: Size(width: 320, height: 224)),
                title: "Tree",
                sortKey: FractionalIndex(rawValue: "V")
            )
        )
        return content
    }

    private func counts(_ controller: CanvasViewController) -> [Int] {
        let content = controller.content
        return [content.strokes.count, content.textBoxes.count, content.cards.count]
    }

    @Test("A clear removes the ink, the text boxes, and the cards as one step that undo reverts")
    func clearUndoRedo() throws {
        let controller = try makeController(content: try fullContent())
        #expect(controller.historyControls.canClear)
        #expect(!controller.historyControls.canUndo)
        controller.clearCanvas()
        #expect(counts(controller) == [0, 0, 0])
        #expect(!controller.historyControls.canClear)
        #expect(controller.historyControls.canUndo)
        #expect(controller.history.undoSteps.count == 1)
        controller.undo()
        #expect(counts(controller) == [1, 1, 1])
        #expect(controller.historyControls.canClear)
        #expect(controller.historyControls.canRedo)
        controller.redo()
        #expect(counts(controller) == [0, 0, 0])
    }

    @Test("The clear button asks first, with a cancel and a destructive clear")
    func question() throws {
        let controller = try makeController(content: try fullContent())
        let alert = controller.clearAlert()
        #expect(alert.title == CanvasStrings.clearTitle)
        #expect(alert.message == CanvasStrings.clearMessage)
        #expect(alert.actions.map(\.style) == [.cancel, .destructive])
        #expect(alert.actions.map(\.title) == [CanvasStrings.cancel, CanvasStrings.clear])
        #expect(counts(controller) == [1, 1, 1], "The question changes nothing")
    }

    @Test("An empty canvas and a canvas without editing take no clear (D-169)")
    func nothingToClear() throws {
        let empty = try makeController(content: CanvasContent(canvasID: Fixtures.canvas))
        #expect(!empty.historyControls.canClear)
        empty.askToClearCanvas()
        #expect(empty.presentedViewController == nil)
        empty.clearCanvas()
        #expect(!empty.historyControls.canUndo)
        let busy = try makeController(content: try fullContent())
        busy.isEditingEnabled = false
        busy.askToClearCanvas()
        #expect(busy.presentedViewController == nil)
        busy.clearCanvas()
        #expect(counts(busy) == [1, 1, 1])
        #expect(!busy.historyControls.canUndo)
    }

    @Test("A clear ends a running edit and takes its text too (D-87)")
    func runningEdit() throws {
        let controller = try makeController(content: CanvasContent(canvasID: Fixtures.canvas))
        controller.select(.text)
        controller.handlePencilTap(at: Point(x: 0, y: 0))
        #expect(controller.textEditing.isEditing)
        controller.textEditing.view.setText("abc")
        controller.clearCanvas()
        #expect(!controller.textEditing.isEditing)
        #expect(controller.content.textBoxes.isEmpty)
        // The end of the edit and the clear are two steps.
        #expect(controller.history.undoSteps.count == 2)
        controller.undo()
        #expect(controller.content.textBoxes.values.map(\.text) == ["abc"])
    }

    @Test("A clear drops the pending card of the card button without a step (D-117)")
    func pendingCard() throws {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        try content.add(CanvasHistoryTests.line())
        let controller = try makeController(content: content)
        controller.showPendingCard()
        #expect(controller.cardInteraction.pendingCard != nil)
        controller.clearCanvas()
        #expect(controller.cardInteraction.pendingCard == nil)
        #expect(counts(controller) == [0, 0, 0])
        controller.undo()
        #expect(counts(controller) == [1, 0, 0])
        #expect(controller.cardInteraction.pendingCard == nil)
        #expect(!controller.historyControls.canUndo)
    }

    @Test("The clear button follows the content of the canvas")
    func canClear() throws {
        let controller = try makeController(content: CanvasContent(canvasID: Fixtures.canvas))
        #expect(!controller.historyControls.canClear)
        controller.addPenStrokes([CanvasHistoryTests.line()])
        #expect(controller.historyControls.canClear)
        controller.undo()
        #expect(!controller.historyControls.canClear)
        controller.redo()
        #expect(controller.historyControls.canClear)
    }
}
