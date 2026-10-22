import Foundation
import Geometry
import Model
import Rendering
import SwiftUI
import Testing
import UIKit

@testable import CanvasFeature

@MainActor
@Suite("Undo and redo of the canvas")
struct CanvasHistoryTests {
    /// A view of 400 x 300 points at the standard camera, so view (200, 150) is canvas (0, 0).
    func makeController(
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
    static func line() -> Stroke {
        Stroke(
            id: StrokeID(rawValue: UUID()),
            canvasID: Fixtures.canvas,
            created: HybridTimestamp(wallMillis: 1, counter: 0, device: Fixtures.device),
            origin: Point(x: -50, y: 0),
            width: 2,
            points: InkPoints((0...50).map { InkPoint(x: Float($0) * 2, y: 0, force: 1, time: 0) })
        )
    }

    func erase(_ controller: CanvasViewController) {
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
        // The shown canvas owns its session, so the sessions hold no copy of it (M-03).
        #expect(sessions.count == 0)
        second.willMove(toParent: nil)
        #expect(sessions.count == 1)
    }

    @Test("A switch in the app order keeps the history of the visit (F-02)")
    func switchInAppOrderKeepsHistory() throws {
        let sessions = CanvasSessions()
        let clock = Fixtures.clock()
        let line = Self.line()
        var loaded = CanvasContent(canvasID: Fixtures.canvas)
        try loaded.add(line)
        let first = try makeController(content: loaded, sessions: sessions, clock: clock)
        erase(first)
        // The app ends the session, then builds the next screen before the old one leaves.
        first.endSession()
        let other = try makeController(
            content: CanvasContent(canvasID: Self.otherCanvas),
            sessions: sessions,
            clock: clock
        )
        first.willMove(toParent: nil)
        other.endSession()
        let back = try makeController(
            content: try Self.reload(first),
            sessions: sessions,
            clock: clock
        )
        other.willMove(toParent: nil)
        #expect(back.historyControls.canUndo)
        back.undo()
        #expect(Set(back.content.strokes.keys) == [line.id])
    }

    @Test("A reopen of the shown canvas in the app order keeps the history of the visit (F-02)")
    func reopenKeepsHistory() throws {
        let sessions = CanvasSessions()
        let clock = Fixtures.clock()
        let line = Self.line()
        var loaded = CanvasContent(canvasID: Fixtures.canvas)
        try loaded.add(line)
        let first = try makeController(content: loaded, sessions: sessions, clock: clock)
        erase(first)
        first.endSession()
        let second = try makeController(
            content: try Self.reload(first),
            sessions: sessions,
            clock: clock
        )
        first.willMove(toParent: nil)
        #expect(second.historyControls.canUndo)
        second.undo()
        #expect(Set(second.content.strokes.keys) == [line.id])
        #expect(second.content.erased[line.id]?.isDeleted == true)
    }

    @Test("With the eraser, a pencil touch on the redo button keeps the redo list (F-06)")
    func pencilOnRedoButton() throws {
        let probe = try makeController(
            content: CanvasContent(canvasID: Fixtures.canvas),
            sessions: CanvasSessions(),
            clock: Fixtures.clock()
        )
        let button = try Self.redoButtonCenter(of: probe)
        // A stroke under the redo button, so that an erase there would make a new step.
        let center = Camera(center: .zero, zoom: Limits.standardZoom).canvasPoint(
            fromView: Point(x: button.x, y: button.y),
            viewSize: Size(width: 400, height: 300)
        )
        var loaded = CanvasContent(canvasID: Fixtures.canvas)
        try loaded.add(Self.line(through: center))
        let controller = try makeController(
            content: loaded,
            sessions: CanvasSessions(),
            clock: Fixtures.clock()
        )
        controller.addPenStrokes([Self.line()])
        controller.undo()
        controller.select(.eraser)
        let observer = controller.pencilObserver
        let onButton = controller.view.hitTest(button, with: nil)
        if observer.receivesTouch(in: onButton) {
            controller.pencilBegan()
            controller.pencilMoved(to: Point(x: button.x, y: button.y))
            controller.pencilEnded(at: 0, isCancelled: false)
        }
        #expect(controller.history.redoSteps.count == 1)
        #expect(controller.content.strokes.count == 1)
        let onCanvas = controller.view.hitTest(CGPoint(x: 100, y: 200), with: nil)
        #expect(observer.receivesTouch(in: onCanvas))
    }

    /// Returns the center of the redo button in the coordinates of the canvas view.
    private static func redoButtonCenter(of controller: CanvasViewController) throws -> CGPoint {
        let host = try #require(
            controller.children.first { $0 is UIHostingController<HistoryButtons> }
        )
        controller.view.layoutIfNeeded()
        let bounds = host.view.bounds
        // The redo button is the right one of the two.
        let center = CGPoint(x: bounds.maxX - bounds.height / 2, y: bounds.midY)
        return host.view.convert(center, to: controller.view)
    }

    /// A horizontal stroke of 40 points with its middle at `center`.
    private static func line(through center: Point) -> Stroke {
        Stroke(
            id: StrokeID(rawValue: UUID()),
            canvasID: Fixtures.canvas,
            created: HybridTimestamp(wallMillis: 1, counter: 1, device: Fixtures.device),
            origin: Point(x: center.x - 20, y: center.y),
            width: 2,
            points: InkPoints((0...20).map { InkPoint(x: Float($0) * 2, y: 0, force: 1, time: 0) })
        )
    }

    /// A canvas that is not `Fixtures.canvas`.
    private static let otherCanvas = CanvasID(
        rawValue: UUID(uuid: (3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    )

    /// The content that the library loads for the canvas of `controller`: its live strokes.
    private static func reload(_ controller: CanvasViewController) throws -> CanvasContent {
        var content = CanvasContent(canvasID: controller.canvasID)
        for stroke in controller.content.strokes.values {
            try content.add(stroke)
        }
        return content
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
