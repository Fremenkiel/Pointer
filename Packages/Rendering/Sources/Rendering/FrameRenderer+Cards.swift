import Model

/// The card changes of the frame work (architecture.md 5.5, D-96).
extension FrameRenderer {
    /// Adds the cards of a load with their title layouts (D-92). A card that an edit changed
    /// during the load keeps the edit.
    func insert(_ loaded: [CardStore.LaidOut]) {
        precondition(loaded.count <= Limits.maxNodesPerCanvas, "Too many cards")
        for item in loaded where !cards.editedDuringLoad.contains(item.card.id) {
            cards.insert(item.card, layout: item.layout)
        }
        assert(cards.count <= Limits.maxNodesPerCanvas, "The store holds at most the node limit")
    }

    /// Applies one card edit to the card store.
    func apply(_ edit: CardEdit) {
        precondition(
            edit.removed.count + edit.added.count <= Limits.maxNodesPerCanvas,
            "Too many cards in one edit"
        )
        if cards.loadsInFlight > 0 {
            cards.editedDuringLoad.formUnion(edit.removed)
            cards.editedDuringLoad.formUnion(edit.added.map(\.id))
        }
        for id in edit.removed {
            cards.remove(id)
        }
        for card in edit.added {
            cards.add(card)
        }
        assert(edit.added.allSatisfy { cards.entries[$0.id] != nil }, "Each added card is held")
    }
}
