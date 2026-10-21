import Dispatch
import Model

/// The cards of the renderer (architecture.md 5.5, D-96).
extension CanvasRenderer {
    /// `true` while the titles of a card load are laid out off the render thread or wait for a
    /// frame (D-92). `needsMoreFrames` does not count it, so the first frame does not wait for it.
    public var isLoadingCards: Bool { engine.isLoadingCards }

    /// Adds the cards of a load without a callback. Their titles are laid out off the render
    /// thread in the chunks of the text load, so the first frame does not wait for them (D-92).
    /// An edit of a card during the layout wins over the loaded card.
    ///
    /// - Precondition: The canvas holds at most `Limits.maxNodesPerCanvas` cards.
    public func load(_ cards: [Card]) {
        precondition(cards.count <= Limits.maxNodesPerCanvas, "Too many cards")
        guard !cards.isEmpty else { return }
        let engine = engine
        let count = cards.count
        engine.post { box in
            box.cardLoadsInFlight += 1
            box.cardReserve = count
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let laidOut = CardStore.layOut(cards)
            engine.post { box in
                box.laidOutCards += laidOut
                box.cardLoadsInFlight -= 1
                assert(box.cardLoadsInFlight >= 0, "A load ends once")
            }
        }
    }

    /// Removes cards and adds cards in one change: an add, a rename, a move, or a delete. An
    /// added card takes the place of the card with the same ID.
    ///
    /// - Precondition: The change holds at most `Limits.maxNodesPerCanvas` cards.
    public func changeCards(removing removed: [CardID], adding added: [Card]) {
        precondition(removed.count + added.count <= Limits.maxNodesPerCanvas, "Too many cards")
        precondition(added.allSatisfy { $0.frame.origin.isFinite }, "A card frame is not finite")
        let edit = CardEdit(removed: removed, added: added)
        engine.post { box in box.cardEdits.append(edit) }
    }
}
