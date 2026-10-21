import Metal

/// The handoff of the frozen copy of a parent frame to the renderer of the child (D-109).
extension RenderEngine {
    /// Carries the frozen copy from the lock of one engine to the lock of another.
    ///
    /// Safe: the parent drops its reference in the same lock that takes the copy, so after the
    /// handoff the child is the only owner, and only its render thread reads the texture. The
    /// parent wrote the texture in the first frame of the open, 0.35 s and about 40 frames before
    /// the handoff at the end of the open, so that command buffer has completed. The box never
    /// leaves this file.
    private struct ParentImageBox: @unchecked Sendable {
        let image: InkTarget
    }

    /// Moves the frozen copy of the parent frame from this engine to the engine of the child
    /// after an open (D-109). Call it at the end of the open, after the crossfade.
    func giveParentImage(to child: RenderEngine) {
        precondition(child !== self, "A parent gives its image to another engine")
        let box = core.withLock { parent -> ParentImageBox? in
            guard let frozen = parent.transition?.frozen else { return nil }
            parent.transition?.frozen = nil
            return ParentImageBox(image: frozen)
        }
        guard let box else { return }
        child.core.withLock { renderer in renderer.parentImage = box.image }
    }
}
