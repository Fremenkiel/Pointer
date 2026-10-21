/// The changes of the cards. `cards` holds the live cards only, as `textBoxes` does (D-68). A
/// command keeps the `Card` value of a deleted card for its undo, and `add(_:)` puts it back. A
/// delete marks the card only, and its child content stays (D-18).
extension CanvasContent {
    /// Puts a changed card in the place of the live card with the same ID.
    ///
    /// - Precondition: The canvas holds the card as a live card, and `card` is not a tombstone.
    /// - Returns: The card before the change.
    public mutating func replace(_ card: Card) -> Card {
        precondition(!card.meta.isDeleted, "Card \(card.id) is a tombstone")
        guard let earlier = cards.updateValue(card, forKey: card.id) else {
            preconditionFailure("Canvas holds no live card \(card.id)")
        }
        assert(earlier.canvasID == card.canvasID, "A card keeps its canvas")
        return earlier
    }

    /// Removes a live card. The caller sends its tombstone to the library.
    ///
    /// - Precondition: The canvas holds the card as a live card.
    /// - Returns: The removed card.
    public mutating func removeCard(_ id: CardID) -> Card {
        let removed = cards.removeValue(forKey: id)
        guard let removed else { preconditionFailure("Canvas holds no live card \(id)") }
        assert(cards[id] == nil, "The card \(id) left the content")
        return removed
    }

    /// Puts `card` with the change time `time` in the place of its live card, for a command.
    ///
    /// - Throws: `CommandError.cardNotLive` if the card is not live.
    /// - Returns: The row of the changed card.
    mutating func change(
        to card: Card,
        at time: HybridTimestamp
    ) throws(CommandError) -> LibraryChange {
        guard cards[card.id] != nil else { throw .cardNotLive(card.id) }
        let changed = card.marking(deleted: false, at: time)
        _ = replace(changed)
        return .card(changed)
    }

    /// Puts `card` back as a live card with the change time `time`, for a command.
    ///
    /// - Throws: `CommandError.cardAlreadyLive` if the card is live, or
    ///   `CommandError.nodeLimitReached` at the node limit.
    /// - Returns: The row of the live card.
    mutating func revive(
        _ card: Card,
        at time: HybridTimestamp
    ) throws(CommandError) -> LibraryChange {
        guard cards[card.id] == nil else { throw .cardAlreadyLive(card.id) }
        let live = card.marking(deleted: false, at: time)
        do {
            try add(live)
        } catch {
            throw .nodeLimitReached
        }
        return .card(live)
    }

    /// Removes the live card `id` and returns its tombstone with the change time `time`, for a
    /// command.
    ///
    /// - Throws: `CommandError.cardNotLive` if the card is not live.
    /// - Returns: The row of the tombstone.
    mutating func bury(
        _ id: CardID,
        at time: HybridTimestamp
    ) throws(CommandError) -> LibraryChange {
        guard cards[id] != nil else { throw .cardNotLive(id) }
        return .card(removeCard(id).marking(deleted: true, at: time))
    }
}
