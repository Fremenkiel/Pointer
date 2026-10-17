import Geometry
import Metal
import QuartzCore

/// Watches the frames of the render thread. Only the performance tests use it (PERF-03).
protocol FrameObserving: Sendable {
    /// Runs the work of one frame. An observer can count the allocations of the work.
    func measure(_ work: () -> Void)
    /// Gets the command buffer and the drawable of a frame before the commit.
    func willCommit(_ commandBuffer: any MTLCommandBuffer, drawable: any CAMetalDrawable)
    /// Gets the record of a frame after the commit.
    func didRender(_ record: FrameRecord)
}
