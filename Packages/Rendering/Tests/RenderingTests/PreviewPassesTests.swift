import Foundation
import Geometry
import Model
import Testing

@testable import Rendering

/// The split of the strokes of an offscreen preview into passes under the arena budget (task
/// 1.6 of docs/m9-plan.md, D-157).
@Suite("Passes of an offscreen preview")
struct PreviewPassesTests {
    @Test("No stroke gives one empty pass, which clears the target")
    func noStroke() {
        let passes = PreviewPasses.split([], byteBudget: PreviewPasses.minimumByteBudget)
        #expect(passes.count == 1 && passes[0].isEmpty)
    }

    @Test("Strokes that fit the budget draw in one pass, in their order")
    func onePass() {
        let strokes = (0..<3).map { Self.stroke(points: 300, x: Double($0)) }
        let passes = PreviewPasses.split(strokes, byteBudget: 32 << 20)
        #expect(passes.map { $0.map(\.id) } == [strokes.map(\.id)])
    }

    @Test(
        "At the smallest budget, each stroke of the point limit takes a pass of its own",
        arguments: [1, 2, 3]
    )
    func longStrokes(count: Int) {
        let strokes = (0..<count).map {
            Self.stroke(points: Limits.maxPointsPerStroke, x: Double($0))
        }
        let passes = PreviewPasses.split(strokes, byteBudget: PreviewPasses.minimumByteBudget)
        #expect(passes.count == count)
        #expect(passes.allSatisfy { $0.count == 1 })
    }

    @Test("Each pass keeps the budget")
    func budgetHolds() {
        // The smallest budget leaves room for 2 slabs beside the size classes: 16,384 points.
        let budget = PreviewPasses.minimumByteBudget
        let strokes = (0..<100).map { Self.stroke(points: 2_000 + $0 * 10, x: Double($0)) }
        let passes = PreviewPasses.split(strokes, byteBudget: budget)
        #expect(passes.count > 1)
        for pass in passes {
            let points = pass.reduce(0) { $0 + $1.points.count }
            #expect(PreviewPasses.arenaBytes(points: points) <= budget)
        }
        #expect(passes.joined().map(\.id) == strokes.map(\.id))
    }

    private static func stroke(points: Int, x: Double) -> Stroke {
        Stroke(
            id: StrokeID(rawValue: UUID()),
            canvasID: CanvasID(rawValue: UUID()),
            created: HybridTimestamp(wallMillis: 1, counter: 0, device: DeviceID(rawValue: UUID())),
            origin: Point(x: x, y: 0),
            width: 2,
            points: InkPoints(
                (0..<points).map { InkPoint(x: Float($0), y: 0, force: 1, time: 0) }
            )
        )
    }
}
