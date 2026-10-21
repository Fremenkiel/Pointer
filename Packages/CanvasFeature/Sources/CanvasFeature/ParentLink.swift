import Geometry
import Model
import Rendering

/// The link of a child canvas to its parent for the pinch-out exit (CARD-05, D-109): the card
/// of the child in the parent, the leave, and the exit that shows.
@MainActor
final class ParentLink {
    /// The card of the canvas in its parent, or `nil` if the app does not know it.
    let card: Card?
    /// Leaves the canvas for its parent after a pinch-out exit.
    let onLeave: @MainActor () -> Void
    /// The exit that the renderer shows, or `nil`.
    var exit: PinchExit?

    init(card: Card?, onLeave: @escaping @MainActor () -> Void) {
        self.card = card
        self.onLeave = onLeave
    }
}
