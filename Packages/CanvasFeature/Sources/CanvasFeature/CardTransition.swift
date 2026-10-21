import Geometry

/// The open of a card on its parent canvas, or a part of the leave of a child into its card
/// (architecture.md 6.2 and 6.3, D-98, D-109). The camera flight sets the weight of the parent
/// each frame.
struct CardTransition {
    /// What the flight does.
    enum Kind {
        /// The parent flies until the card covers the screen and fades out under it.
        case open
        /// The parent flies from the card to the camera of CARD-04 and fades in around it.
        case leave
        /// The child flies to the camera of its open before a leave. No weight changes.
        case settle
    }

    /// What the flight does.
    let kind: Kind
    /// The camera before the flight, for a cancel.
    let start: Camera
    /// Runs once at the end of the flight.
    let onEnd: @MainActor () -> Void
}
