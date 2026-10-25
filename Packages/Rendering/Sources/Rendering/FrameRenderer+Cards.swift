import Geometry
import Model

/// The card changes of the frame work (architecture.md 5.5, D-96).
extension FrameRenderer {
    /// Adds the cards of a load with their title layouts and redraws the green channel of their
    /// area (D-92, D-96). A card that an edit changed during the load keeps the edit.
    func insert(_ loaded: [CardStore.LaidOut]) {
        precondition(loaded.count <= Limits.maxNodesPerCanvas, "Too many cards")
        for item in loaded where !cards.editedDuringLoad.contains(item.card.id) {
            cards.insert(item.card, layout: item.layout)
            guard let bounds = cards.entries[item.card.id]?.bounds else { continue }
            dirtyTextArea = dirtyTextArea.map { Self.union($0, bounds) } ?? bounds
        }
        assert(cards.count <= Limits.maxNodesPerCanvas, "The store holds at most the node limit")
    }

    /// Applies one card edit: it changes the card store and notes the old and the new bounds for
    /// a green redraw in the next frame, which draws the cards and the text there again (D-96).
    func apply(_ edit: CardEdit) {
        switch edit {
        case .change(let removed, let added):
            precondition(
                removed.count + added.count <= Limits.maxNodesPerCanvas,
                "Too many cards in one edit"
            )
            for id in removed {
                if cards.loadsInFlight > 0 { cards.editedDuringLoad.insert(id) }
                previews?.forget(id)
                guard let bounds = cards.remove(id) else { continue }
                dirtyTextArea = dirtyTextArea.map { Self.union($0, bounds) } ?? bounds
            }
            for card in added { place(card) }
        case .place(let card):
            place(card)
        }
    }

    /// Puts a card in the store and notes its old and new bounds for the green redraw.
    private func place(_ card: Card) {
        if cards.loadsInFlight > 0 { cards.editedDuringLoad.insert(card.id) }
        let earlier = cards.add(card)
        assert(cards.entries[card.id] != nil, "The placed card \(card.id) is held")
        guard let bounds = cards.entries[card.id]?.bounds else { return }
        let area = earlier.map { Self.union($0, bounds) } ?? bounds
        dirtyTextArea = dirtyTextArea.map { Self.union($0, area) } ?? area
    }
}
