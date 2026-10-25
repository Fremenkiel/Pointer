import Dispatch
import Geometry
import Model

/// The cards of the renderer (architecture.md 5.5, D-96).
extension CanvasRenderer {
    /// `true` while the titles of a card load are laid out off the render thread or wait for a
    /// frame (D-92). `needsMoreFrames` does not count it, so the first frame does not wait for it.
    public var isLoadingCards: Bool { engine.isLoadingCards }

    /// `true` while a card preview waits, decodes, or waits for its upload (D-97).
    public var isLoadingPreviews: Bool { engine.isLoadingPreviews }

    /// Renders the preview of this canvas for the card of the canvas in its parent (m6-plan.md
    /// task 3.4, D-97, D-98): the child region of the open camera `camera`, cut to the aspect of
    /// the card. The longer side has `size` pixels. The render runs in chunks inside the
    /// instance budget, so no frame drops. A newer request ends a waiting one with `nil`.
    /// `completion` gets the image, or `nil` if the render failed. It runs off the main actor, so
    /// it can encode the PNG and write the file there.
    ///
    /// - Precondition: `cardAspect` is positive and finite, and `size` is from 1 to 512.
    public func renderPreview(
        camera: Camera,
        cardAspect: Double,
        size: Int = PreviewImage.maxSide,
        completion: @escaping @Sendable (PreviewImage?) -> Void
    ) {
        precondition(cardAspect > 0 && cardAspect.isFinite, "Card aspect \(cardAspect)")
        precondition(size > 0 && size <= PreviewImage.maxSide, "Preview size \(size)")
        let request = PreviewRenderRequest(
            camera: camera,
            cardAspect: cardAspect,
            size: size,
            completion: completion
        )
        engine.post { box in
            box.previewRender?.endWithoutImage()
            box.previewRender = request
        }
    }

    /// Shows a new preview of the child canvas of `card` without a read of its file, for the
    /// parent after a leave (m6-plan.md task 3.4).
    ///
    /// - Precondition: The longer side of `image` is at most 512 pixels.
    public func showPreview(_ image: PreviewImage, of card: CardID) {
        let side = max(image.width, image.height)
        precondition(side <= PreviewImage.maxSide, "A preview has at most 512 pixels a side")
        let preview = DecodedPreview(
            card: card,
            step: PreviewAtlas.step(forPixels: Double(side)),
            width: image.width,
            height: image.height,
            outcome: .pixels(image.pixels)
        )
        engine.post { box in box.decodedPreviews.append(preview) }
    }

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
