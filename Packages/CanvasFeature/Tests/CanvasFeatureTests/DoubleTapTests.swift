import Foundation
import Geometry
import Model
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

/// The finger double tap on a card and the single tap beside it (CARD-03, TOOL-06, D-100).
@MainActor
@Suite("Double tap on a card")
struct DoubleTapTests {
    /// The cards that a double tap opened.
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

    @Test("A double tap on a card opens it, and the single tap there waits for it")
    func onCard() throws {
        let opened = Opened()
        let controller = try makeController(opened: opened)
        #expect(controller.fingerTapWaits(at: .zero))
        controller.openCard(at: .zero)
        #expect(opened.cards.count == 1)
    }

    @Test("A double tap on a text box over a card opens nothing, and its tap does not wait")
    func onTextOverCard() throws {
        let box = try TextEditTests.box("node", at: Point(x: -20, y: -10))
        let opened = Opened()
        let controller = try makeController(boxes: [box], opened: opened)
        let point = Point(x: -10, y: -5)
        #expect(!controller.fingerTapWaits(at: point))
        controller.openCard(at: point)
        #expect(opened.cards.isEmpty)
        // The card beside the box still opens.
        #expect(controller.fingerTapWaits(at: Point(x: 30, y: 30)))
    }

    @Test("A double tap on empty canvas opens nothing, and its tap does not wait")
    func onEmpty() throws {
        let opened = Opened()
        let controller = try makeController(opened: opened)
        #expect(!controller.fingerTapWaits(at: Point(x: 150, y: 0)))
        controller.openCard(at: Point(x: 150, y: 0))
        #expect(opened.cards.isEmpty)
    }

    @Test("A double tap ends a running edit before the open")
    func endsEdit() throws {
        let opened = Opened()
        let controller = try makeController(opened: opened)
        controller.startNewTextBox(at: Point(x: 150, y: 100))
        controller.openCard(at: .zero)
        #expect(!controller.textEditing.isEditing)
        #expect(opened.cards.count == 1)
    }

    @Test("The double tap takes two finger taps on the canvas surface")
    func recognizer() throws {
        let controller = try makeController()
        let doubleTap = controller.textEditing.doubleTap
        #expect(doubleTap.numberOfTapsRequired == 2)
        #expect(doubleTap.allowedTouchTypes == [NSNumber(value: UITouch.TouchType.direct.rawValue)])
        #expect(doubleTap.view === controller.canvasView)
        #expect(doubleTap.delegate === controller)
    }
}
