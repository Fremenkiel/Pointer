import Foundation
import Geometry
import Model
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

/// The card menu, the rename, the delete, and the move of a card (CARD-07, CARD-08, D-10, D-16).
@MainActor
@Suite("Card menu and move")
struct CardMenuTests {
    private static let frame = Rect(
        origin: Point(x: -50, y: -40),
        size: Size(width: 100, height: 80)
    )

    private func makeController(
        card: Card,
        boxes: [TextBox] = [],
        messages: TextEditTests.Messages = TextEditTests.Messages()
    ) throws -> CanvasViewController {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        try content.add(card)
        for box in boxes {
            try content.add(box)
        }
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: content
        )
        dependencies.camera = Camera(center: .zero, zoom: 1)
        dependencies.repository = RecordingLibrary()
        dependencies.onMessage = { messages.shown.append($0) }
        let controller = CanvasViewController(dependencies: dependencies)
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        controller.view.layoutIfNeeded()
        return controller
    }

    private static func card(title: String? = "Tree") throws -> Card {
        try NewCardTests.card(1, frame: frame).retitling(title, at: Fixtures.clock().now())
    }

    @Test("A long press on a card without a drag opens Rename and Delete")
    func menu() throws {
        let card = try Self.card()
        let controller = try makeController(card: card)
        controller.beginLongPress(at: .zero)
        controller.endCardPress(at: .zero)
        #expect(controller.textEditing.menuCard?.id == card.id)
        let menu = controller.cardMenu(for: card)
        #expect(menu.children.map(\.title) == [CanvasStrings.rename, CanvasStrings.delete])
        let delete = try #require(menu.children.last as? UIAction)
        #expect(delete.attributes.contains(.destructive))
    }

    @Test("The rename alert shows the title in a text field with Cancel and Rename")
    func alert() throws {
        let card = try Self.card()
        let controller = try makeController(card: card)
        let alert = controller.renameAlert(for: card.id)
        #expect(alert.title == CanvasStrings.rename)
        #expect(alert.textFields?.first?.text == "Tree")
        #expect(alert.textFields?.first?.placeholder == CanvasStrings.titlePlaceholder)
        #expect(alert.actions.map(\.title) == [CanvasStrings.cancel, CanvasStrings.rename])
    }

    @Test(
        "A rename takes 0, 1, and 120 code points and refuses 121 with a message",
        arguments: [0, 1, Limits.maxTitleLength, Limits.maxTitleLength + 1]
    )
    func rename(length: Int) throws {
        let card = try Self.card()
        let messages = TextEditTests.Messages()
        let controller = try makeController(card: card, messages: messages)
        let title = String(repeating: "a", count: length)
        controller.renameCard(card.id, to: title)
        if length > Limits.maxTitleLength {
            #expect(messages.shown == [CanvasStrings.titleLimit])
            #expect(controller.history.undoSteps.isEmpty)
            #expect(controller.content.cards[card.id]?.title == "Tree")
            return
        }
        #expect(controller.content.cards[card.id]?.title == (length == 0 ? nil : title))
        #expect(controller.history.undoSteps.last is RenameCard)
        controller.undo()
        #expect(controller.content.cards[card.id]?.title == "Tree")
        controller.redo()
        #expect(controller.content.cards[card.id]?.title == (length == 0 ? nil : title))
    }

    @Test("A rename to the same title records no step")
    func sameTitle() throws {
        let card = try Self.card()
        let controller = try makeController(card: card)
        controller.renameCard(card.id, to: "Tree")
        #expect(controller.history.undoSteps.isEmpty)
    }

    @Test("A delete records one step, and undo brings the card back")
    func delete() throws {
        let card = try Self.card()
        let controller = try makeController(card: card)
        controller.deleteCard(card.id)
        #expect(controller.content.cards.isEmpty)
        #expect(controller.history.undoSteps.last is DeleteNode)
        controller.undo()
        #expect(controller.content.cards[card.id]?.title == "Tree")
        controller.redo()
        #expect(controller.content.cards.isEmpty)
    }

    @Test("A long press on a card, then a drag, moves it with one step")
    func move() throws {
        let card = try Self.card()
        let controller = try makeController(card: card)
        controller.beginLongPress(at: .zero)
        controller.continueCardMove(to: Point(x: 30, y: 10))
        controller.continueCardMove(to: Point(x: 60, y: 20))
        controller.endCardPress(at: .zero)
        #expect(controller.content.cards[card.id]?.frame.origin == Point(x: 10, y: -20))
        #expect(controller.history.undoSteps.count == 1)
        #expect(controller.history.undoSteps.last is MoveNode)
        #expect(controller.textEditing.menuCard == nil)
        controller.undo()
        #expect(controller.content.cards[card.id]?.frame == Self.frame)
        controller.redo()
        #expect(controller.content.cards[card.id]?.frame.origin == Point(x: 10, y: -20))
    }

    @Test("A text box above a card wins the long press (D-16)")
    func textWins() throws {
        let card = try Self.card()
        let box = try TextEditTests.box("node", at: Point(x: -20, y: -10))
        let controller = try makeController(card: card, boxes: [box])
        controller.beginLongPress(at: Point(x: -10, y: -5))
        #expect(controller.textEditing.move?.box.id == box.id)
        #expect(controller.textEditing.cardMove == nil)
    }
}
