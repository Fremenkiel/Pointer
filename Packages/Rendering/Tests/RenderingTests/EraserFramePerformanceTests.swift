import Geometry
import Metal
import Model
import QuartzCore
import Synchronization
import XCTest

@testable import Rendering

/// Collects the GPU time of each frame.
private final class GPUTimes: FrameObserving {
    let values = Mutex<[Double]>([])

    func measure(_ work: () -> Void) { work() }

    func willCommit(_ commandBuffer: any MTLCommandBuffer, drawable: any CAMetalDrawable) {
        commandBuffer.whenCompleted { [self] buffer in
            let milliseconds = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
            values.withLock { $0.append(milliseconds) }
        }
    }

    func didRender(_ record: FrameRecord) {}
}

/// A frame of the eraser with 4 new samples against the frame budget of architecture.md
/// section 12: under 3 ms CPU and under 4 ms GPU (M4 task 3.4). Only a device gives drawables at
/// the frame rate and real GPU times, so it runs on the iPad only (D-77).
@MainActor
final class EraserFramePerformanceTests: XCTestCase {
    private static let frames = 60
    private static let samplesPerFrame = 4

    /// A renderer on the screen size of the iPad Pro 11-inch (M4), with the 20,000 strokes of the
    /// M2 content drawn.
    private func makeRenderer() throws -> (CanvasRenderer, CAMetalLayer) {
        let renderer = try CanvasRenderer()
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(width: 2420, height: 1668)
        renderer.setViewport(viewSize: Size(width: 1210, height: 834), displayScale: 2)
        renderer.load(PerformanceContent.dense(count: 20_000, points: 300))
        // The eraser is the tool before the gesture, as after a pick in the palette (D-78).
        renderer.setEraserReady(true)
        for _ in 0..<200 where renderer.renderFrame(into: layer, deadline: nil) {}
        return (renderer, layer)
    }

    func testEraserFrameWithFourSamples() throws {
        let (renderer, layer) = try makeRenderer()
        renderer.beginErase(radius: 8)
        let times = GPUTimes()
        renderer.engine.post { $0.observer = times }
        var cpu: [Double] = []
        for frame in 0..<Self.frames {
            let drawable = try XCTUnwrap(layer.nextDrawable())
            for sample in 0..<Self.samplesPerFrame {
                let x = 100 + Double(frame * Self.samplesPerFrame + sample) * 3
                renderer.addEraserSample(Point(x: x, y: 400))
            }
            let start = CACurrentMediaTime()
            _ = renderer.engine.renderFrame(
                drawableSize: layer.drawableSize,
                deadline: nil,
                drawable: .drawable(drawable)
            )
            cpu.append((CACurrentMediaTime() - start) * 1000)
            Thread.sleep(forTimeInterval: 1.0 / 120)
        }
        renderer.engine.post { $0.observer = nil }
        Thread.sleep(forTimeInterval: 0.2)
        let gpu = times.values.withLock { $0 }
        let median = { (values: [Double]) in values.sorted()[values.count / 2] }
        let line = String(
            format: "eraser frame CPU p50 %.2f ms, max %.2f ms, GPU p50 %.2f ms, max %.2f ms",
            median(cpu),
            cpu.max() ?? 0,
            median(gpu),
            gpu.max() ?? 0
        )
        let samples = ["cpu.p50.ms": median(cpu), "gpu.p50.ms": median(gpu)]
        PerformanceRecord.attach(samples, line: line)
        XCTAssertLessThan(median(cpu), 3, line)
        XCTAssertLessThan(median(gpu), 4, line)
    }
}
