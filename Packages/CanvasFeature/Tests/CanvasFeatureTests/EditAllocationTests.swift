import Geometry
import Model
import QuartzCore
import UIKit
import XCTest

@testable import CanvasFeature
@testable import Rendering

/// The heap allocations of `FrameRenderer.apply` for one erase, one undo, and one redo of the
/// content of M4 acceptance 2 (D-69, the M4 fix plan phase 0, task 3). The test records the
/// counts. Phase 3 sets their targets. It runs on the iPad only (D-77).
@MainActor
final class EditAllocationTests: XCTestCase {
    /// The frames that a test may draw until the renderer needs no more.
    private static let maxFrames = 400

    func testAllocationsOfOneEraseUndoAndRedo() async throws {
        let host = try OnScreenCanvas.host()
        let content = try EraseUndoPerformanceTests.content()
        let command = try eraseCommand(content: content, host: host)
        let renderer = try CanvasRenderer()
        let layer = CAMetalLayer()
        renderer.configure(layer)
        let size = host.view.bounds.size
        let scale = host.traitCollection.displayScale
        layer.drawableSize = CGSize(width: size.width * scale, height: size.height * scale)
        renderer.setViewport(
            viewSize: Size(width: size.width, height: size.height),
            displayScale: scale
        )
        renderer.camera = EraseUndoPerformanceTests.camera
        renderer.load(Array(content.strokes.values))
        Self.drain(renderer, layer)
        let erase = RenderEdit(
            removed: command.removed.map(\.id),
            added: command.parts,
            area: command.area
        )
        let undo = RenderEdit(
            removed: command.parts.map(\.id),
            added: command.removed,
            area: command.area
        )
        var lines: [String] = []
        for (name, edit) in [("erase", erase), ("undo", undo), ("redo", erase)] {
            let count = Self.countApply(edit, in: renderer.engine)
            Self.drain(renderer, layer)
            lines.append("\(name) \(count.map(String.init) ?? "no count")")
        }
        let line = "FrameRenderer.apply allocations: " + lines.joined(separator: ", ")
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertEqual(
            renderer.strokeCount,
            content.strokes.count + command.parts.count
                - command.removed.count,
            line
        )
    }

    /// Erases the 1,000 parallel strokes on a canvas on the screen, as acceptance 2 does, and
    /// returns the command of the gesture.
    private func eraseCommand(
        content: CanvasContent,
        host: UIViewController
    ) throws -> EraseStrokes {
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: content
        )
        dependencies.camera = EraseUndoPerformanceTests.camera
        let canvas = CanvasViewController(dependencies: dependencies)
        EraseUndoPerformanceTests.show(canvas, in: host)
        defer { EraseUndoPerformanceTests.close(canvas) }
        canvas.select(.eraser)
        canvas.pencilBegan()
        let size = Size(width: canvas.view.bounds.width, height: canvas.view.bounds.height)
        for step in 0...260 {
            canvas.pencilMoved(
                to: EraseUndoPerformanceTests.camera.viewPoint(
                    fromCanvas: Point(x: 0, y: Double(step) * 6 - 780),
                    viewSize: size
                )
            )
        }
        canvas.pencilEnded(at: 0, isCancelled: false)
        return try XCTUnwrap(canvas.history.undoSteps.last as? EraseStrokes)
    }

    /// Counts the allocations of one `apply` under the lock of the render state.
    private nonisolated static func countApply(
        _ edit: RenderEdit,
        in engine: RenderEngine
    ) -> Int? {
        engine.withRenderer { frameRenderer in
            AllocationCounter.count { frameRenderer.apply(edit) }
        }
    }

    /// Draws frames until the renderer needs no more, so that removals are released.
    private static func drain(_ renderer: CanvasRenderer, _ layer: CAMetalLayer) {
        for _ in 0..<maxFrames where renderer.renderFrame(into: layer, deadline: nil) {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }
}
