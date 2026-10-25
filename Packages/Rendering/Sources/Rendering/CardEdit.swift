import Model

/// One change of the cards that the main actor sends to the render thread: an add, a rename, a
/// move, or a delete (architecture.md 5.5).
enum CardEdit: Sendable {
    /// Removes the cards of `removed`, then adds the cards of `added`. An added card takes the
    /// place of the card with the same ID.
    case change(removed: [CardID], added: [Card])
    /// Puts one card in the place of the card with the same ID, or adds it. A drag step posts
    /// it without an array (PERF-01, m10-plan.md task 3.1).
    case place(Card)
}
