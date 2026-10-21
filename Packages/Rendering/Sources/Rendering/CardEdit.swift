import Model

/// One change of the cards that the main actor sends to the render thread: an add, a rename, a
/// move, or a delete (architecture.md 5.5).
struct CardEdit: Sendable {
    /// The cards to remove.
    let removed: [CardID]
    /// The cards to add, or to put in the place of the card with the same ID.
    let added: [Card]
}
