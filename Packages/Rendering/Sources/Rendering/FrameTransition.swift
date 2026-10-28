import Geometry
import Model

/// The start of an open or a leave, from the main actor to the render thread.
struct TransitionStart: Sendable {
    /// The opened card.
    let card: CardID
    /// `true` for an open, `false` for a leave.
    let isOpen: Bool
}

/// An open or a leave of a card on the renderer of the parent canvas (architecture.md 6.2 and
/// 6.3, D-98, D-108, D-109, D-110).
struct FrameTransition {
    /// The opened card.
    let card: CardID
    /// The weight of the parent image, from 0 to 1. The camera animation sets it each frame.
    var parentWeight: Double
    /// `true` for an open: the next frame freezes the shown image and frees the committed
    /// textures. `false` for a leave, which shows the live committed texture.
    let freezes: Bool
    /// The frozen copy of the parent frame, or `nil` before the freeze and in a leave (D-109).
    var frozen: InkTarget?
    /// Set when the command buffer that wrote the frozen copy completed, so that the handoff to
    /// the child never gives a texture that the GPU still writes (review of 2026-10-28, 3.2.13).
    var frozenCompletion = CompletionFlag()
    /// `true` after the first frame of an open froze the parent, also without a shown image.
    /// The frames after it change only with the flight, the weight, or a preview.
    var isFrozen = false
}
