import Model

/// The open and the leave of a card on the renderer of the parent canvas (architecture.md 6.2
/// and 6.3, D-98, D-108, D-109, D-110).
extension CanvasRenderer {
    /// The crossfade from the preview to the first frame of the child, and back for a leave
    /// (D-98). The canvas fades the view of the child with it.
    public static let crossfadeDuration = 0.1

    /// Starts the open of `card`. The next frame copies the shown image into one texture and
    /// frees the committed textures and the eraser mask. Until the end, each frame draws the
    /// copy with the parent weight and the card on top at full weight. The weight starts at 1.
    public func beginOpen(of card: CardID) {
        let start = TransitionStart(card: card, isOpen: true)
        engine.post { box in
            box.transitionStart = start
            box.transitionWeight = nil
        }
    }

    /// Starts the leave of a child into `card` on the loaded parent. Each frame draws the
    /// parent with the parent weight and the card on top at full weight. The weight starts at 0.
    public func beginLeave(into card: CardID) {
        let start = TransitionStart(card: card, isOpen: false)
        engine.post { box in
            box.transitionStart = start
            box.transitionWeight = nil
        }
    }

    /// Sets the weight of the parent image of the running transition: 1 shows the parent in
    /// full, 0 shows the card alone. The camera animation sets it each frame (m6-plan.md
    /// section 4, rule 7).
    ///
    /// - Precondition: `weight` is from 0 to 1.
    public func setParentWeight(_ weight: Double) {
        precondition((0...1).contains(weight), "A parent weight is from 0 to 1, got \(weight)")
        engine.post { box in box.transitionWeight = weight }
    }

    /// Ends the transition. A renderer whose committed textures went makes new ones.
    public func endTransition() {
        engine.post { box in box.endsTransition = true }
    }
}
