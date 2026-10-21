import Geometry
import Model
import UIKit
/// The cards of the canvas screen (architecture.md 5.5 and 6).
extension CanvasViewController {
    /// Gives the loaded strokes and cards to the renderer. The renderer lays out the card titles
    /// off the render thread, so the first frame does not wait for them (D-92).
    func loadRenderer() {
        renderer.load(Array(content.strokes.values))
        renderer.load(Array(content.cards.values))
    }

    /// Notes a long press that began on empty canvas: no card and no text box under the finger.
    /// Ink does not count (D-113). A running edit ends first.
    func beginCardPress(at point: Point) {
        endTextEdit()
        textEditing.menuBox = nil
        textEditing.menuPoint = card(at: point) == nil ? point : nil
    }

    /// Opens the menu of "New card" at the end of a long press on empty canvas.
    func endCardPress(at location: CGPoint) {
        guard textEditing.menuPoint != nil else { return }
        textEditing.menu?.presentEditMenu(
            with: UIEditMenuConfiguration(identifier: nil, sourcePoint: location)
        )
    }

    /// The menu of a long press on empty canvas: "New card" (CARD-01).
    func newCardMenu(at point: Point) -> UIMenu {
        let handler: UIActionHandler = { [weak self] _ in self?.addCard(at: point) }
        return UIMenu(children: [UIAction(title: CanvasStrings.newCard, handler: handler)])
    }

    /// Returns the card under a canvas point, the one with the largest sort key on top, or `nil`.
    func card(at point: Point) -> Card? {
        precondition(point.isFinite, "A hit test needs a finite point")
        var best: Card?
        for card in content.cards.values where card.frame.contains(point) {
            if best.map({ Self.isAbove($0, card) }) ?? false { continue }
            best = card
        }
        return best
    }

    /// `true` if `first` lies above `second`: a larger sort key, and the ID breaks a tie
    /// (data-model.md section 6).
    private static func isAbove(_ first: Card, _ second: Card) -> Bool {
        guard first.sortKey == second.sortKey else { return second.sortKey < first.sortKey }
        return first.id.rawValue.uuidString > second.id.rawValue.uuidString
    }

    /// Adds a new card at a canvas point with one undo step (CARD-01, D-101). At level 32 and at
    /// the node limit, it shows a message and adds nothing (CARD-09, D-95).
    func addCard(at point: Point) {
        textEditing.menuPoint = nil
        guard level < Limits.maxDepth else {
            onMessage(CanvasStrings.depthLimit)
            return
        }
        guard content.nodeCount < Limits.maxNodesPerCanvas else {
            onMessage(CanvasStrings.nodeLimit)
            return
        }
        do {
            let card = try Card(
                id: clock.makeIdentifier(CardID.self),
                meta: RecordMeta(created: clock.now()),
                canvasID: content.canvasID,
                frame: Card.defaultFrame(at: point, camera: renderer.camera, viewSize: viewSize),
                title: nil,
                sortKey: nextCardSortKey()
            )
            send(try perform(AddCard(card: card)))
            renderer.changeCards(removing: [], adding: [card])
        } catch CommandError.nodeLimitReached {
            onMessage(CanvasStrings.nodeLimit)
        } catch {
            logger.error("A new card did not apply: \(String(describing: error))")
        }
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
