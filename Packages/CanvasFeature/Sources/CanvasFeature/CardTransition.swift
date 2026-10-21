import Geometry

/// The open of a card on its parent canvas, or the leave of a child into its card (architecture.md
/// 6.2 and 6.3, D-98). The camera flight sets the weight of the parent each frame.
struct CardTransition {
    /// `true` for an open: the parent fades out. `false` for a leave: the parent fades in.
    let isOpen: Bool
    /// The camera before the flight, for a cancel.
    let start: Camera
    /// Runs once at the end of the flight.
    let onEnd: @MainActor () -> Void
}
