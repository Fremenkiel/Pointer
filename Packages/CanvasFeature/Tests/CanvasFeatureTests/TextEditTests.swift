import Foundation
import Geometry
import Model
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

@MainActor
@Suite("Text boxes of the canvas")
struct TextEditTests {
    /// The messages that the canvas showed.
    final class Messages {
        var shown: [String] = []
    }

    /// A view of 400 x 300 points, so view (200, 150) is the canvas point of the camera center.
    private func makeController(
        boxes: [TextBox] = [],
        zoom: Double = 1,
        library: RecordingLibrary = RecordingLibrary(),
        messages: Messages = Messages()
    ) throws -> CanvasViewController {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        for box in boxes {
            try content.add(box)
        }
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: content
        )
        dependencies.camera = Camera(center: .zero, zoom: zoom)
        dependencies.repository = library
        dependencies.onMessage = { messages.shown.append($0) }
        let controller = CanvasViewController(dependencies: dependencies)
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        controller.view.layoutIfNeeded()
        return controller
    }

    static func box(
        _ text: String,
        at origin: Point = Point(x: 10, y: 20),
        id: UInt8 = 1
    ) throws -> TextBox {
        try TextBox(
            id: TextBoxID(rawValue: UUID(uuid: (6, id, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))),
            meta: RecordMeta(
                created: HybridTimestamp(wallMillis: 1, counter: 0, device: Fixtures.device)
            ),
            canvasID: Fixtures.canvas,
            origin: origin,
            text: text,
            sortKey: FractionalIndex(rawValue: "V")
        )
    }

    @Test("A new box with text records one add, and undo and redo take it away and back")
    func newBox() async throws {
        let library = RecordingLibrary()
        let controller = try makeController(library: library)
        controller.select(.text)
        controller.startNewTextBox(at: Point(x: 5, y: 5))
        #expect(controller.textEditing.isEditing)
        controller.textEditing.view.text = "queue"
        controller.endTextEdit()
        let box = try #require(controller.content.textBoxes.values.first)
        #expect(box.text == "queue")
        #expect(controller.history.undoSteps.count == 1)
        controller.undo()
        #expect(controller.content.textBoxes.isEmpty)
        controller.redo()
        #expect(controller.content.textBoxes[box.id]?.text == "queue")
        for _ in 0..<100 where await library.rows.count < 3 {
            try await Task.sleep(for: .milliseconds(10))
        }
        let rows = await library.rows.compactMap { row -> TextBox? in
            if case .textBox(let box) = row { box } else { nil }
        }
        #expect(rows.map(\.meta.isDeleted) == [false, true, false])
    }

    @Test("A new box that ends empty and a box without a change record no step (D-86)")
    func noStep() throws {
        let box = try Self.box("same")
        let controller = try makeController(boxes: [box])
        controller.startNewTextBox(at: .zero)
        controller.endTextEdit()
        controller.startTextEdit(of: box)
        controller.endTextEdit()
        #expect(controller.history.undoSteps.isEmpty)
        #expect(controller.content.textBoxes.count == 1)
    }

    @Test("A changed box records one edit, and an emptied box records one delete (D-86)")
    func editAndDelete() throws {
        let box = try Self.box("old")
        let controller = try makeController(boxes: [box])
        controller.startTextEdit(of: box)
        controller.textEditing.view.text = "new"
        controller.endTextEdit()
        #expect(controller.content.textBoxes[box.id]?.text == "new")
        #expect(controller.history.undoSteps.last is EditText)
        let edited = try #require(controller.content.textBoxes[box.id])
        controller.startTextEdit(of: edited)
        controller.textEditing.view.text = ""
        controller.endTextEdit()
        #expect(controller.content.textBoxes[box.id] == nil)
        #expect(controller.history.undoSteps.last is DeleteNode)
        controller.undo()
        #expect(controller.content.textBoxes[box.id]?.text == "new")
        controller.undo()
        #expect(controller.content.textBoxes[box.id]?.text == "old")
    }

    @Test("At the node limit, a tap makes no box and shows the limit message")
    func nodeLimit() throws {
        let messages = Messages()
        var identifiers = IdentifierFactory(
            wallClock: FixedWallClock(),
            random: SeededRandom(state: 3)
        )
        let boxes = try (0..<Limits.maxNodesPerCanvas).map { _ in
            try TextBox(
                id: identifiers.make(),
                meta: RecordMeta(
                    created: HybridTimestamp(wallMillis: 1, counter: 0, device: Fixtures.device)
                ),
                canvasID: Fixtures.canvas,
                origin: Point(x: 5_000, y: 5_000),
                text: "x",
                sortKey: FractionalIndex(rawValue: "V")
            )
        }
        let controller = try makeController(boxes: boxes, messages: messages)
        controller.startNewTextBox(at: .zero)
        #expect(!controller.textEditing.isEditing)
        #expect(messages.shown == [CanvasStrings.nodeLimit])
    }

    @Test("The edit view refuses text past the limit with a message, and refuses U+0000")
    func textLimit() throws {
        let messages = Messages()
        let controller = try makeController(messages: messages)
        controller.startNewTextBox(at: .zero)
        let view = controller.textEditing.view
        view.text = String(repeating: "a", count: Limits.maxTextLength - 1)
        let end = NSRange(location: Limits.maxTextLength - 1, length: 0)
        #expect(controller.textView(view, shouldChangeTextIn: end, replacementText: "b"))
        #expect(!controller.textView(view, shouldChangeTextIn: end, replacementText: "bc"))
        #expect(!controller.textView(view, shouldChangeTextIn: end, replacementText: "\u{0}"))
        #expect(messages.shown == [CanvasStrings.textLimit])
    }

    @Test("A tool change ends an edit at once (D-87)")
    func toolChangeEndsEdit() throws {
        let controller = try makeController()
        controller.select(.text)
        controller.startNewTextBox(at: .zero)
        controller.textEditing.view.text = "a"
        controller.select(.pen)
        #expect(!controller.textEditing.isEditing)
        #expect(controller.content.textBoxes.count == 1)
    }

    @Test("During an edit, undo acts on the text view and leaves the canvas history (D-86)")
    func undoDuringEdit() throws {
        let box = try Self.box("kept")
        let controller = try makeController(boxes: [box])
        controller.startTextEdit(of: box)
        controller.textEditing.view.text = "kept"
        controller.endTextEdit()
        controller.startNewTextBox(at: Point(x: 100, y: 100))
        #expect(!controller.historyControls.canUndo)
        controller.undo()
        #expect(controller.textEditing.isEditing)
        #expect(controller.content.textBoxes[box.id] != nil)
    }

    @Test("The edit view lies on the layout of the box at the zoom", arguments: [0.5, 1.0, 4.0])
    func editViewFrame(zoom: Double) throws {
        let box = try Self.box("let x = 1\nnext")
        let controller = try makeController(boxes: [box], zoom: zoom)
        controller.startTextEdit(of: box)
        let frame = controller.textEditing.view.frame
        let layout = TextLayout(text: box.text)
        #expect(abs(frame.minX - (200 + box.origin.x * zoom)) < 0.001)
        #expect(abs(frame.minY - (150 + box.origin.y * zoom)) < 0.001)
        #expect(abs(frame.height - layout.size.height * zoom) < 0.001)
        #expect(abs(frame.width - TextStyle.maxWidth * zoom) < 0.001)
        let font = try #require(controller.textEditing.view.font)
        #expect(abs(font.pointSize - TextStyle.fontSize * zoom) < 0.001)
    }

    @Test("The edit view keeps plain text: no rich text, no links, no data detectors")
    func plainText() throws {
        let controller = try makeController()
        let view = controller.textEditing.view
        #expect(!view.allowsEditingTextAttributes)
        #expect(view.dataDetectorTypes.isEmpty)
        controller.startNewTextBox(at: .zero)
        view.attributedText = NSAttributedString(
            string: "link",
            attributes: [.link: URL(fileURLWithPath: "/")]
        )
        controller.endTextEdit()
        #expect(controller.content.textBoxes.values.first?.text == "link")
    }

    @Test("A tap finds the box under it, and a small box has the tap target as its area")
    func hitTest() throws {
        let box = try Self.box("i", at: Point(x: 0, y: 0))
        let controller = try makeController(boxes: [box])
        #expect(controller.textBox(at: Point(x: 2, y: 5))?.id == box.id)
        #expect(controller.textBox(at: Point(x: -15, y: 10))?.id == box.id)
        #expect(controller.textBox(at: Point(x: 100, y: 100)) == nil)
    }

    @Test("A drag moves a box with one step, and an undo puts it back (CARD-07)")
    func move() throws {
        let box = try Self.box("node", at: Point(x: 0, y: 0))
        let controller = try makeController(boxes: [box])
        controller.beginTextMove(at: Point(x: 5, y: 5))
        controller.continueTextMove(to: Point(x: 55, y: 25))
        controller.endTextMove(at: .zero)
        #expect(controller.content.textBoxes[box.id]?.origin == Point(x: 50, y: 20))
        #expect(controller.history.undoSteps.last is MoveNode)
        controller.undo()
        #expect(controller.content.textBoxes[box.id]?.origin == Point(x: 0, y: 0))
    }

    @Test("A long press without a drag opens the menu, and its delete has one step (TOOL-08)")
    func menuDelete() throws {
        let box = try Self.box("node", at: Point(x: 0, y: 0))
        let controller = try makeController(boxes: [box])
        controller.beginTextMove(at: Point(x: 5, y: 5))
        controller.endTextMove(at: .zero)
        #expect(controller.textEditing.menuBox?.id == box.id)
        #expect(controller.history.undoSteps.isEmpty)
        controller.deleteTextBox(box.id)
        #expect(controller.content.textBoxes[box.id] == nil)
        controller.undo()
        #expect(controller.content.textBoxes[box.id] != nil)
    }
}
