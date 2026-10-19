import Foundation
import Geometry
import Model
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

@MainActor
@Suite("Eraser tool")
struct EraserToolTests {
    /// A view of 400 x 300 points at the standard camera, so view (200, 150) is canvas (0, 0).
    private func makeController(
        strokes: [Stroke],
        library: RecordingLibrary
    ) throws -> CanvasViewController {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        for stroke in strokes {
            try content.add(stroke)
        }
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: content
        )
        dependencies.repository = library
        let controller = CanvasViewController(dependencies: dependencies)
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        controller.view.layoutIfNeeded()
        return controller
    }

    /// A horizontal line through the canvas origin.
    private static func line(clock: AppClock) -> Stroke {
        let points = (0...50).map { InkPoint(x: Float($0) * 2, y: 0, force: 1, time: 0) }
        return Stroke(
            id: StrokeID(rawValue: UUID()),
            canvasID: Fixtures.canvas,
            created: clock.now(),
            origin: Point(x: -50, y: 0),
            width: 2,
            points: InkPoints(points)
        )
    }

    /// Runs one eraser gesture from top to bottom through view x = 200.
    private func erase(_ controller: CanvasViewController, isCancelled: Bool = false) {
        controller.pencilBegan()
        for step in 0...10 {
            controller.pencilMoved(to: Point(x: 200, y: 130 + Double(step) * 4))
        }
        controller.pencilEnded(at: 0, isCancelled: isCancelled)
    }

    @Test("An erase across a stroke cuts it in two and sends the rows with a save request")
    func cut() async throws {
        let library = RecordingLibrary()
        let line = Self.line(clock: Fixtures.clock())
        let controller = try makeController(strokes: [line], library: library)
        controller.select(.eraser)
        erase(controller)
        #expect(controller.content.strokes[line.id] == nil)
        #expect(controller.content.strokes.count == 2)
        #expect(controller.content.erased[line.id]?.isDeleted == false)
        #expect(controller.history.canUndo)
        for _ in 0..<100 where await library.saveRequests == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        let rows = await library.rows
        #expect(rows.filter { if case .stroke = $0 { true } else { false } }.count == 2)
        #expect(rows.filter { if case .erase = $0 { true } else { false } }.count == 1)
        #expect(await library.saveRequests == 1)
    }

    @Test("The first sample after a tool change cuts the stroke under it (D-34, D-70)")
    func firstSample() throws {
        let line = Self.line(clock: Fixtures.clock())
        let controller = try makeController(strokes: [line], library: RecordingLibrary())
        controller.select(.eraser)
        controller.pencilBegan()
        controller.pencilMoved(to: Point(x: 200, y: 150))
        controller.pencilEnded(at: 0, isCancelled: false)
        #expect(controller.content.strokes[line.id] == nil)
        #expect(controller.content.strokes.count == 2)
    }

    @Test("A cancelled gesture, a pen touch, and a library that cannot save erase nothing")
    func noErase() throws {
        let line = Self.line(clock: Fixtures.clock())
        let controller = try makeController(strokes: [line], library: RecordingLibrary())
        controller.select(.eraser)
        erase(controller, isCancelled: true)
        controller.select(.pen)
        erase(controller)
        controller.select(.eraser)
        controller.isEditingEnabled = false
        erase(controller)
        #expect(controller.content.strokes.count == 1)
        #expect(!controller.history.canUndo)
    }

    @Test("The drawing gesture of PencilKit follows the tool and the editing flag (D-70)")
    func drawingGesture() throws {
        let controller = try makeController(strokes: [], library: RecordingLibrary())
        let recognizer = controller.canvasView.liveCanvas.drawingGestureRecognizer
        #expect(recognizer.isEnabled)
        controller.pencilBegan()
        controller.select(.eraser)
        #expect(recognizer.isEnabled)
        #expect(controller.tool == .eraser)
        controller.pencilEnded(at: 0, isCancelled: false)
        #expect(!recognizer.isEnabled)
        controller.select(.pen)
        controller.isEditingEnabled = false
        #expect(!recognizer.isEnabled)
        #expect(!controller.isEditingEnabled)
    }
}
