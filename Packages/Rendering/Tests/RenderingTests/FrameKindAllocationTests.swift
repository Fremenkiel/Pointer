import Geometry
import Metal
import Model
import QuartzCore
import XCTest

@testable import Rendering

/// The heap allocations of the frames that do more than a pan: a frame that shows a handoff, a
/// frame of an eraser gesture, and a frame that redraws an area after an erase (review M9
/// section 3.4, item 9, m10-plan.md task 3.7). The changes go to the inbox before each count, so
/// the count holds the frame only. The Metal work does not count (D-43), so `AllocationTracer`
/// counts each allocation by its caller. A frame of each kind makes no more Pointer allocations
/// than a pan frame, except two in a handoff frame: the block of the presented handler, and one
/// in `InkEncoder.appendEntries` for the new stroke. Before task 3.6, the presented handler made
/// two, a closure context and its block.
@MainActor
final class FrameKindAllocationTests: XCTestCase {
    /// The measured frames of each kind.
    private static let frames = 20

    private struct Rig {
        let renderer: CanvasRenderer
        let layer: CAMetalLayer
    }

    private func rig() throws -> Rig {
        let renderer = try CanvasRenderer()
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(width: 800, height: 600)
        renderer.setViewport(viewSize: Size(width: 400, height: 300), displayScale: 2)
        renderer.camera = Camera(center: Point(x: -2_900, y: -1_400), zoom: 1)
        renderer.load(PerformanceContent.dense(count: 200, points: 300))
        for _ in 0..<100 {
            guard renderer.renderFrame(into: layer, deadline: nil) else { break }
        }
        return Rig(renderer: renderer, layer: layer)
    }

    /// The median counts of a kind of frame, and the callers of the Pointer allocations of one
    /// frame with the median count.
    private struct Counts {
        let pointer: Int
        let system: Int
        let callers: [String]
    }

    /// Returns the median Pointer and system allocations of a frame after `prepare` of each step.
    private func medianCount(_ rig: Rig, prepare: (Int) -> Void) throws -> Counts {
        var results: [AllocationTracer.Result] = []
        for step in 0..<Self.frames {
            prepare(step)
            let drawable = try XCTUnwrap(rig.layer.nextDrawable())
            let size = rig.layer.drawableSize
            let result = AllocationTracer.trace {
                _ = rig.renderer.engine.renderFrame(
                    drawableSize: size,
                    deadline: nil,
                    drawable: .drawable(drawable)
                )
            }
            results.append(try XCTUnwrap(result))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        XCTAssertEqual(results.map(\.unrecorded).max(), 0, "Each allocation has its caller")
        let median = { (values: [Int]) in values.sorted()[values.count / 2] }
        let pointer = median(results.map(\.pointer))
        let typical = results.first { $0.pointer == pointer }
        return Counts(
            pointer: pointer,
            system: median(results.map(\.system)),
            callers: typical?.pointerCallers ?? []
        )
    }

    private func check(_ kind: String, median: Counts, pan: Counts, extra: Int = 0) {
        let line =
            "\(kind) frame allocations p50: Pointer \(median.pointer), system \(median.system);"
            + " pan frame: Pointer \(pan.pointer), system \(pan.system)"
        XCTContext.runActivity(named: line) { _ in }
        XCTContext.runActivity(named: "\(kind) callers: \(median.callers)") { _ in }
        XCTContext.runActivity(named: "pan callers: \(pan.callers)") { _ in }
        XCTAssertLessThanOrEqual(median.pointer, pan.pointer + extra, "\(line); \(median.callers)")
    }

    private func panCount(_ rig: Rig) throws -> Counts {
        try medianCount(rig) { step in
            rig.renderer.camera = Camera(
                center: Point(x: -2_900 + Double(step % 2), y: -1_400),
                zoom: 1
            )
        }
    }

    func testHandoffFrame() throws {
        let rig = try rig()
        let pan = try panCount(rig)
        let median = try medianCount(rig) { step in
            let x = -2_950 + Double(step) * 5
            let points = [Point(x: x, y: -1_420), Point(x: x + 3, y: -1_380)]
            rig.renderer.add([StrokeBuilder.stroke(points, seed: 10_000 + step)]) {}
        }
        check("handoff", median: median, pan: pan, extra: 2)
    }

    func testEraserFrame() throws {
        let rig = try rig()
        let pan = try panCount(rig)
        rig.renderer.setEraserReady(true)
        rig.renderer.beginErase(radius: 8)
        // The first frames make the mask texture, which is not a frame of a gesture.
        for step in 0..<3 {
            rig.renderer.addEraserSample(Point(x: 50 + Double(step) * 4, y: 150))
            _ = rig.renderer.renderFrame(into: rig.layer, deadline: nil)
        }
        let median = try medianCount(rig) { step in
            rig.renderer.addEraserSample(Point(x: 100 + Double(step) * 4, y: 150))
        }
        rig.renderer.endErase()
        check("eraser", median: median, pan: pan)
    }

    func testRedrawFrame() throws {
        let rig = try rig()
        let pan = try panCount(rig)
        let strokes = PerformanceContent.dense(count: 200, points: 300)
        let median = try medianCount(rig) { step in
            let stroke = strokes[step]
            let area = stroke.bounds.expanded(by: 4)
            rig.renderer.change(removing: [stroke.id], adding: [], area: area) {}
        }
        check("redraw", median: median, pan: pan, extra: 2)
    }
}
