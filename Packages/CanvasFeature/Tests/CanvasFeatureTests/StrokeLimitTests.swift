import Foundation
import Geometry
import Model
import PencilKit
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

/// The canvas at its stroke limits (D-181, m10-plan.md task 6.2). Before M10, the pen at the
/// limit dropped the stroke with a log line only.
@MainActor
@Suite("Stroke limit")
struct StrokeLimitTests {
    /// The messages of a canvas.
    final class Shown {
        var messages: [String] = []
    }

    private static func controller(
        content: CanvasContent,
        shown: Shown
    ) throws -> CanvasViewController {
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: content
        )
        dependencies.onMessage = { shown.messages.append($0) }
        let controller = CanvasViewController(dependencies: dependencies)
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        controller.view.layoutIfNeeded()
        return controller
    }

    /// Hands a live stroke of the pencil to the canvas, as PencilKit does at the lift.
    private static func draw(_ controller: CanvasViewController) {
        let live = controller.canvasView.liveCanvas
        var drawing = live.drawing
        drawing.strokes.append(Fixtures.pencilKitStroke(Fixtures.wave(), pointSize: 3))
        live.drawing = drawing
        controller.canvasViewDrawingDidChange(live)
    }

    /// Content of `count` strokes of 2 points far from the view, and `extra` strokes first.
    private static func content(count: Int, extra: [Stroke] = []) throws -> CanvasContent {
        let clock = Fixtures.clock()
        var content = CanvasContent(canvasID: Fixtures.canvas)
        for stroke in extra {
            try content.add(stroke, limit: Limits.maxStrokesAfterErase)
        }
        let points = InkPoints([
            InkPoint(x: 0, y: 0, force: 1, time: 0), InkPoint(x: 1, y: 0, force: 1, time: 0),
        ])
        for index in extra.count..<count {
            let stroke = Stroke(
                id: StrokeID(rawValue: UUID()),
                canvasID: Fixtures.canvas,
                created: clock.now(),
                origin: Point(x: 10_000 + Double(index % 500) * 4, y: Double(index / 500) * 4),
                width: 2,
                points: points
            )
            try content.add(stroke, limit: Limits.maxStrokesAfterErase)
        }
        return content
    }

    @Test("The pen at the stroke limit shows the message once per pencil down")
    func penAtLimit() throws {
        let shown = Shown()
        let controller = try Self.controller(
            content: try Self.content(count: Limits.maxStrokesPerCanvas),
            shown: shown
        )
        controller.pencilBegan()
        Self.draw(controller)
        Self.draw(controller)
        #expect(shown.messages == [CanvasStrings.strokeLimit])
        controller.pencilBegan()
        Self.draw(controller)
        #expect(shown.messages == [CanvasStrings.strokeLimit, CanvasStrings.strokeLimit])
        #expect(controller.content.strokes.count == Limits.maxStrokesPerCanvas)
    }

    @Test("An erase past the bound after an erase removes the strokes whole, with no message")
    func eraseAtBound() throws {
        // A line through the canvas origin, which the eraser would cut in two.
        let line = Stroke(
            id: StrokeID(rawValue: UUID()),
            canvasID: Fixtures.canvas,
            created: Fixtures.clock().now(),
            origin: Point(x: -50, y: 0),
            width: 2,
            points: InkPoints((0...50).map { InkPoint(x: Float($0) * 2, y: 0, force: 1, time: 0) })
        )
        // Strokes far from the eraser fill the canvas to the bound after an erase (D-73).
        let content = try Self.content(count: Limits.maxStrokesAfterErase, extra: [line])
        let shown = Shown()
        let controller = try Self.controller(content: content, shown: shown)
        controller.select(.eraser)
        controller.pencilBegan()
        for step in 0...10 {
            controller.pencilMoved(to: Point(x: 200, y: 130 + Double(step) * 4))
        }
        controller.pencilEnded(at: 0, isCancelled: false)
        #expect(controller.content.strokes[line.id] == nil, "The line is erased")
        #expect(controller.content.strokes.count == Limits.maxStrokesAfterErase - 1, "No parts")
        #expect(shown.messages.isEmpty)
    }
}
