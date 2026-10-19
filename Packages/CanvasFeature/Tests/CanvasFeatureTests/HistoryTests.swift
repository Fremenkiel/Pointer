import Foundation
import Geometry
import Model
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

@MainActor
@Suite("Undo and redo of the canvas")
struct CanvasHistoryTests {
    /// A view of 400 x 300 points at the standard camera, so view (200, 150) is canvas (0, 0).
    private func makeController(
        content: CanvasContent,
        sessions: CanvasSessions,
        clock: AppClock
    ) throws -> CanvasViewController {
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: clock,
            content: content
        )
        dependencies.sessions = sessions
        let controller = CanvasViewController(dependencies: dependencies)
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        controller.view.layoutIfNeeded()
        return controller
    }

    /// A horizontal pen stroke through the canvas origin.
    private static func line() -> Stroke {
        Stroke(
            id: StrokeID(rawValue: UUID()),
            canvasID: Fixtures.canvas,
            created: HybridTimestamp(wallMillis: 1, counter: 0, device: Fixtures.device),
            origin: Point(x: -50, y: 0),
            width: 2,
            points: InkPoints((0...50).map { InkPoint(x: Float($0) * 2, y: 0, force: 1, time: 0) })
        )
    }

    private func erase(_ controller: CanvasViewController) {
        controller.select(.eraser)
        controller.pencilBegan()
        for step in 0...10 {
            controller.pencilMoved(to: Point(x: 200, y: 130 + Double(step) * 4))
        }
        controller.pencilEnded(at: 0, isCancelled: false)
    }

    @Test("A stroke, an erase, two undo steps, and two redo steps give the expected canvas")
    func strokeEraseUndoRedo() throws {
        let line = Self.line()
        let controller = try makeController(
            content: CanvasContent(canvasID: Fixtures.canvas),
            sessions: CanvasSessions(),
            clock: Fixtures.clock()
        )
        controller.addPenStrokes([line])
        erase(controller)
        let parts = Set(controller.content.strokes.keys)
        #expect(parts.count == 2)
        #expect(controller.historyControls.canUndo)
        #expect(!controller.historyControls.canRedo)
        controller.undo()
        #expect(Set(controller.content.strokes.keys) == [line.id])
        controller.undo()
        #expect(controller.content.strokes.isEmpty)
        #expect(!controller.historyControls.canUndo)
        #expect(controller.historyControls.canRedo)
        controller.redo()
        #expect(Set(controller.content.strokes.keys) == [line.id])
        controller.redo()
        #expect(Set(controller.content.strokes.keys) == parts)
        #expect(!controller.historyControls.canRedo)
        controller.redo()
        #expect(Set(controller.content.strokes.keys) == parts)
    }

    @Test("The history of a canvas stays after a switch to another canvas and back (D-12)")
    func switchKeepsHistory() throws {
        let sessions = CanvasSessions()
        let clock = Fixtures.clock()
        let line = Self.line()
        var loaded = CanvasContent(canvasID: Fixtures.canvas)
        try loaded.add(line)
        let first = try makeController(content: loaded, sessions: sessions, clock: clock)
        erase(first)
        first.willMove(toParent: nil)
        let parts = first.content.strokes
        // A switch makes a new screen. The library loads the live strokes only.
        var reloaded = CanvasContent(canvasID: Fixtures.canvas)
        for stroke in parts.values {
            try reloaded.add(stroke)
        }
        let second = try makeController(content: reloaded, sessions: sessions, clock: clock)
        #expect(second.historyControls.canUndo)
        second.undo()
        #expect(Set(second.content.strokes.keys) == [line.id])
        #expect(second.content.erased[line.id]?.isDeleted == true)
        second.redo()
        #expect(Set(second.content.strokes.keys) == Set(parts.keys))
        #expect(sessions.count == 1)
    }

    @Test("Command-Z and Shift-Command-Z are the key commands of the canvas")
    func keyCommands() throws {
        let controller = try makeController(
            content: CanvasContent(canvasID: Fixtures.canvas),
            sessions: CanvasSessions(),
            clock: Fixtures.clock()
        )
        let commands = try #require(controller.keyCommands)
        #expect(commands.map(\.input) == ["z", "z"])
        #expect(commands.map(\.modifierFlags) == [.command, [.command, .shift]])
        #expect(controller.canBecomeFirstResponder)
    }

    @Test("The sessions drop the least recently used canvas past their capacity")
    func sessionCapacity() {
        let sessions = CanvasSessions()
        let ids = (0...CanvasSessions.capacity).map { _ in CanvasID(rawValue: UUID()) }
        var session = CanvasSession()
        session.erased = [:]
        for id in ids {
            sessions.save(session, for: id)
        }
        #expect(sessions.count == CanvasSessions.capacity)
    }
}
