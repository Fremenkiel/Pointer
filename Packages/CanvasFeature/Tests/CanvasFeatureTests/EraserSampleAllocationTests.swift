import Geometry
import Model
import QuartzCore
import UIKit
import XCTest

@testable import CanvasFeature
@testable import Rendering

/// A gesture of `EraserPath.maxSamples` samples allocates nothing in Pointer code after its first
/// sample (PERF-01, M-07 of the M4 fix plan). Both paths run on the main thread here, so the
/// counts take the main thread only: in a full run, other tests run on other threads at the same
/// time.
@MainActor
final class EraserSampleAllocationTests: XCTestCase {
    /// The samples between two frames, fewer than the 64 that the inbox holds per frame.
    private static let samplesPerFrame = 16
    /// The wait after a frame, so that the GPU and its handlers on other threads are done before
    /// the next count: the counter sees every thread, and Metal allocations do not count (D-43).
    private static let frameSettle: TimeInterval = 0.005

    func testCanvasSamplesMakeNoAllocation() throws {
        let rig = try Rig()
        let (canvas, renderer, layer) = (rig.canvas, rig.renderer, rig.layer)
        canvas.select(.eraser)
        canvas.pencilBegan()
        canvas.pencilMoved(to: Point(x: 0, y: 0))
        renderer.renderFrame(into: layer, deadline: nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: Self.frameSettle))
        var total = 0
        var batches: [Int] = []
        var sample = 1
        while sample < EraserTool.sampleCapacity {
            let batch = sample..<min(sample + Self.samplesPerFrame, EraserTool.sampleCapacity)
            let count = try XCTUnwrap(
                AllocationCounter.countMainThread {
                    for index in batch { canvas.pencilMoved(to: Self.point(index)) }
                }
            )
            total += count
            if count > 0 { batches.append(sample) }
            sample += Self.samplesPerFrame
            renderer.renderFrame(into: layer, deadline: nil)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: Self.frameSettle))
        }
        XCTAssertEqual(canvas.eraserSamples?.count, EraserTool.sampleCapacity)
        XCTAssertEqual(
            total,
            0,
            "\(total) allocations after the first sample, in the batches at \(batches)"
        )
        canvas.pencilEnded(at: 0, isCancelled: true)
    }

    func testMaskSamplesMakeNoAllocation() throws {
        var mask = EraserMask()
        mask.begin(radius: 8)
        mask.append(Self.point(0))
        let count = try XCTUnwrap(
            AllocationCounter.countMainThread {
                for index in 1..<EraserMask.maxSamples {
                    mask.append(Self.point(index))
                }
            }
        )
        XCTAssertEqual(count, 0, "The mask samples made \(count) allocations")
    }

    /// A canvas of 400 x 300 points with a layer for the frames of its renderer.
    @MainActor
    private struct Rig {
        let canvas: CanvasViewController
        let renderer: CanvasRenderer
        let layer = CAMetalLayer()

        init() throws {
            renderer = try CanvasRenderer()
            renderer.configure(layer)
            layer.drawableSize = CGSize(width: 800, height: 600)
            renderer.setViewport(viewSize: Size(width: 400, height: 300), displayScale: 2)
            canvas = CanvasViewController(
                dependencies: CanvasDependencies(
                    renderer: renderer,
                    clock: Fixtures.clock(),
                    content: CanvasContent(canvasID: Fixtures.canvas)
                )
            )
            canvas.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
            canvas.view.layoutIfNeeded()
        }
    }

    /// A sample of a long gesture inside a 400 x 300 view.
    private static func point(_ index: Int) -> Point {
        Point(x: Double(index % 400), y: Double((index / 400) % 300))
    }
}
