import Foundation
import Geometry
import Model
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

/// A new card from the card button of the chrome (CARD-01, CARD-09, D-95, D-101, D-117).
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

    /// The canvas point at the left edge of the view, in the middle of its height.
    private static let leftEdge = Point(x: -200, y: 0)

    @Test("The card button shows a card half outside the left edge, which is not content yet")
    func pendingCard() throws {
        let controller = try makeController()
        controller.showPendingCard()
        let card = try #require(controller.cardInteraction.pendingCard)
        let frame = Card.defaultFrame(at: Self.leftEdge)
        #expect(card.frame == frame)
        #expect(card.frame.center == Self.leftEdge)
        #expect(controller.content.cards.isEmpty)
        #expect(controller.history.undoSteps.isEmpty)
        #expect(controller.openableCard(at: Self.leftEdge) == nil, "A tap does not open it")
    }

    @Test("A drag of the pending card places it with one undo step (D-117)")
    func dragPlaces() throws {
        let controller = try makeController()
        controller.showPendingCard()
        let pending = try #require(controller.cardInteraction.pendingCard)
        let start = Point(x: -190, y: 0)
        #expect(controller.beginPendingDrag(at: start))
        controller.continuePendingDrag(to: Point(x: start.x + 120, y: start.y + 20))
        #expect(controller.content.cards.isEmpty, "The card joins the canvas at the lift")
        controller.endPendingDrag(isPlaced: true)
        let card = try #require(controller.content.cards[pending.id])
        #expect(card.frame.origin == Point(x: pending.frame.minX + 120, y: pending.frame.minY + 20))
        #expect(card.frame.size == pending.frame.size)
        #expect(card.title == nil)
        #expect(controller.history.undoSteps.count == 1)
        #expect(controller.history.undoSteps.last is AddCard)
        #expect(controller.cardInteraction.pendingCard == nil)
        controller.undo()
        #expect(controller.content.cards.isEmpty)
        controller.redo()
        #expect(controller.content.cards[pending.id]?.frame == card.frame)
    }

    @Test("A drag beside the pending card pans the canvas, and a cancelled drag puts it back")
    func besideAndCancel() throws {
        let controller = try makeController()
        #expect(!controller.beginPendingDrag(at: Self.leftEdge), "No pending card, no drag")
        controller.showPendingCard()
        let pending = try #require(controller.cardInteraction.pendingCard)
        #expect(!controller.beginPendingDrag(at: Point(x: 150, y: 0)))
        #expect(controller.beginPendingDrag(at: Self.leftEdge))
        controller.continuePendingDrag(to: Point(x: 0, y: 0))
        controller.endPendingDrag(isPlaced: false)
        #expect(controller.cardInteraction.pendingCard?.frame == pending.frame)
        #expect(controller.content.cards.isEmpty)
        #expect(controller.history.undoSteps.isEmpty)
    }

    @Test("A second tap on the card button keeps one pending card at the left edge")
    func secondTap() throws {
        let controller = try makeController()
        controller.showPendingCard()
        controller.showPendingCard()
        let card = try #require(controller.cardInteraction.pendingCard)
        #expect(card.frame.center == Self.leftEdge)
        #expect(controller.content.cards.isEmpty)
        #expect(controller.history.undoSteps.isEmpty)
    }

    @Test("A long press on empty canvas starts no move and no menu (D-117)")
    func emptyPress() throws {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        let frame = Rect(origin: Point(x: -50, y: -50), size: Size(width: 100, height: 100))
        try content.add(Self.card(1, frame: frame))
        let controller = try makeController(content: content)
        controller.beginCardPress(at: Point(x: 120, y: 0))
        #expect(controller.cardInteraction.move == nil)
        #expect(controller.cardInteraction.menuCard == nil)
        controller.beginCardPress(at: Point(x: 0, y: 0))
        #expect(controller.cardInteraction.move?.card.frame == frame)
    }

    @Test(
        "The card button works below level 32 and is refused with a message at level 32 (D-95)",
        arguments: [0, 1, Limits.maxDepth - 1, Limits.maxDepth]
    )
    func depthLimit(level: Int) throws {
        let messages = TextEditTests.Messages()
        let controller = try makeController(level: level, messages: messages)
        controller.showPendingCard()
        if level < Limits.maxDepth {
            #expect(controller.cardInteraction.pendingCard != nil)
            #expect(messages.shown.isEmpty)
        } else {
            #expect(controller.cardInteraction.pendingCard == nil)
            #expect(messages.shown == [CanvasStrings.depthLimit])
            #expect(controller.history.undoSteps.isEmpty)
        }
    }

    @Test("The card button at the node limit is refused with the node limit message")
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
        controller.showPendingCard()
        #expect(controller.cardInteraction.pendingCard == nil)
        #expect(messages.shown == [CanvasStrings.nodeLimit])
    }

    @Test("A long press and the card button end a running text edit first")
    func endsEdit() throws {
        let controller = try makeController()
        controller.startNewTextBox(at: Point(x: 100, y: 100))
        #expect(controller.textEditing.isEditing)
        controller.beginCardPress(at: Point(x: -100, y: -100))
        #expect(!controller.textEditing.isEditing)
        controller.startNewTextBox(at: Point(x: 100, y: 100))
        controller.showPendingCard()
        #expect(!controller.textEditing.isEditing)
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
