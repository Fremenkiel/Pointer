import Foundation
import Geometry
import Model
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

/// "New card" from a long press on empty canvas (CARD-01, CARD-09, D-95, D-101, D-113).
@MainActor
@Suite("New card")
struct NewCardTests {
    private static let viewSize = Size(width: 400, height: 300)

    /// A view of 400 x 300 points at zoom 1 around the origin.
    private func makeController(
        content: CanvasContent = CanvasContent(canvasID: Fixtures.canvas),
        level: Int = 0,
        messages: TextEditTests.Messages = TextEditTests.Messages()
    ) throws -> CanvasViewController {
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: content
        )
        dependencies.camera = Camera(center: .zero, zoom: 1)
        dependencies.repository = RecordingLibrary()
        dependencies.onMessage = { messages.shown.append($0) }
        dependencies.level = level
        let controller = CanvasViewController(dependencies: dependencies)
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        controller.view.layoutIfNeeded()
        return controller
    }

    static func card(_ id: UInt8, frame: Rect) throws -> Card {
        try Card(
            id: CardID(rawValue: UUID(uuid: (5, id, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))),
            meta: RecordMeta(
                created: HybridTimestamp(wallMillis: 1, counter: 0, device: Fixtures.device)
            ),
            canvasID: Fixtures.canvas,
            frame: frame,
            title: nil,
            sortKey: FractionalIndex(rawValue: "V")
        )
    }

    @Test("A long press on empty canvas offers New card, and New card adds one undo step")
    func newCard() throws {
        let controller = try makeController()
        let point = Point(x: 30, y: -20)
        controller.beginCardPress(at: point)
        #expect(controller.textEditing.menuPoint == point)
        let menu = controller.newCardMenu(at: point)
        #expect(menu.children.map(\.title) == [CanvasStrings.newCard])
        controller.addCard(at: point)
        let card = try #require(controller.content.cards.values.first)
        let frame = Card.defaultFrame(
            at: point,
            camera: Camera(center: .zero, zoom: 1),
            viewSize: Self.viewSize
        )
        #expect(card.frame == frame)
        #expect(card.title == nil)
        #expect(controller.history.undoSteps.last is AddCard)
        #expect(controller.textEditing.menuPoint == nil)
        controller.undo()
        #expect(controller.content.cards.isEmpty)
        controller.redo()
        #expect(controller.content.cards[card.id]?.frame == frame)
    }

    @Test("A long press on a card or on a text box offers no New card (D-113)")
    func notEmpty() throws {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        let frame = Rect(origin: Point(x: -50, y: -50), size: Size(width: 100, height: 100))
        try content.add(Self.card(1, frame: frame))
        let controller = try makeController(content: content)
        controller.beginCardPress(at: Point(x: 0, y: 0))
        #expect(controller.textEditing.menuPoint == nil)
        controller.beginCardPress(at: Point(x: 120, y: 0))
        #expect(controller.textEditing.menuPoint == Point(x: 120, y: 0))
    }

    @Test(
        "New card works below level 32 and is refused with a message at level 32 (D-95)",
        arguments: [0, 1, Limits.maxDepth - 1, Limits.maxDepth]
    )
    func depthLimit(level: Int) throws {
        let messages = TextEditTests.Messages()
        let controller = try makeController(level: level, messages: messages)
        controller.addCard(at: .zero)
        if level < Limits.maxDepth {
            #expect(controller.content.cards.count == 1)
            #expect(messages.shown.isEmpty)
        } else {
            #expect(controller.content.cards.isEmpty)
            #expect(messages.shown == [CanvasStrings.depthLimit])
            #expect(controller.history.undoSteps.isEmpty)
        }
    }

    @Test("New card at the node limit is refused with the node limit message")
    func nodeLimit() throws {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        for index in 0..<Limits.maxNodesPerCanvas {
            let id = UUID(
                uuid: (
                    4, UInt8(index & 255), UInt8(index >> 8), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                )
            )
            let frame = Rect(
                origin: Point(x: Double(index) * 70, y: 500),
                size: Size(width: 64, height: 48)
            )
            try content.add(
                Card(
                    id: CardID(rawValue: id),
                    meta: RecordMeta(
                        created: HybridTimestamp(wallMillis: 1, counter: 0, device: Fixtures.device)
                    ),
                    canvasID: Fixtures.canvas,
                    frame: frame,
                    title: nil,
                    sortKey: FractionalIndex(rawValue: "V")
                )
            )
        }
        let messages = TextEditTests.Messages()
        let controller = try makeController(content: content, messages: messages)
        controller.addCard(at: .zero)
        #expect(controller.content.cards.count == Limits.maxNodesPerCanvas)
        #expect(messages.shown == [CanvasStrings.nodeLimit])
    }

    @Test("A long press during a text edit ends the edit first")
    func endsEdit() throws {
        let controller = try makeController()
        controller.startNewTextBox(at: Point(x: 100, y: 100))
        #expect(controller.textEditing.isEditing)
        controller.beginCardPress(at: Point(x: -100, y: -100))
        #expect(!controller.textEditing.isEditing)
        #expect(controller.textEditing.menuPoint == Point(x: -100, y: -100))
    }

    @Test("The long press waits for a still finger, so a pan on empty canvas still moves it")
    func panStillWorks() throws {
        let controller = try makeController()
        let press = controller.textEditing.longPress
        #expect(press.minimumPressDuration >= 0.5)
        #expect(press.allowableMovement <= 10)
        #expect(press.allowedTouchTypes == [NSNumber(value: UITouch.TouchType.direct.rawValue)])
    }
}
