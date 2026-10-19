import Observation

/// The state and the actions of the undo and redo buttons (UNDO-01).
@MainActor
@Observable
final class HistoryControls {
    /// `true` if the undo list holds a step.
    var canUndo = false
    /// `true` if the redo list holds a step.
    var canRedo = false
    /// Runs an undo.
    @ObservationIgnored var undo: () -> Void = {}
    /// Runs a redo.
    @ObservationIgnored var redo: () -> Void = {}
}
