import Metal

/// The values that every pass of one frame shares (the M2 fix plan, phase 6, task 3).
struct FrameContext {
    /// The command buffer of the frame.
    let commandBuffer: any MTLCommandBuffer
    /// The number of the frame, for the least-recently-drawn order of the arena.
    let frame: UInt64
}
