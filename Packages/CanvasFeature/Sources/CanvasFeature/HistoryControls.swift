import Observation

/// The state and the actions of the undo, redo, clear, and export buttons (UNDO-01, EXP-01,
/// TOOL-10).
@MainActor
@Observable
final class HistoryControls {
    /// `true` if the undo list holds a step.
    var canUndo = false
    /// `true` if the redo list holds a step.
    var canRedo = false
    /// `true` if the canvas holds ink, a text box, or a card. The clear button is off on an
    /// empty canvas (TOOL-10).
    var canClear = false
    /// `true` while an export runs. The export button is off then (EXP-01).
    var isExporting = false
    /// Runs an undo.
    @ObservationIgnored var undo: () -> Void = {}
    /// Runs a redo.
    @ObservationIgnored var redo: () -> Void = {}
    /// Asks before the clear of the canvas, then clears it (D-200).
    @ObservationIgnored var clear: () -> Void = {}
    /// Exports the canvas as a PDF.
    @ObservationIgnored var export: () -> Void = {}
}
