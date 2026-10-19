import Geometry
import Model
import Testing

@testable import InkEngine

@Suite("Erase timing (D-69)")
struct EraseTimingTests {
    /// The strokes of M4 acceptance 2: 1,000 parallel strokes of 300 points.
    static let strokeCount = 1_000
    static let pointsPerStroke = 300
    /// The budget of one step of M4 acceptance 2.
    static let budget = Duration.milliseconds(16)

    @Test("Apply and revert of an erase of 1,000 strokes cut in two take under 16 ms each")
    func applyAndRevert() throws {
        var factory = InkFixtures.factory()
        var content = CanvasContent(canvasID: InkFixtures.canvas)
        let strokes = (0..<Self.strokeCount).map { row in
            InkFixtures.line(
                from: 0,
                to: Double(Self.pointsPerStroke - 1) * 2,
                y: Double(row) * 6,
                factory: &factory
            )
        }
        for stroke in strokes {
            try content.add(stroke)
        }
        let path = EraserPath(
            samples: (0...Self.strokeCount * 2).map { Point(x: 300, y: Double($0) * 3 - 3) },
            radius: 4
        )
        let clock = ContinuousClock()
        let erase = try #require(
            Eraser.command(erasing: strokes, along: path, factory: &factory)
        )
        #expect(erase.removed.count == Self.strokeCount)
        #expect(erase.parts.count == 2 * Self.strokeCount)
        var history = History()
        let apply = try clock.measure {
            _ = try history.perform(erase, on: &content, clock: &factory.clock)
        }
        let revert = try clock.measure {
            _ = try history.undo(on: &content, clock: &factory.clock)
        }
        let redo = try clock.measure {
            _ = try history.redo(on: &content, clock: &factory.clock)
        }
        #expect(content.strokes.count == 2 * Self.strokeCount)
        #expect(apply < Self.budget, "apply \(apply)")
        #expect(revert < Self.budget, "revert \(revert)")
        #expect(redo < Self.budget, "redo \(redo)")
    }
}
