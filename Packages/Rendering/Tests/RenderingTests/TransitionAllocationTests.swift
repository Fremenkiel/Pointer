import Geometry
import Metal
import Model
import QuartzCore
import XCTest

@testable import Rendering

/// The heap allocations of a frame of an open, against a bare Metal frame (PERF-01, D-43,
/// m6-plan.md task 3.5).
@MainActor
final class TransitionAllocationTests: XCTestCase {
    private static let frames = 60
    private static let completed: @Sendable (any MTLCommandBuffer) -> Void = { _ in }

    /// A renderer of 200 strokes and one card, 10 frames into the open of the card.
    private func openingRenderer() throws -> (CanvasRenderer, CAMetalLayer) {
        let renderer = try CanvasRenderer()
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(width: 800, height: 600)
        renderer.setViewport(viewSize: Size(width: 400, height: 300), displayScale: 2)
        renderer.load(PerformanceContent.dense(count: 200, points: 300))
        let card = try CardStoreTests.card(1, title: "Tree")
        renderer.load([card])
        for _ in 0..<2_000 where renderer.isLoadingCards {
            _ = renderer.renderFrame(into: layer, deadline: nil)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        for _ in 0..<100 where renderer.renderFrame(into: layer, deadline: nil) {}
        renderer.beginOpen(of: card.id)
        for _ in 0..<10 { _ = renderer.renderFrame(into: layer, deadline: nil) }
        return (renderer, layer)
    }

    func testOpenFrameAllocatesNoMoreThanBareMetalFrame() throws {
        let (renderer, layer) = try openingRenderer()
        var ours: [Int] = []
        for step in 0..<Self.frames {
            let progress = Double(step) / Double(Self.frames)
            renderer.camera = Camera(center: .zero, zoom: 1 + progress * 4)
            renderer.setParentWeight(1 - progress)
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
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        let bare = try bareFrames(layer)
        let median = { (values: [Int]) in values.sorted()[values.count / 2] }
        let line = "open frame allocations p50 \(median(ours)), bare frame p50 \(median(bare))"
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertLessThanOrEqual(median(ours), median(bare), line)
    }

    /// A frame of a flight on the render thread (D-121) allocates no more than a bare frame, and
    /// the flight ends exactly at its target with the parent weight 0.
    func testFlightFrameAllocatesNoMoreThanBareMetalFrame() throws {
        let (renderer, layer) = try openingRenderer()
        let target = Camera(center: Point(x: 10, y: 5), zoom: 5)
        let flight = CameraFlight(from: renderer.camera, to: target, duration: 1, start: 0)
        renderer.fly(RenderFlight(flight: flight, effect: .open, fixedZoom: nil))
        var ours: [Int] = []
        for step in 0..<Self.frames {
            let drawable = try XCTUnwrap(layer.nextDrawable())
            let size = layer.drawableSize
            let time = Double(step) / Double(Self.frames)
            let count = AllocationCounter.count {
                _ = renderer.engine.renderFrame(
                    drawableSize: size,
                    deadline: time,
                    drawable: .drawable(drawable)
                )
            }
            if let count { ours.append(count) }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        _ = renderer.renderFrame(into: layer, deadline: 2)
        let end = renderer.engine.withRenderer { ($0.camera, $0.transition?.parentWeight) }
        XCTAssertEqual(end.0, target)
        XCTAssertEqual(end.1, 0)
        let bare = try bareFrames(layer)
        let median = { (values: [Int]) in values.sorted()[values.count / 2] }
        let line = "flight frame allocations p50 \(median(ours)), bare frame p50 \(median(bare))"
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertLessThanOrEqual(median(ours), median(bare), line)
    }

    /// Frames with one empty pass and one completed handler, as in `FrameAllocationTests`.
    private func bareFrames(_ layer: CAMetalLayer) throws -> [Int] {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let pass = MTLRenderPassDescriptor()
        var bare: [Int] = []
        for _ in 0..<Self.frames {
            let drawable = try XCTUnwrap(layer.nextDrawable())
            let count = AllocationCounter.count {
                guard let commandBuffer = queue.makeCommandBuffer() else { return }
                commandBuffer.addCompletedHandler(Self.completed)
                pass.colorAttachments[0].texture = drawable.texture
                pass.colorAttachments[0].loadAction = .clear
                guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
                    return
                }
                encoder.endEncoding()
                commandBuffer.present(drawable)
                commandBuffer.commit()
            }
            if let count { bare.append(count) }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        return bare
    }
}
