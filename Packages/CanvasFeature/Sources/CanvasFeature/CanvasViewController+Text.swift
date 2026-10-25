import DesignSystem
import Geometry
import Model
import Rendering
import UIKit

/// The text boxes of the canvas: the start and the end of an edit, and the step that an edit
/// records (architecture.md section 7, TOOL-05, TOOL-06, D-86, D-87).
extension CanvasViewController: UITextViewDelegate {
    /// Connects the tap and long-press recognizers and the edit view.
    func installTextControls() {
        let editing = textEditing
        editing.pencilTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        editing.fingerTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        editing.longPress.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        editing.pencilTap.addTarget(self, action: #selector(handlePencilTap(_:)))
        editing.fingerTap.addTarget(self, action: #selector(handleFingerTap(_:)))
        editing.longPress.addTarget(self, action: #selector(handleLongPress(_:)))
        let recognizers: [UIGestureRecognizer] = [
            editing.pencilTap, editing.fingerTap, editing.longPress,
        ]
        for recognizer in recognizers {
            recognizer.delegate = self
            canvasView.addGestureRecognizer(recognizer)
        }
        editing.view.delegate = self
        installTextMenu()
        renderer.load(Array(content.textBoxes.values))
    }

    /// Ends a running edit and records its step (D-86). The app calls it before the move to the
    /// background, so that the text reaches the library.
    public func finishTextEdit() {
        endTextEdit()
    }

    /// Returns the canvas point of a recognizer.
    func canvasPoint(of recognizer: UIGestureRecognizer) -> Point {
        let location = recognizer.location(in: canvasView)
        return camera.canvasPoint(
            fromView: Point(x: location.x, y: location.y),
            viewSize: viewSize
        )
    }

    /// Returns the live box under a canvas point, or `nil`.
    func textBox(at point: Point) -> TextBox? {
        textEditing.box(
            at: point,
            in: content.textBoxes,
            zoom: camera.zoom,
            tapTarget: DesignSystem.Size.tapTarget
        )
    }

    /// Passes an ended pencil tap to `handlePencilTap(at:)`.
    @objc private func handlePencilTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        handlePencilTap(at: canvasPoint(of: recognizer))
    }

    /// A pencil tap with the text tool edits the box under it, or makes a new box (TOOL-05,
    /// D-87). A tap on the box of the running edit changes nothing.
    func handlePencilTap(at point: Point) {
        guard isEditingEnabled, tool == .text else { return }
        let hit = textBox(at: point)
        if let hit, hit.id == textEditing.edit?.id { return }
        endTextEdit()
        if let hit {
            startTextEdit(of: hit)
        } else {
            startNewTextBox(at: point)
        }
    }

    /// A finger tap on a box edits it with any tool. A tap beside the edited box ends the edit
    /// (TOOL-06).
    @objc private func handleFingerTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        tap(at: canvasPoint(of: recognizer))
    }

    /// A finger tap: on a box, it starts its edit at once (TOOL-06). Beside the boxes, it ends a
    /// running edit, or else opens the card under the finger (CARD-03, D-115).
    func tap(at point: Point) {
        let hit = textBox(at: point)
        guard hit?.id != textEditing.edit?.id || hit == nil else { return }
        let wasEditing = textEditing.isEditing
        endTextEdit()
        if let hit, isEditingEnabled {
            startTextEdit(of: hit)
        } else if !wasEditing {
            openCard(at: point)
        }
    }

    /// Starts the edit of a live box. The renderer hides the box under the edit view.
    func startTextEdit(of box: TextBox) {
        precondition(textEditing.edit == nil, "One edit runs at a time")
        textEditing.edit = TextEditing.Edit(
            id: box.id,
            original: box,
            origin: box.origin,
            sortKey: box.sortKey
        )
        renderer.changeTextBoxes(removing: [box.id], adding: [])
        showEditView(text: box.text)
    }

    /// Makes a new box at a canvas point and starts its edit. The first line takes the point.
    func startNewTextBox(at point: Point) {
        guard content.nodeCount < Limits.maxNodesPerCanvas else {
            onMessage(CanvasStrings.nodeLimit)
            return
        }
        let origin = Point(x: point.x, y: point.y - TextLayout.lineHeight / 2)
        textEditing.edit = TextEditing.Edit(
            id: clock.makeIdentifier(TextBoxID.self),
            original: nil,
            origin: origin,
            sortKey: nextTextSortKey()
        )
        showEditView(text: "")
        assert(textEditing.isEditing, "A new box starts an edit")
    }

    private func showEditView(text: String) {
        guard let edit = textEditing.edit else { return }
        let view = textEditing.view
        view.setText(text)
        if view.superview !== canvasView { canvasView.addSubview(view) }
        view.layOut(origin: edit.origin, camera: camera, viewSize: viewSize)
        view.undoManager?.removeAllActions()
        view.becomeFirstResponder()
        historyDidChange()
    }

    /// Returns a sort key after the keys of all boxes, so that a new box is on top.
    private func nextTextSortKey() -> FractionalIndex {
        // The largest key without a list of all keys (PERF-01, m10-plan.md task 3.6).
        let last = content.textBoxes.values.max { $0.sortKey < $1.sortKey }?.sortKey
        do {
            return try FractionalIndex.between(last, nil)
        } catch {
            // The ID breaks the tie of two equal keys (data-model.md section 6).
            logger.error("No sort key after the last text box: \(String(describing: error))")
            return last ?? Self.firstSortKey
        }
    }

    /// The key of the first text box of a canvas: the midpoint of the empty list.
    private static var firstSortKey: FractionalIndex {
        do {
            return try FractionalIndex.between(nil, nil)
        } catch {
            preconditionFailure("The empty list has a midpoint key")
        }
    }

    /// Ends the running edit, records its step, and shows the box again (D-86).
    func endTextEdit() {
        guard let edit = textEditing.edit else { return }
        textEditing.edit = nil
        let text = textEditing.view.text ?? ""
        textEditing.view.resignFirstResponder()
        textEditing.view.removeFromSuperview()
        // The key commands of undo and redo reach the canvas only as the first responder.
        becomeFirstResponder()
        do {
            if let step = try textStep(of: edit, text: text) {
                send(try perform(step))
            }
        } catch CommandError.nodeLimitReached {
            onMessage(CanvasStrings.nodeLimit)
        } catch {
            logger.error("An edit of a text box did not apply: \(String(describing: error))")
        }
        if let shown = content.textBoxes[edit.id] {
            renderer.placeTextBox(shown)
        }
        historyDidChange()
        assert(!textEditing.isEditing, "The edit ended")
    }

    /// Returns the step of an edit: an add for a new box with text, an edit for a changed box,
    /// a delete for a box that ends empty, or `nil` for no change (D-86).
    private func textStep(
        of edit: TextEditing.Edit,
        text: String
    ) throws -> (any CanvasCommand)? {
        let time = clock.now()
        guard let original = edit.original else {
            guard !text.isEmpty else { return nil }
            let box = try TextBox(
                id: edit.id,
                meta: RecordMeta(created: time),
                canvasID: content.canvasID,
                origin: edit.origin,
                text: text,
                sortKey: edit.sortKey
            )
            return AddTextBox(textBox: box)
        }
        guard !text.isEmpty else { return DeleteNode(textBox: original) }
        guard text != original.text else { return nil }
        return EditText(old: original, new: try original.editing(text: text, at: time))
    }

    /// Moves the edit view with the camera. A pinch scales it until the pinch ends (D-85).
    func textCameraDidChange(isPinching: Bool) {
        guard let edit = textEditing.edit else { return }
        let view = textEditing.view
        if isPinching, camera.zoom != view.layoutZoom {
            view.follow(origin: edit.origin, camera: camera, viewSize: viewSize)
        } else {
            view.layOut(origin: edit.origin, camera: camera, viewSize: viewSize)
        }
    }

    /// Refuses text past `Limits.maxTextLength` code points and U+0000, with a message (D-57).
    public func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        let current = (textView.text ?? "") as NSString
        guard range.location != NSNotFound, NSMaxRange(range) <= current.length else {
            return false
        }
        let next = current.replacingCharacters(in: range, with: text)
        guard !next.unicodeScalars.contains("\u{0}") else { return false }
        guard next.unicodeScalars.count <= Limits.maxTextLength else {
            onMessage(CanvasStrings.textLimit)
            return false
        }
        return true
    }

    /// Grows the edit view with its text, and updates the undo and redo buttons.
    public func textViewDidChange(_ textView: UITextView) {
        guard let edit = textEditing.edit else { return }
        textEditing.view.textDidChange()
        textEditing.view.layOut(origin: edit.origin, camera: camera, viewSize: viewSize)
        historyDidChange()
    }
}
