import Foundation
import Model
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

@MainActor
@Suite("Tool palette and squeeze")
struct ToolPaletteTests {
    private let tip = CGPoint(x: 120, y: 80)
    private let last = CGPoint(x: 10, y: 20)

    @Test("A squeeze with the setting Ignore or Run Shortcut opens nothing")
    func ignoredSettings() {
        for action in [UIPencilPreferredAction.ignore, .runSystemShortcut] {
            let anchor = PaletteAnchor.squeeze(
                isEnded: true,
                action: action,
                hoverLocation: tip,
                lastPencilLocation: last
            )
            #expect(anchor == nil)
        }
    }

    @Test("A squeeze opens the palette at the tip, else at the last pencil location")
    func anchor() {
        for action in [UIPencilPreferredAction.showContextualPalette, .switchEraser] {
            #expect(
                PaletteAnchor.squeeze(
                    isEnded: true,
                    action: action,
                    hoverLocation: tip,
                    lastPencilLocation: last
                ) == tip
            )
            #expect(
                PaletteAnchor.squeeze(
                    isEnded: true,
                    action: action,
                    hoverLocation: nil,
                    lastPencilLocation: last
                ) == last
            )
        }
    }

    @Test("Only the end of a squeeze acts")
    func phase() {
        let anchor = PaletteAnchor.squeeze(
            isEnded: false,
            action: .showContextualPalette,
            hoverLocation: tip,
            lastPencilLocation: last
        )
        #expect(anchor == nil)
    }

    @Test("A tool picked in the palette becomes the tool of the canvas and of the button")
    func pick() throws {
        let controller = CanvasViewController(
            dependencies: CanvasDependencies(
                renderer: try CanvasRenderer(),
                clock: Fixtures.clock(),
                content: CanvasContent(canvasID: Fixtures.canvas)
            )
        )
        controller.loadViewIfNeeded()
        controller.toolControls.select(.eraser)
        #expect(controller.tool == .eraser)
        #expect(controller.toolControls.selected == .eraser)
        controller.select(.pen)
        #expect(controller.toolControls.selected == .pen)
        #expect(controller.view.interactions.contains { $0 is UIPencilInteraction })
        #expect(controller.toolButton.view != nil)
    }
}
