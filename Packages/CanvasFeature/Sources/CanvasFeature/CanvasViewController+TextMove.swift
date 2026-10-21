import Geometry
import Model
import UIKit

/// The move of a text box with a finger and its long-press menu (CARD-07, TOOL-08, D-10, D-89).
extension CanvasViewController: @MainActor UIEditMenuInteractionDelegate {
    /// Installs the menu of a long press without a drag.
    func installTextMenu() {
        let interaction = UIEditMenuInteraction(delegate: self)
        canvasView.addInteraction(interaction)
        textEditing.menu = interaction
    }

    /// A long press on a box, then a drag, moves it. A long press without a drag opens the menu.
    @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        let point = canvasPoint(of: recognizer)
        switch recognizer.state {
        case .began:
            beginLongPress(at: point)
        case .changed:
            continueTextMove(to: point)
            continueCardMove(to: point)
        case .ended where textEditing.move != nil:
            endTextMove(at: recognizer.location(in: canvasView))
        case .ended:
            endCardPress(at: recognizer.location(in: canvasView))
        case .cancelled, .failed:
            cancelTextMove()
            cancelCardMove()
        default:
            return
        }
    }

    /// Starts a long press at a canvas point. Text lies on top, so a box above a card wins the
    /// press (D-16).
    func beginLongPress(at point: Point) {
        if textBox(at: point) != nil {
            beginTextMove(at: point)
        } else {
            beginCardPress(at: point)
        }
    }

    /// `true` if a long press can start: on a box for a move or its menu, and on empty canvas
    /// for "New card" (CARD-01, D-08). The pan wins a finger that moves before the press.
    func longPressCanBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        isEditingEnabled
    }

    /// Starts the move of the box under a canvas point.
    func beginTextMove(at point: Point) {
        guard let box = textBox(at: point) else { return }
        // A running edit ends first, so that its step comes before the move.
        endTextEdit()
        guard let live = content.textBoxes[box.id] else { return }
        textEditing.move = TextEditing.Move(box: live, start: point, current: live)
    }

    /// Moves the box with the finger. The renderer shows it at the new place.
    func continueTextMove(to point: Point) {
        guard var move = textEditing.move else { return }
        let target = Point(
            x: move.box.origin.x + point.x - move.start.x,
            y: move.box.origin.y + point.y - move.start.y
        )
        guard let moved = try? move.box.moving(to: target, at: move.box.meta.modified) else {
            logger.error("A moved text box has an origin that is not finite")
            return
        }
        move.current = moved
        textEditing.move = move
        renderer.changeTextBoxes(removing: [], adding: [moved])
    }

    /// Ends a move with one step, or opens the menu if the finger did not move (TOOL-08).
    func endTextMove(at location: CGPoint) {
        guard let move = textEditing.move else { return }
        textEditing.move = nil
        guard move.current.origin != move.box.origin else {
            showTextMenu(for: move.box, at: location)
            return
        }
        do {
            send(try perform(MoveNode(from: move.box, to: move.current)))
        } catch {
            logger.error("A move of a text box did not apply: \(String(describing: error))")
        }
        if let shown = content.textBoxes[move.box.id] {
            renderer.changeTextBoxes(removing: [], adding: [shown])
        }
        assert(textEditing.move == nil, "The move ended")
    }

    /// Puts the box back at its place before the move.
    func cancelTextMove() {
        guard let move = textEditing.move else { return }
        textEditing.move = nil
        renderer.changeTextBoxes(removing: [], adding: [move.box])
    }

    private func showTextMenu(for box: TextBox, at location: CGPoint) {
        textEditing.menuBox = box
        textEditing.menuPoint = nil
        textEditing.menuCard = nil
        textEditing.menu?.presentEditMenu(
            with: UIEditMenuConfiguration(identifier: nil, sourcePoint: location)
        )
    }

    /// Deletes a box with one undo step (TOOL-08, D-89).
    func deleteTextBox(_ id: TextBoxID) {
        guard let box = content.textBoxes[id] else { return }
        do {
            send(try perform(DeleteNode(textBox: box)))
        } catch {
            logger.error("A delete of a text box did not apply: \(String(describing: error))")
            return
        }
        renderer.changeTextBoxes(removing: [id], adding: [])
        assert(content.textBoxes[id] == nil, "The deleted box left the content")
    }

    /// The menu of a long press without a drag holds "Delete" on a box (TOOL-08) and "New card"
    /// on empty canvas (CARD-01).
    public func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        if let point = textEditing.menuPoint { return newCardMenu(at: point) }
        if let card = textEditing.menuCard { return cardMenu(for: card) }
        guard let box = textEditing.menuBox else { return nil }
        let handler: UIActionHandler = { [weak self] _ in self?.deleteTextBox(box.id) }
        let delete = UIAction(
            title: CanvasStrings.delete,
            attributes: .destructive,
            handler: handler
        )
        return UIMenu(children: [delete])
    }
}
