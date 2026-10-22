import DesignSystem
import Geometry
import Model
import SwiftUI
import UIKit

/// Undo and redo of the canvas (architecture.md section 8, UNDO-01, UNDO-02).
extension CanvasViewController {
    /// Undoes the newest step of this canvas. It does nothing if the undo list is empty.
    public func undo() {
        // During an edit, undo and redo act on the text view (D-86).
        if textEditing.isEditing {
            textEditing.view.undoManager?.undo()
            historyDidChange()
            return
        }
        let command = history.undoSteps.last
        runStep(command, isUndo: true) { history, content, clock throws(CommandError) in
            try history.undo(on: &content, clock: &clock)
        }
    }

    /// Redoes the newest undone step of this canvas. It does nothing if the redo list is empty.
    public func redo() {
        if textEditing.isEditing {
            textEditing.view.undoManager?.redo()
            historyDidChange()
            return
        }
        let command = history.redoSteps.last
        runStep(command, isUndo: false) { history, content, clock throws(CommandError) in
            try history.redo(on: &content, clock: &clock)
        }
    }

    /// Applies a new command as one undo step and keeps the session (D-12).
    ///
    /// - Throws: The `CommandError` of the command. The content then stays as it was.
    /// - Returns: The changed rows for the library.
    func perform(_ command: any CanvasCommand) throws(CommandError) -> [LibraryChange] {
        let performed = try history.perform(command, on: &content, clock: &clock.factory.clock)
        if !performed.dropped.isEmpty {
            // The dropped steps can no longer be undone, so their records leave memory (D-76).
            content.forgetRecords(of: history.unheldStrokeIDs(of: performed.dropped))
        }
        historyDidChange()
        return performed.changes
    }

    /// Runs an undo or a redo of `command`, then sends the change to the renderer and the rows to
    /// the library, and asks for a save. An erase and an add give their change to the renderer
    /// before the model step, so the frame starts earlier (D-122).
    private func runStep(
        _ command: (any CanvasCommand)?,
        isUndo: Bool,
        _ step: (inout History, inout CanvasContent, inout HybridClock) throws(CommandError) ->
            [LibraryChange]
    ) {
        let early = Self.renderDelta(of: command, isUndo: isUndo)
        if let early { showStep(early, of: command) }
        let rows: [LibraryChange]
        do {
            rows = try step(&history, &content, &clock.factory.clock)
        } catch {
            logger.error("An undo or a redo did not apply: \(String(describing: error))")
            if let early { restoreRenderer(after: early) }
            return
        }
        guard !rows.isEmpty else { return }
        let nodes = Self.nodeDelta(of: rows)
        if !nodes.removedTexts.isEmpty || !nodes.addedTexts.isEmpty {
            renderer.changeTextBoxes(removing: nodes.removedTexts, adding: nodes.addedTexts)
        }
        if !nodes.removedCards.isEmpty || !nodes.addedCards.isEmpty {
            renderer.changeCards(removing: nodes.removedCards, adding: nodes.addedCards)
        }
        if early == nil {
            let late = renderDelta(of: rows)
            if !late.removed.isEmpty || !late.added.isEmpty || nodes.rowCount != rows.count {
                showStep(late, of: command)
            }
        }
        // The send schedules the save of the rows (P-09).
        send(rows)
        historyDidChange()
    }

    /// Gives the strokes of a step to the renderer, with the area of an erase.
    private func showStep(
        _ delta: (removed: [StrokeID], added: [Stroke]),
        of command: (any CanvasCommand)?
    ) {
        renderer.change(
            removing: delta.removed,
            adding: delta.added,
            area: (command as? EraseStrokes)?.area,
            onCompleted: stepDrawnCallback(),
            onPresented: {}
        )
    }

    /// Takes back a change that the renderer got before a model step that then failed (D-122).
    /// The renderer then shows the strokes of the change as the model holds them: an added
    /// stroke that is not live goes, and a removed stroke that is live comes back.
    func restoreRenderer(after delta: (removed: [StrokeID], added: [Stroke])) {
        let stale = delta.added.map(\.id).filter { content.strokes[$0] == nil }
        let back = delta.removed.compactMap { content.strokes[$0] }
        assert(stale.count <= delta.added.count, "Only added strokes go")
        guard !stale.isEmpty || !back.isEmpty else { return }
        renderer.change(removing: stale, adding: back, area: nil, onPresented: {})
    }

    /// Returns the strokes that a step of an erase or an add removes from the screen and adds to
    /// it, from the command itself, or `nil` for another command (P-06). An undo of an erase
    /// removes the parts and adds the cut strokes, and its redo does the reverse.
    private static func renderDelta(
        of command: (any CanvasCommand)?,
        isUndo: Bool
    ) -> (removed: [StrokeID], added: [Stroke])? {
        if let erase = command as? EraseStrokes {
            let undoDelta = (erase.parts.map(\.id), erase.removed)
            let redoDelta = (erase.removed.map(\.id), erase.parts)
            return isUndo ? undoDelta : redoDelta
        }
        if let add = command as? AddStroke {
            return isUndo ? (add.strokes.map(\.id), []) : ([], add.strokes)
        }
        return nil
    }

    /// Returns the strokes that the rows of a step remove from the screen and add to it.
    private func renderDelta(of rows: [LibraryChange]) -> (removed: [StrokeID], added: [Stroke]) {
        var removed: [StrokeID] = []
        var added: [Stroke] = []
        for row in rows {
            switch row {
            case .stroke(let stroke):
                added.append(stroke)
            case .erase(let record) where record.isDeleted:
                guard let stroke = content.strokes[record.strokeID] else {
                    assertionFailure("A restored stroke \(record.strokeID) is not live")
                    continue
                }
                added.append(stroke)
            case .erase(let record):
                removed.append(record.strokeID)
            case .card, .textBox:
                continue
            }
        }
        return (removed, added)
    }

