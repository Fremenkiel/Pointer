import Foundation
import Model
import Testing

@testable import CanvasFeature
@testable import Rendering

/// A step that fails after the renderer got its change (D-122, the M6 fix plan task 3.2).
extension CanvasHistoryTests {
    /// The strokes that the renderer holds after the waiting load and edits. The canvas has no
    /// window, so no frame takes them from the inbox.
    static func rendered(_ renderer: CanvasRenderer) -> Set<StrokeID> {
        renderer.engine.inbox.withLock { box in
            var ids = Set(box.loaded.map(\.id))
            for edit in box.edits {
                ids.subtract(edit.removed)
                ids.formUnion(edit.added.map(\.id))
            }
            return ids
        }
    }

    @Test("A redo that fails after the renderer got its change leaves the strokes of the model")
    func failedRedo() throws {
        let line = Self.line()
        let controller = try makeController(
            content: CanvasContent(canvasID: Fixtures.canvas),
            sessions: CanvasSessions(),
            clock: Fixtures.clock()
        )
        controller.addPenStrokes([line])
        erase(controller)
        controller.undo()
        // Another change took the line away, so the redo of the erase fails (D-122).
        _ = controller.content.remove(line.id, at: controller.clock.factory.clock.now())
        controller.renderer.change(removing: [line.id], adding: [], area: nil, onPresented: {})
        #expect(Self.rendered(controller.renderer) == Set(controller.content.strokes.keys))
        controller.redo()
        #expect(controller.content.strokes.isEmpty)
        #expect(Self.rendered(controller.renderer) == Set(controller.content.strokes.keys))
        #expect(controller.historyControls.canRedo)
    }
}
