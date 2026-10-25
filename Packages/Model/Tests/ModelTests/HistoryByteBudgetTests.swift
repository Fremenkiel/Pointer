import Foundation
import Testing

@testable import Model

/// The byte budget of a history with strokes of 2 points (D-183). A budget of 4,000,000 points
/// held 452 MB of such strokes, by the measure of D-183: 226 bytes per stroke.
@Suite("History byte budget")
struct HistoryByteBudgetTests {
    /// A step that holds strokes and changes no content, so the test can hold more strokes
    /// than a canvas holds live.
    private struct HeldStrokes: CanvasCommand {
        let strokes: [Stroke]
        var heldByteCount: Int {
            strokes.reduce(0) { $0 + HistoryCost.bytes(ofStroke: $1.points.count) }
        }

        func forEachHeldStroke(_ body: (StrokeID) -> Void) {
            for stroke in strokes { body(stroke.id) }
        }

        func apply(
            to content: inout CanvasContent,
            clock: inout HybridClock
        ) throws(CommandError) -> [LibraryChange] { [] }

        func revert(
            on content: inout CanvasContent,
            clock: inout HybridClock
        ) throws(CommandError) -> [LibraryChange] { [] }
    }

    @Test("Steps of strokes of 2 points keep the measured bytes inside the budget")
    func strokesOfTwoPoints() throws {
        var rig = CommandRig()
        var history = History()
        // The strokes share their points, so the test holds them once (data-model.md 7.4).
        let points = InkPoints([
            InkPoint(x: 0, y: 0, force: 1, time: 0), InkPoint(x: 1, y: 0, force: 1, time: 0),
        ])
        for _ in 0..<Limits.maxHistoryDepth {
            let strokes = (0..<4_000).map { _ in
                Stroke(
                    id: StrokeID(rawValue: UUID()),
                    canvasID: rig.content.canvasID,
                    created: rig.factory.clock.now(),
                    origin: .zero,
                    width: 2,
                    points: points
                )
            }
            _ = try history.perform(
                HeldStrokes(strokes: strokes),
                on: &rig.content,
                clock: &rig.factory.clock
            )
        }
        var held = 0
        for step in history.undoSteps {
            step.forEachHeldStroke { _ in held += 1 }
        }
        // The measure of D-183: 226 bytes for each stroke of 2 points.
        let measured = held * 226
        #expect(measured <= Limits.maxHistoryBytesPerCanvas, "\(held) strokes, \(measured) bytes")
    }
}
