import DesignSystem
import Geometry
import Model
import SwiftUI
import UIKit

/// Undo and redo of the canvas (architecture.md section 8, UNDO-01, UNDO-02).
extension CanvasViewController {
    /// Undoes the newest step of this canvas. It does nothing if the undo list is empty.
    public func undo() {
        let command = history.undoSteps.last
        runStep(command, isUndo: true) { history, content, clock throws(CommandError) in
            try history.undo(on: &content, clock: &clock)
        }
    }

    /// Redoes the newest undone step of this canvas. It does nothing if the redo list is empty.
    public func redo() {
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
    /// the library, and asks for a save.
    private func runStep(
        _ command: (any CanvasCommand)?,
        isUndo: Bool,
        _ step: (inout History, inout CanvasContent, inout HybridClock) throws(CommandError) ->
            [LibraryChange]
    ) {
        let rows: [LibraryChange]
        do {
            rows = try step(&history, &content, &clock.factory.clock)
        } catch {
            logger.error("An undo or a redo did not apply: \(String(describing: error))")
            return
        }
        guard !rows.isEmpty else { return }
        let (removed, added) =
            Self.renderDelta(of: command, isUndo: isUndo) ?? renderDelta(of: rows)
        renderer.change(
            removing: removed,
            adding: added,
            area: (command as? EraseStrokes)?.area,
            onCompleted: stepDrawnCallback(),
            onPresented: {}
        )
        // The send schedules the save of the rows (P-09).
        send(rows)
        historyDidChange()
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

    /// Returns the callback of the GPU end of a step for `onStepDrawn`, or `nil` without it, so
    /// that the renderer adds no handler to the frame (P-08).
    func stepDrawnCallback() -> (@MainActor (Double) -> Void)? {
        guard onStepDrawn != nil else { return nil }
        return { [weak self] time in self?.onStepDrawn?(time) }
    }

    /// Keeps the session of this visit in the sessions of the app (D-12). The app calls it
    /// before it makes the next canvas screen, so that a screen of the same canvas finds the
    /// steps of this visit (F-02). A second call does nothing.
    public func endSession() {
        guard !hasEndedSession else { return }
        hasEndedSession = true
        saveSession()
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
        historyControls.canUndo = history.canUndo
        historyControls.canRedo = history.canRedo
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