    /// The text boxes and the cards that the rows of a step remove from the screen and add to
    /// it.
    struct NodeDelta {
        var removedTexts: [TextBoxID] = []
        var addedTexts: [TextBox] = []
        var removedCards: [CardID] = []
        var addedCards: [Card] = []

        /// The rows of text boxes and cards.
        var rowCount: Int {
            removedTexts.count + addedTexts.count + removedCards.count + addedCards.count
        }
    }

    /// Returns the text boxes and the cards of the rows of a step, in one pass: a tombstone
    /// removes a box or a card, and a live one takes its place.
    static func nodeDelta(of rows: [LibraryChange]) -> NodeDelta {
        var delta = NodeDelta()
        for row in rows {
            switch row {
            case .textBox(let box) where box.meta.isDeleted: delta.removedTexts.append(box.id)
            case .textBox(let box): delta.addedTexts.append(box)
            case .card(let card) where card.meta.isDeleted: delta.removedCards.append(card.id)
            case .card(let card): delta.addedCards.append(card)
            case .stroke, .erase: continue
            }
        }
        assert(delta.rowCount <= rows.count, "Each node row gives one change")
        return delta
    }

    /// Returns the callback of the GPU end of a step for `onStepDrawn`, or `nil` without it, so
    /// that the renderer adds no handler to the frame (P-08).
    func stepDrawnCallback() -> (@MainActor (Double) -> Void)? {
        guard onStepDrawn != nil else { return nil }
        return { [weak self] time in self?.onStepDrawn?(time) }
    }

    /// Takes the history and the erase records of an earlier visit of the canvas from the
    /// sessions of the app, so that an undo reaches the steps of that visit (D-12).
    func takeSession() {
        guard let session = sessions?.take(for: content.canvasID) else { return }
        history = session.history
        // The content is new, so it holds no erase record yet.
        let skipped = content.adoptSessionRecords(session.erased)
        assert(skipped == 0, "\(skipped) erase records of the session do not fit the load")
    }

    /// Keeps the session of this visit in the sessions of the app (D-12). The app calls it
    /// before it makes the next canvas screen, so that a screen of the same canvas finds the
    /// steps of this visit (F-02). A pending card joins the canvas first (D-123). A second call
    /// does nothing.
    public func endSession() {
        endTextEdit()
        placePendingCard()
        guard !hasEndedSession else { return }
        hasEndedSession = true
        saveSession()
    }

    /// Takes back the session that `endSession()` kept, because the screen stays after an open
    /// or a leave that did not finish (D-131). The steps after that then go into the session
    /// again. A session that `discardSession()` dropped stays dropped (M-03).
    func resumeSession() {
        guard hasEndedSession, let sessions, sessions.hasSession(for: canvasID) else { return }
        // The screen holds the newest history, so the saved copy goes, and the screen is again
        // the only owner of its history.
        _ = sessions.take(for: canvasID)
        hasEndedSession = false
    }

    /// Drops the session of this visit, because the workspace of the canvas is deleted (M-03).
    /// The canvas then keeps no session when it leaves.
    public func discardSession() {
        hasEndedSession = true
    }

    /// Keeps the session of the canvas for the time the app runs (D-12). The canvas calls it when
    /// it leaves the screen, not at each step: a copy at each step made the next step copy the
    /// erase records of the session (M4 task 3.8).
    func saveSession() {
        sessions?.save(
            CanvasSession(history: history, erased: content.erased),
            for: content.canvasID
        )
    }

    /// Updates the buttons after a step.
    func historyDidChange() {
        // During an edit, the buttons show the steps of the text view (D-86).
        guard textEditing.isEditing else {
            historyControls.canUndo = history.canUndo
            historyControls.canRedo = history.canRedo
            return
        }
        historyControls.canUndo = textEditing.view.undoManager?.canUndo ?? false
        historyControls.canRedo = textEditing.view.undoManager?.canRedo ?? false
    }

    /// Shows the undo and redo buttons in the top right corner (UNDO-01).
    func installHistoryButtons() {
        historyControls.undo = { [weak self] in self?.undo() }
        historyControls.redo = { [weak self] in self?.redo() }
        let host = UIHostingController(rootView: HistoryButtons(controls: historyControls))
        host.view.backgroundColor = .clear
        host.sizingOptions = .intrinsicContentSize
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(
                equalTo: guide.topAnchor,
                constant: DesignSystem.Spacing.large
            ),
            host.view.trailingAnchor.constraint(
                equalTo: guide.trailingAnchor,
                constant: -DesignSystem.Spacing.large
            ),
        ])
        host.didMove(toParent: self)
        historyDidChange()
    }

    /// Command-Z and Shift-Command-Z on a hardware keyboard (architecture.md section 8).
    override public var keyCommands: [UIKeyCommand]? {
        historyKeyCommands
    }

    /// Makes the key commands of undo and redo.
    func makeHistoryKeyCommands() -> [UIKeyCommand] {
        [
            UIKeyCommand(
                title: CanvasStrings.undo,
                action: #selector(undoKey),
                input: "z",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: CanvasStrings.redo,
                action: #selector(redoKey),
                input: "z",
                modifierFlags: [.command, .shift]
            ),
        ]
    }

    /// The canvas takes the key commands.
    override public var canBecomeFirstResponder: Bool { true }

    @objc private func undoKey() { undo() }

    @objc private func redoKey() { redo() }
}

extension CanvasSession {
    /// Makes a session from a history and the erase records of the content.
    init(history: History, erased: [StrokeID: EraseRecord]) {
        self.init()
        self.history = history
        self.erased = erased
    }
}
