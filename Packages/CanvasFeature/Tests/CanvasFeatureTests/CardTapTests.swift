import Foundation
import Geometry
import Model
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

/// The finger tap on a card and on a text box over it (CARD-03, TOOL-06, D-100, D-115).
@MainActor
@Suite("Tap on a card")
struct CardTapTests {
    /// The cards that a tap opened.
    final class Opened {
        var cards: [CardID] = []
    }

    private static let frame = Rect(
        origin: Point(x: -50, y: -40),
        size: Size(width: 100, height: 80)
    )

    private func makeController(
        boxes: [TextBox] = [],
        opened: Opened = Opened()
    ) throws -> CanvasViewController {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        try content.add(NewCardTests.card(1, frame: Self.frame))
        for box in boxes {
            try content.add(box)
        }
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: content
        )
        dependencies.camera = Camera(center: .zero, zoom: 1)
        dependencies.onOpenCard = { opened.cards.append($0.id) }
        let controller = CanvasViewController(dependencies: dependencies)
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        controller.view.layoutIfNeeded()
        return controller
    }

    @Test("A single tap on a card opens it (D-115)")
    func onCard() throws {
        let opened = Opened()
        let controller = try makeController(opened: opened)
        controller.tap(at: .zero)
        #expect(opened.cards.count == 1)
    }

    @Test("A tap on a text box over a card starts its edit and opens nothing")
    func onTextOverCard() throws {
        let box = try TextEditTests.box("node", at: Point(x: -20, y: -10))
        let opened = Opened()
        let controller = try makeController(boxes: [box], opened: opened)
        controller.tap(at: Point(x: -10, y: -5))
        #expect(opened.cards.isEmpty)
        #expect(controller.textEditing.edit?.id == box.id)
        // The card beside the box still opens after the edit ends.
        controller.tap(at: Point(x: 30, y: 30))
        #expect(opened.cards.isEmpty)
        controller.tap(at: Point(x: 30, y: 30))
        #expect(opened.cards.count == 1)
    }

    @Test("A tap on empty canvas opens nothing")
    func onEmpty() throws {
        let opened = Opened()
        let controller = try makeController(opened: opened)
        controller.tap(at: Point(x: 150, y: 0))
        #expect(opened.cards.isEmpty)
    }

    @Test("A tap on a card during an edit ends the edit and opens nothing")
    func endsEdit() throws {
        let opened = Opened()
        let controller = try makeController(opened: opened)
        controller.startNewTextBox(at: Point(x: 150, y: 100))
        controller.tap(at: .zero)
        #expect(!controller.textEditing.isEditing)
        #expect(opened.cards.isEmpty)
    }
}
