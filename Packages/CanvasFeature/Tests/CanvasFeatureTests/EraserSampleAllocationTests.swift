import Geometry
import Model
import QuartzCore
import UIKit
import XCTest

@testable import CanvasFeature
@testable import Rendering

/// A gesture of `EraserPath.maxSamples` samples allocates nothing in Pointer code (PERF-01, M-07
/// of the M4 fix plan). The first gesture of the process reserves the sample list (M-07) and
/// shows the eraser ring (D-202). The first setters on the shown ring layer grow the method cache
/// of its class once, in the Objective-C runtime, as a backtrace of a count showed on 2026-11-02.
/// So the count takes the second gesture, which reuses the list and the ring. Both paths run on
/// the main thread here, so the counts take the main thread only: in a full run, other tests run
/// on other threads at the same time.
@MainActor
final class EraserSampleAllocationTests: XCTestCase {
    /// The samples between two frames, fewer than the 64 that the inbox holds per frame.
    private static let samplesPerFrame = 16
    /// The wait after a frame, so that the GPU and its handlers on other threads are done before
    /// the next count: the counter sees every thread, and Metal allocations do not count (D-43).
    private static let frameSettle: TimeInterval = 0.005

    func testCanvasSamplesMakeNoAllocation() throws {
        let rig = try Rig()
        let canvas = rig.canvas
        canvas.select(.eraser)
        canvas.pencilBegan()
        for start in stride(from: 0, to: EraserTool.sampleCapacity, by: Self.samplesPerFrame) {
            rig.feed(Self.batch(from: start))
        }
        canvas.pencilEnded(at: 0, isCancelled: true)
        rig.render()
        canvas.pencilBegan()
        rig.feed(Self.batch(from: 0))
        var total = 0
        var batches: [Int] = []
        var sample = Self.samplesPerFrame
        while sample < EraserTool.sampleCapacity {
            let batch = Self.batch(from: sample)
            let count = try XCTUnwrap(
                AllocationCounter.countMainThread {
                    for index in batch { canvas.pencilMoved(to: Self.point(index)) }
                }
            )
            total += count
            if count > 0 { batches.append(sample) }
            sample += Self.samplesPerFrame
            rig.render()
        }
        XCTAssertEqual(canvas.eraserSamples?.count, EraserTool.sampleCapacity)
        XCTAssertEqual(total, 0, "\(total) allocations in the batches at \(batches)")
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

    /// The samples of one frame from `start`, bounded by the capacity.
    private static func batch(from start: Int) -> Range<Int> {
        start..<min(start + samplesPerFrame, EraserTool.sampleCapacity)
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

        /// Gives the samples of `batch` to the canvas, then renders a frame.
        func feed(_ batch: Range<Int>) {
            for index in batch { canvas.pencilMoved(to: point(index)) }
            render()
        }

        /// Renders a frame and lets the GPU and its handlers settle.
        func render() {
            renderer.renderFrame(into: layer, deadline: nil)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: frameSettle))
        }
    }

    /// A sample of a long gesture inside a 400 x 300 view.
    private static func point(_ index: Int) -> Point {
        Point(x: Double(index % 400), y: Double((index / 400) % 300))
    }
}
