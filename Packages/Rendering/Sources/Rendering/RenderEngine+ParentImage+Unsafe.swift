import Metal

/// The handoff of the frozen copy of a parent frame to the renderer of the child (D-109).
extension RenderEngine {
    /// Carries the frozen copy from the lock of one engine to the lock of another.
    ///
    /// Safe: the parent drops its reference in the same lock that takes the copy, so after the
    /// handoff the child is the only owner, and only its render thread reads the texture. The
    /// handoff waits for the completion flag of the command buffer that wrote the texture, so
    /// the GPU no longer writes it (review of 2026-10-28, 3.2.13). The box never leaves this
    /// file.
    private struct ParentImageBox: @unchecked Sendable {
        let image: InkTarget
    }

    /// Moves the frozen copy of the parent frame from this engine to the engine of the child
    /// after an open (D-109), if neither render thread holds its frame lock. The main actor
    /// calls it, so it never waits for a frame (review after M9, section 3.2, item 3). The two
    /// render threads never hold both locks, so the nested tries cannot deadlock.
    ///
    /// - Precondition: `child` is another engine.
    /// - Returns: `false` if a frame held a lock, or if the command buffer of the freeze did not
    ///   complete yet, and nothing moved. Then the caller tries again.
    func tryGiveParentImage(to child: RenderEngine) -> Bool {
        precondition(child !== self, "A parent gives its image to another engine")
        let moved = core.withLockIfAvailable { parent -> Bool in
            guard let transition = parent.transition, let frozen = transition.frozen else {
                return true
            }
            guard transition.frozenCompletion.isSet else { return false }
            let box = ParentImageBox(image: frozen)
            let given = child.core.withLockIfAvailable { renderer -> Bool in
                renderer.parentImage = box.image
                return true
            }
            guard given == true else { return false }
            parent.transition?.frozen = nil
            return true
        }
        return moved == true
    }
}
