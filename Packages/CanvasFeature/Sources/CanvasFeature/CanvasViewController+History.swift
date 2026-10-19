import DesignSystem
import Model
import SwiftUI
import UIKit

/// Undo and redo of the canvas (architecture.md section 8, UNDO-01, UNDO-02).
extension CanvasViewController {
    /// Undoes the newest step of this canvas. It does nothing if the undo list is empty.
    public func undo() {
        runStep { history, content, clock throws(CommandError) in
            try history.undo(on: &content, clock: &clock)
        }
    }

    /// Redoes the newest undone step of this canvas. It does nothing if the redo list is empty.
    public func redo() {
        runStep { history, content, clock throws(CommandError) in
            try history.redo(on: &content, clock: &clock)
        }
    }

    /// Applies a new command as one undo step and keeps the session (D-12).
    ///
    /// - Throws: The `CommandError` of the command. The content then stays as it was.
    /// - Returns: The changed rows for the library.
    func perform(_ command: any CanvasCommand) throws(CommandError) -> [LibraryChange] {
        let rows = try history.perform(command, on: &content, clock: &clock.factory.clock)
        historyDidChange()
        return rows
    }

    /// Runs an undo or a redo, then sends the change to the renderer and the rows to the library,
    /// and asks for a save.
    private func runStep(
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
        let (removed, added) = renderDelta(of: rows)
        renderer.change(removing: removed, adding: added, onPresented: {})
        send(rows)
        requestSave()
        historyDidChange()
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

    /// Keeps the session of the canvas and updates the buttons.
    func historyDidChange() {
        sessions?.save(
            CanvasSession(history: history, erased: content.erased),
            for: content.canvasID
        )
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
