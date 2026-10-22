import Foundation
import Geometry
import Model
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

@MainActor
@Suite("Double tap on the canvas")
struct DoubleTapTests {
    /// The settings that switch the tool (D-130).
    nonisolated private static let switchingActions: [UIPencilPreferredAction] = [
        .switchEraser, .switchPrevious,
    ]
    /// The settings that do nothing (D-130), with a raw value of a later SDK.
    nonisolated private static let ignoredActions: [UIPencilPreferredAction] = [
        .ignore, .showColorPalette, .showInkAttributes, .showContextualPalette, .runSystemShortcut,
        UIPencilPreferredAction(rawValue: 7) ?? .ignore,
    ]

    /// A view of 400 x 300 points with a library, so that a text edit can start. The container
    /// shows it, unless `isShown` is `false`.
    private func makeController(isShown: Bool = true) throws -> CanvasViewController {
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: CanvasContent(canvasID: Fixtures.canvas)
        )
        dependencies.camera = Camera(center: .zero, zoom: 1)
        dependencies.repository = RecordingLibrary()
        let controller = CanvasViewController(dependencies: dependencies)
        controller.isShownCanvas = isShown
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        controller.view.layoutIfNeeded()
        return controller
    }

    @Test(
        "A switching setting takes the pen to the eraser and back, on the canvas and the button",
        arguments: switchingActions
    )
    func switchesTool(action: UIPencilPreferredAction) throws {
        let controller = try makeController()
        controller.doubleTap(action: action)
        #expect(controller.tool == .eraser)
        #expect(controller.toolControls.selected == .eraser)
        #expect(!controller.canvasView.liveCanvas.drawingGestureRecognizer.isEnabled)
        controller.doubleTap(action: action)
        #expect(controller.tool == .pen)
        #expect(controller.toolControls.selected == .pen)
        #expect(controller.canvasView.liveCanvas.drawingGestureRecognizer.isEnabled)
    }

    @Test(
        "A switching setting ends a text edit and takes the text tool to the pen (D-87)",
        arguments: switchingActions
    )
    func endsTextEdit(action: UIPencilPreferredAction) throws {
        let controller = try makeController()
        controller.select(.text)
        controller.startNewTextBox(at: .zero)
        controller.textEditing.view.text = "a"
        #expect(controller.textEditing.isEditing)
        controller.doubleTap(action: action)
        #expect(!controller.textEditing.isEditing)
        #expect(controller.content.textBoxes.count == 1)
        #expect(controller.tool == .pen)
        #expect(controller.toolControls.selected == .pen)
    }

    @Test(
        "A double tap during a pencil touch takes effect at the next pencil down (D-70)",
        arguments: switchingActions
    )
    func duringPencilTouch(action: UIPencilPreferredAction) throws {
        let controller = try makeController()
        controller.pencilBegan()
        controller.doubleTap(action: action)
        #expect(controller.tool == .eraser)
        #expect(controller.toolState.active == .pen)
        controller.pencilEnded(at: 1, isCancelled: false)
        #expect(controller.toolState.active == .eraser)
    }

    @Test(
        "Every other setting leaves the tool, the button, and a text edit",
        arguments: ignoredActions,
        Tool.allCases
    )
    func ignored(action: UIPencilPreferredAction, tool: Tool) throws {
        let controller = try makeController()
        controller.select(tool)
        if tool == .text {
            controller.startNewTextBox(at: .zero)
        }
        controller.doubleTap(action: action)
        #expect(controller.tool == tool)
        #expect(controller.toolControls.selected == tool)
        #expect(controller.textEditing.isEditing == (tool == .text))
    }

    @Test(
        "A canvas that the container does not show ignores a double tap and a squeeze",
        arguments: switchingActions
    )
    func notShown(action: UIPencilPreferredAction) throws {
        let controller = try makeController(isShown: false)
        controller.doubleTap(action: action)
        controller.squeeze(
            isEnded: true,
            action: .showContextualPalette,
            hoverLocation: CGPoint(x: 10, y: 10)
        )
        #expect(controller.tool == .pen)
        #expect(controller.toolControls.selected == .pen)
        #expect(controller.presentedViewController == nil)
    }

    @Test("The canvas is the delegate of its pencil interaction and gets the double tap")
    func delegate() throws {
        let controller = try makeController()
        let interaction = try #require(
            controller.view.interactions.compactMap { $0 as? UIPencilInteraction }.first
        )
        #expect(interaction.delegate === controller)
        let selector = #selector(
            UIPencilInteractionDelegate.pencilInteraction(_:didReceiveTap:)
        )
        #expect(controller.responds(to: selector))
    }
}
