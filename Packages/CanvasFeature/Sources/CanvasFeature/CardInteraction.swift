import Geometry
import Model

/// The state of the card gestures of one canvas: the move of a card, the card of the open
/// long-press menu, and the pending card of the card button with its drag (CARD-01, CARD-07,
/// CARD-08). It left `TextEditing`, which holds the state of the text tools (review of
/// 2026-10-28, 3.4.1).
@MainActor
final class CardInteraction {
    /// The move of a card with a finger (CARD-07, D-10).
    struct Move {
        /// The card before the move.
        let card: Card
        /// The finger point at the start, in canvas space.
        let start: Point
        /// The card at the last finger point.
        var current: Card
    }

    /// The running move of a card, or `nil`.
    var move: Move?
    /// The card of the open long-press menu, or `nil` (CARD-08).
    var menuCard: Card?
    /// The card of the card button that waits for a drag onto the canvas, or `nil`. It is not
    /// part of the content until the drag ends (CARD-01, D-117).
    var pendingCard: Card?
    /// The running drag of the pending card, or `nil`.
    var pendingDrag: Move?
}
