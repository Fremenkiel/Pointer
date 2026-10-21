/// The transition commands of the engine (D-98).
extension RenderEngine {
    /// Applies the end, the start, and the weight of a transition, in this order, so that a new
    /// start after an end in the same frame wins.
    static func applyTransition(_ input: RenderInput, to renderer: FrameRenderer) {
        precondition(input.transitionWeight.map { (0...1).contains($0) } ?? true, "Weight")
        if input.endsTransition, renderer.transition != nil {
            renderer.transition = nil
        }
        if let start = input.transitionStart {
            // An open starts with the parent in full, a leave with the card alone.
            renderer.transition = FrameTransition(
                card: start.card,
                parentWeight: start.isOpen ? 1 : 0,
                freezes: start.isOpen,
                frozen: nil
            )
        }
        if let weight = input.transitionWeight {
            renderer.transition?.parentWeight = weight
        }
        if input.endsPinchExit { renderer.pinchExit = nil }
        if let exit = input.pinchExit { renderer.pinchExit = exit }
        assert(
            renderer.transition.map { (0...1).contains($0.parentWeight) } ?? true,
            "A parent weight is from 0 to 1"
        )
    }
}
