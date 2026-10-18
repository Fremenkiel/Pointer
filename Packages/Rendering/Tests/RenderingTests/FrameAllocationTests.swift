import Geometry
import Metal
import Model
import QuartzCore
import XCTest

@testable import Rendering

/// The heap allocations of a frame against a bare Metal frame with the same passes (PERF-01,
/// D-43, docs/m2-fix-plan.md, phase 5, task 7). Only a device gives drawables at the frame rate,
/// so the simulator skips the test.
@MainActor
final class FrameAllocationTests: XCTestCase {
    /// The measured frames of each kind.
    private static let frames = 60

    func testFrameAllocatesNoMoreThanBareMetalFrame() throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("The allocation count needs the drawables of a device.")
        #else
            let renderer = try CanvasRenderer()
            let layer = CAMetalLayer()
            renderer.configure(layer)
            layer.drawableSize = CGSize(width: 800, height: 600)
            renderer.setViewport(viewSize: Size(width: 400, height: 300), displayScale: 2)
            renderer.load(PerformanceContent.dense(count: 200, points: 300))
            for _ in 0..<100 where renderer.renderFrame(into: layer, deadline: nil) {}
            var ours: [Int] = []
            for step in 0..<Self.frames {
                // A pan of one point per frame stays inside the margin, so no frame builds.
                renderer.camera = Camera(center: Point(x: Double(step % 2), y: 0), zoom: 1)
                let drawable = try XCTUnwrap(layer.nextDrawable())
                let size = layer.drawableSize
                let count = AllocationCounter.count {
                    _ = renderer.engine.renderFrame(
                        drawableSize: size,
                        deadline: nil,
                        drawable: .drawable(drawable)
                    )
                }
                if let count { ours.append(count) }
                Self.settle()
            }
            let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
            let queue = try XCTUnwrap(device.makeCommandQueue())
            let pass = MTLRenderPassDescriptor()
            var bare: [Int] = []
            for _ in 0..<Self.frames {
                let drawable = try XCTUnwrap(layer.nextDrawable())
                let count = AllocationCounter.count { Self.bareFrame(queue, drawable, pass) }
                if let count { bare.append(count) }
                Self.settle()
            }
            let median = { (values: [Int]) in values.sorted()[values.count / 2] }
            let line = "frame allocations p50 \(median(ours)), bare frame p50 \(median(bare))"
            XCTContext.runActivity(named: line) { _ in }
            XCTAssertLessThanOrEqual(median(ours), median(bare), line)
        #endif
    }

    /// A completed handler that does nothing.
    private static let completed: @Sendable (any MTLCommandBuffer) -> Void = { _ in }

    /// Lets the GPU and the display finish the frame, so that their work is not in the next count.
    private static func settle() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
    }

    /// One command buffer with one render pass on the drawable, as the composite pass has.
    private static func bareFrame(
        _ queue: any MTLCommandQueue,
        _ drawable: any CAMetalDrawable,
        _ pass: MTLRenderPassDescriptor
    ) {
        guard let commandBuffer = queue.makeCommandBuffer() else { return }
        // Each frame needs one completed handler to free its draw list. Metal copies the block
        // of the handler, an allocation inside Metal (D-43), so the bare frame has one too.
        commandBuffer.addCompletedHandler(Self.completed)
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
