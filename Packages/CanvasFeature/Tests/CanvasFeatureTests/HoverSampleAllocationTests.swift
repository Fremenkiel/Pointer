import Geometry
import Model
import QuartzCore
import UIKit
import XCTest

@testable import CanvasFeature
@testable import Rendering

/// A hover sample allocates nothing in Pointer code (PERF-01, the M7 plan task 2.3). The work of
/// Core Animation does not count, as the Metal work does not count (D-43), so the test subtracts
/// the count of a bare layer move with the same samples. The samples run on the main thread, so
/// the counts take the main thread only.
@MainActor
final class HoverSampleAllocationTests: XCTestCase {
    /// The hover samples between two turns of the run loop, about the samples of one frame.
    private static let samplesPerTurn = 16
    /// The hover samples of the test: a hover of about 4 s at 240 Hz.
    private static let sampleCount = 1_024

    func testPenSamplesMakeNoAllocation() throws {
        try checkSamples(tool: .pen)
    }

    func testEraserSamplesMakeNoAllocation() throws {
        try checkSamples(tool: .eraser)
    }

    /// Counts the hover samples of `tool` and the bare moves, and compares them.
    private func checkSamples(tool: Tool) throws {
        let canvas = try Self.makeCanvas()
        canvas.select(tool)
        canvas.hoverBegan(at: Self.point(0), isPreviewOn: true)
        let hover = try countBatches { canvas.hoverMoved(to: Self.point($0)) }
        XCTAssertNotNil(canvas.canvasView.hoverDot.shownCenter)
        XCTAssertEqual(canvas.canvasView.hoverDot.showsRing, tool == .eraser)
        let bare = Self.bareLayer(isRing: tool == .eraser, on: canvas.canvasView.layer)
        bare.position = Self.point(0)
        let bareCount = try countBatches { index in
            bare.position = Self.point(index)
            bare.isHidden = false
        }
        let summary = "hover \(hover.total) in \(hover.batches), bare move \(bareCount.total)"
        XCTContext.runActivity(named: summary) { _ in }
        XCTAssertLessThanOrEqual(
            hover.total - bareCount.total,
            0,
            "Pointer code allocated at a hover sample: \(summary)"
        )
    }

    /// Runs `sample` for each sample in batches, with a turn of the run loop after each batch,
    /// so that Core Animation commits as in the app. Returns the total count and the batches
    /// with allocations.
    private func countBatches(
        _ sample: (Int) -> Void
    ) throws -> (total: Int, batches: [Int]) {
        var total = 0
        var batches: [Int] = []
        var start = 1
        while start < Self.sampleCount {
            let batch = start..<min(start + Self.samplesPerTurn, Self.sampleCount)
            let count = try XCTUnwrap(
                AllocationCounter.countMainThread {
                    for index in batch { sample(index) }
                }
            )
            total += count
            if count > 0 { batches.append(start) }
            start += Self.samplesPerTurn
            CATransaction.flush()
        }
        return (total, batches)
    }

    /// A shown canvas of 400 x 300 points.
    private static func makeCanvas() throws -> CanvasViewController {
        let canvas = CanvasViewController(
            dependencies: CanvasDependencies(
                renderer: try CanvasRenderer(),
                clock: Fixtures.clock(),
                content: CanvasContent(canvasID: Fixtures.canvas)
            )
        )
        canvas.isShownCanvas = true
        canvas.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        canvas.view.layoutIfNeeded()
        return canvas
    }

    /// A shape layer as the hover dot sets it up, on the same superlayer, without Pointer code
    /// in its moves.
    private static func bareLayer(isRing: Bool, on superlayer: CALayer) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = CGPath(ellipseIn: CGRect(x: -8, y: -8, width: 16, height: 16), transform: nil)
        layer.fillColor = isRing ? nil : UIColor.gray.cgColor
        layer.strokeColor = isRing ? UIColor.gray.cgColor : nil
        layer.actions = ["position": NSNull(), "hidden": NSNull()]
        superlayer.addSublayer(layer)
        return layer
    }

    /// A hover sample inside a 400 x 300 view.
    private static func point(_ index: Int) -> CGPoint {
        CGPoint(x: Double(index % 400), y: Double((index / 4) % 300))
    }
}
