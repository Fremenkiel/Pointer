import Geometry
import Model
import UIKit

/// A new card from the card button of the chrome (CARD-01, D-117). The button shows a pending
/// card half outside the left edge of the screen. A finger drags it into place, and at the lift
/// it joins the canvas with one undo step.
extension CanvasViewController {
    /// Shows the pending card with the size of D-118, centered on the left edge of the view. A
    /// second tap puts it back there. At level 32 and at the node limit, it shows a message and
    /// shows no card (CARD-09, D-95). A running edit ends first.
    func showPendingCard() {
        endTextEdit()
        guard mayAddCard() else { return }
        let size = viewSize
        guard size.width > 0, size.height > 0 else { return }
        let edge = renderer.camera.canvasPoint(
            fromView: Point(x: 0, y: size.height / 2),
            viewSize: size
        )
        let card: Card
        do {
            card = try Card(
                id: textEditing.pendingCard?.id ?? clock.makeIdentifier(CardID.self),
                meta: RecordMeta(created: clock.now()),
                canvasID: content.canvasID,
                frame: Card.defaultFrame(at: edge),
                title: nil,
                sortKey: nextCardSortKey()
            )
        } catch {
            logger.error("A pending card is not valid: \(String(describing: error))")
            return
        }
        textEditing.pendingDrag = nil
        textEditing.pendingCard = card
        renderer.changeCards(removing: [], adding: [card])
        assert(content.cards[card.id] == nil, "The pending card is not content yet")
    }

    /// Starts the drag of the pending card if the finger lies on it. Returns `false` beside it,
    /// so the finger pans the canvas.
    func beginPendingDrag(at point: Point) -> Bool {
        guard point.isFinite, let card = textEditing.pendingCard else { return false }
        guard card.frame.contains(point) else { return false }
        textEditing.pendingDrag = TextEditing.CardMove(card: card, start: point, current: card)
        return true
    }

    /// Moves the pending card with the finger. The renderer shows it at the new place.
    func continuePendingDrag(to point: Point) {
        guard var drag = textEditing.pendingDrag, point.isFinite else { return }
        let target = Point(
            x: drag.card.frame.minX + point.x - drag.start.x,
            y: drag.card.frame.minY + point.y - drag.start.y
        )
        guard let moved = try? drag.card.moving(to: target, at: drag.card.meta.modified) else {
            logger.error("A dragged card has a frame that is not finite")
            return
        }
        drag.current = moved
        textEditing.pendingDrag = drag
        textEditing.pendingCard = moved
        renderer.changeCards(removing: [], adding: [moved])
    }

    /// Ends the drag of the pending card. A lift places it with one undo step. A cancelled drag,
    /// or a drag without a move, puts it back at its place before the drag.
    func endPendingDrag(isPlaced: Bool) {
        guard let drag = textEditing.pendingDrag else { return }
        textEditing.pendingDrag = nil
        let hasMoved = drag.current.frame.origin != drag.card.frame.origin
        guard isPlaced, hasMoved else {
            textEditing.pendingCard = drag.card
            renderer.changeCards(removing: [], adding: [drag.card])
            return
        }
        textEditing.pendingCard = nil
        addCard(id: drag.card.id, frame: drag.current.frame)
        if content.cards[drag.card.id] == nil {
            renderer.changeCards(removing: [drag.card.id], adding: [])
        }
    }

    /// Places the pending card where it shows, with one undo step, before the canvas leaves the
    /// screen or the app moves to the background, so nothing that the screen shows is lost
    /// (D-123). A running drag ends at the place of the finger.
    public func placePendingCard() {
        guard let card = textEditing.pendingCard else { return }
        textEditing.pendingDrag = nil
        textEditing.pendingCard = nil
        addCard(id: card.id, frame: card.frame)
        if content.cards[card.id] == nil {
            renderer.changeCards(removing: [card.id], adding: [])
        }
        assert(textEditing.pendingCard == nil, "No card stays pending")
    }

    /// Takes a one-finger pan that starts on the pending card. Returns `true` while the pan
    /// drags the card, so the camera stays.
    func dragsPendingCard(_ recognizer: UIPanGestureRecognizer) -> Bool {
        let location = recognizer.location(in: canvasView)
        let point = renderer.camera.canvasPoint(
            fromView: Point(x: location.x, y: location.y),
            viewSize: viewSize
        )
        switch recognizer.state {
        case .began:
            // The pan begins after the movement threshold, so the drag starts where the finger
            // touched down.
            let moved = recognizer.translation(in: canvasView)
            let start = renderer.camera.canvasPoint(
                fromView: Point(x: location.x - moved.x, y: location.y - moved.y),
                viewSize: viewSize
            )
            guard beginPendingDrag(at: start) else { return false }
            continuePendingDrag(to: point)
            return true
        case .changed:
            guard textEditing.pendingDrag != nil else { return false }
            continuePendingDrag(to: point)
            return true
        default:
            guard textEditing.pendingDrag != nil else { return false }
            endPendingDrag(isPlaced: recognizer.state == .ended)
            return true
        }
    }

    /// Adds a new card with a frame with one undo step (CARD-01). At level 32 and at the node
    /// limit, it shows a message and adds nothing (CARD-09, D-95).
    func addCard(id: CardID? = nil, frame: Rect) {
        guard mayAddCard() else { return }
        do {
            let card = try Card(
                id: id ?? clock.makeIdentifier(CardID.self),
                meta: RecordMeta(created: clock.now()),
                canvasID: content.canvasID,
                frame: frame,
                title: nil,
                sortKey: nextCardSortKey()
            )
            send(try perform(AddCard(card: card)))
            renderer.changeCards(removing: [], adding: [card])
            assert(content.cards[card.id] != nil, "The new card is live")
        } catch CommandError.nodeLimitReached {
            onMessage(CanvasStrings.nodeLimit)
        } catch {
            logger.error("A new card did not apply: \(String(describing: error))")
        }
    }

    /// `true` below level 32 and below the node limit. Otherwise it shows the message of the
    /// limit (CARD-09, D-95).
    private func mayAddCard() -> Bool {
        guard level < Limits.maxDepth else {
            onMessage(CanvasStrings.depthLimit)
            return false
        }
        guard content.nodeCount < Limits.maxNodesPerCanvas else {
            onMessage(CanvasStrings.nodeLimit)
            return false
        }
        return true
    }

    /// The sort key after the last card: a new card lies above the others.
    private func nextCardSortKey() -> FractionalIndex {
        let last = content.cards.values.map(\.sortKey).max()
        do {
            return try FractionalIndex.between(last, nil)
        } catch {
            // The ID breaks the tie of two equal keys (data-model.md section 6).
            logger.error("No sort key after the last card: \(String(describing: error))")
            return last ?? Self.firstCardSortKey
        }
    }

    /// The key of the first card of a canvas: the midpoint of the empty list.
    private static var firstCardSortKey: FractionalIndex {
        do {
            return try FractionalIndex.between(nil, nil)
        } catch {
            preconditionFailure("The empty list has a midpoint: \(error)")
        }
    }
}
