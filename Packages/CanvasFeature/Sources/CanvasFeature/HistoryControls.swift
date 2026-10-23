import Observation

/// The state and the actions of the undo, redo, and export buttons (UNDO-01, EXP-01).
@MainActor
@Observable
final class HistoryControls {
    /// `true` if the undo list holds a step.
    var canUndo = false
    /// `true` if the redo list holds a step.
    var canRedo = false
    /// `true` while an export runs. The export button is off then (EXP-01).
    var isExporting = false
    /// Runs an undo.
    @ObservationIgnored var undo: () -> Void = {}
    /// Runs a redo.
    @ObservationIgnored var redo: () -> Void = {}
    /// Exports the canvas as a PDF.
    @ObservationIgnored var export: () -> Void = {}
}
