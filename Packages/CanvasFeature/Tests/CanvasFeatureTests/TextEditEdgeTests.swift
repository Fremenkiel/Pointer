import Foundation
import Geometry
import Model
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

/// The edges of text boxes that the review after M9 found: equal sort keys and the key commands
/// after an edit.
@MainActor
@Suite("Edges of the text boxes")
struct TextEditEdgeTests {
    /// A canvas of 400 x 300 points without content.
    private func makeController() throws -> CanvasViewController {
        let dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: CanvasContent(canvasID: Fixtures.canvas)
        )
        let controller = CanvasViewController(dependencies: dependencies)
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        controller.view.layoutIfNeeded()
        return controller
    }

    @Test("Of boxes with equal sort keys, a tap takes the box with the largest ID (3.1.3)")
    func equalKeysTieByID() throws {
        let boxes = try (1...8).map { try TextEditTests.box("node", id: UInt8($0)) }
        let byID = Dictionary(uniqueKeysWithValues: boxes.map { ($0.id, $0) })
        let hit = TextEditing().box(at: Point(x: 15, y: 25), in: byID, zoom: 1, tapTarget: 44)
        #expect(hit?.id == boxes.map(\.id).max())
    }

    @Test("After a text edit, the canvas takes the key commands again (review after M9)")
    func keyCommandsAfterEdit() throws {
        let controller = try makeController()
        let host = try OnScreenCanvas.host()
        OnScreenCanvas.show(controller, in: host)
        defer { OnScreenCanvas.close(controller) }
        controller.select(.text)
        controller.startNewTextBox(at: Point(x: 5, y: 5))
        controller.textEditing.view.text = "queue"
        controller.endTextEdit()
        #expect(controller.isFirstResponder)
    }

}
