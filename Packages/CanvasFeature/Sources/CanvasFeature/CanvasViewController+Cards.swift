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

    /// Notes a long press that began beside the text boxes: on a card, the start of a move or
    /// of its menu (CARD-07, CARD-08). On empty canvas it does nothing (D-117). A running edit
    /// ends first.
    func beginCardPress(at point: Point) {
        endTextEdit()
        textEditing.menuBox = nil
        textEditing.menuCard = nil
        guard let card = card(at: point) else { return }
        textEditing.cardMove = TextEditing.CardMove(card: card, start: point, current: card)
    }

    /// Moves the card with the finger. The renderer shows it at the new place.
    func continueCardMove(to point: Point) {
        guard var move = textEditing.cardMove else { return }
        let target = Point(
            x: move.card.frame.minX + point.x - move.start.x,
            y: move.card.frame.minY + point.y - move.start.y
        )
        guard let moved = try? move.card.moving(to: target, at: move.card.meta.modified) else {
            logger.error("A moved card has a frame that is not finite")
            return
        }
        move.current = moved
        textEditing.cardMove = move
        renderer.changeCards(removing: [], adding: [moved])
    }

    /// Ends a long press beside the text boxes: a move of a card records one step, and a card
    /// that did not move opens its menu.
    func endCardPress(at location: CGPoint) {
        guard let move = textEditing.cardMove else { return }
        textEditing.cardMove = nil
        guard move.current.frame.origin != move.card.frame.origin else {
            textEditing.menuCard = move.card
            presentMenu(at: location)
            return
        }
        applyCardStep(MoveNode(from: move.card, to: move.current), shows: move.card.id)
    }

    /// Puts a moved card back at its place before the move.
    func cancelCardMove() {
        guard let move = textEditing.cardMove else { return }
        textEditing.cardMove = nil
        renderer.changeCards(removing: [], adding: [move.card])
    }

    private func presentMenu(at location: CGPoint) {
        textEditing.menu?.presentEditMenu(
            with: UIEditMenuConfiguration(identifier: nil, sourcePoint: location)
        )
    }

    /// The menu of a long press on a card without a drag: "Rename" and "Delete" (CARD-08).
    func cardMenu(for card: Card) -> UIMenu {
        let rename = UIAction(title: CanvasStrings.rename) { [weak self] _ in
            self?.showRenameAlert(for: card.id)
        }
        let deleteHandler: UIActionHandler = { [weak self] _ in self?.deleteCard(card.id) }
        let delete = UIAction(
            title: CanvasStrings.delete,
            attributes: .destructive,
            handler: deleteHandler
        )
        return UIMenu(children: [rename, delete])
    }

    /// Makes the rename alert of a card: a text field with the title, as the workspace rename
    /// does (D-101).
    func renameAlert(for id: CardID) -> UIAlertController {
        let alert = UIAlertController(
            title: CanvasStrings.rename,
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { [title = content.cards[id]?.title] field in
            field.text = title
            field.placeholder = CanvasStrings.titlePlaceholder
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: CanvasStrings.cancel, style: .cancel))
        let handler: (UIAlertAction) -> Void = { [weak self, weak alert] _ in
            self?.renameCard(id, to: alert?.textFields?.first?.text)
        }
        alert.addAction(
            UIAlertAction(title: CanvasStrings.rename, style: .default, handler: handler)
        )
        return alert
    }

    private func showRenameAlert(for id: CardID) {
        textEditing.menuCard = nil
        present(renameAlert(for: id), animated: true)
    }

    /// Gives a card a new title with one step. A title of 0 code points stores no title, a
    /// title that did not change records no step, and a title above `Limits.maxTitleLength`
    /// code points shows a message (CARD-08, D-57).
    func renameCard(_ id: CardID, to title: String?) {
        guard let card = content.cards[id] else { return }
        let renamed: Card
        do {
            renamed = try card.retitling(title, at: clock.now())
        } catch {
            onMessage(CanvasStrings.titleLimit)
            return
        }
        guard renamed.title != card.title else { return }
        applyCardStep(RenameCard(old: card, new: renamed), shows: id)
    }

    /// Deletes a card with one step. Its child content stays (D-18).
    func deleteCard(_ id: CardID) {
        textEditing.menuCard = nil
        guard let card = content.cards[id] else { return }
        applyCardStep(DeleteNode(card: card), shows: id)
    }

    /// Performs a card step, sends its rows, and shows the card as the content holds it.
    private func applyCardStep(_ command: any CanvasCommand, shows id: CardID) {
        do {
            send(try perform(command))
        } catch {
            logger.error("A card step did not apply: \(String(describing: error))")
        }
        if let shown = content.cards[id] {
            renderer.changeCards(removing: [], adding: [shown])
        } else {
            renderer.changeCards(removing: [id], adding: [])
        }
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
        return second.id < first.id
    }

    /// Returns the card that a tap at a canvas point opens: a card that no text box covers
    /// there (D-100, D-115), or `nil`.
    func openableCard(at point: Point) -> Card? {
        guard point.isFinite, textBox(at: point) == nil else { return nil }
        return card(at: point)
    }

    /// Opens the card at a canvas point that no text box covers (CARD-03, D-115).
    func openCard(at point: Point) {
        guard let card = openableCard(at: point) else { return }
        onOpenCard(card)
    }
}
