import Model
import UIKit

/// The clear of the canvas: one step that removes all ink, text boxes, and cards of the shown
/// canvas (TOOL-10, D-200). A card goes with its subtree, as a delete of the card does (D-18).
extension CanvasViewController {
    /// Asks before the clear, then clears (D-200). It does nothing on an empty canvas or while
    /// the canvas takes no edits, for example during a restore (D-169).
    func askToClearCanvas() {
        guard isEditingEnabled, hasContent else { return }
        present(clearAlert(), animated: true)
    }

    /// `true` if the canvas holds a stroke, a text box, or a card.
    var hasContent: Bool { !content.strokes.isEmpty || content.nodeCount > 0 }

    /// Makes the question before a clear: "Cancel" and the destructive "Clear".
    func clearAlert() -> UIAlertController {
        let alert = UIAlertController(
            title: CanvasStrings.clearTitle,
            message: CanvasStrings.clearMessage,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: CanvasStrings.cancel, style: .cancel))
        let handler: (UIAlertAction) -> Void = { [weak self] _ in self?.clearCanvas() }
        alert.addAction(
            UIAlertAction(title: CanvasStrings.clear, style: .destructive, handler: handler)
        )
        return alert
    }

    /// Clears the canvas with one undo step (TOOL-10). A running edit ends first, so its text
    /// goes too (D-87). The pending card of the card button goes without a step, because it is
    /// not content (D-117). The renderer and the library get the change. Without editing, or on
    /// an empty canvas, it does nothing.
    public func clearCanvas() {
        guard isEditingEnabled else { return }
        endTextEdit()
        dropPendingCard()
        guard hasContent else { return }
        let command = ClearCanvas(clearing: content)
        do {
            send(try perform(command))
        } catch {
            logger.error("A clear did not apply: \(String(describing: error))")
            return
        }
        renderer.change(
            removing: command.strokes.map(\.id),
            adding: [],
            area: nil,
            onCompleted: stepDrawnCallback(),
            onPresented: {}
        )
        renderer.changeTextBoxes(removing: command.textBoxes.map(\.id), adding: [])
        renderer.changeCards(removing: command.cards.map(\.id), adding: [])
        assert(!hasContent, "The clear leaves no item")
    }

    /// Removes the pending card of the card button from the screen. It is not content, so no
    /// step records it (D-117).
    private func dropPendingCard() {
        guard let card = cardInteraction.pendingCard else { return }
        cardInteraction.pendingDrag = nil
        cardInteraction.pendingCard = nil
        renderer.changeCards(removing: [card.id], adding: [])
    }
}
