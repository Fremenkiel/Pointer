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

    /// A shown canvas of 400 x 300 points.
    private func makeController() throws -> CanvasViewController {
        let controller = CanvasViewController(
            dependencies: CanvasDependencies(
                renderer: try CanvasRenderer(),
                clock: Fixtures.clock(),
                content: CanvasContent(canvasID: Fixtures.canvas)
            )
        )
        controller.isShownCanvas = true
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        controller.view.layoutIfNeeded()
        return controller
    }

    /// A visible window of the scene of the test host with the canvas as its root, so that the
    /// palette can present. The caller hides it at the end.
    private func makeWindow(for controller: CanvasViewController) throws -> UIWindow {
        // Only UIApplication reaches the scene of the test host, as in `ViewSnapshot` (D-59).
        // swiftlint:disable:next arch_05_singletons
        let scenes = UIApplication.shared.connectedScenes
        let scene = try #require(scenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()
        return window
    }

    /// Opens the palette with a squeeze, waits for its animation, and returns its host.
    private func openPalette(_ controller: CanvasViewController) async throws -> UIViewController {
        controller.squeeze(isEnded: true, action: .showContextualPalette, hoverLocation: tip)
        let host = try #require(controller.presentedViewController)
        #expect(host === controller.paletteHost)
        // The loop is bounded (FLOW-03).
        for _ in 0..<100 where host.isBeingPresented {
            try await Task.sleep(for: .milliseconds(20))
        }
        return host
    }

    /// Waits until no screen is presented, for at most 2 seconds.
    private func waitForClose(_ controller: CanvasViewController) async throws {
        for _ in 0..<100 where controller.presentedViewController != nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(controller.presentedViewController == nil)
    }

    @Test("A tool picked in the palette becomes the tool of the canvas and of the button")
    func pick() throws {
        let controller = try makeController()
        controller.toolControls.select(.eraser)
        #expect(controller.tool == .eraser)
        #expect(controller.toolControls.selected == .eraser)
        controller.select(.pen)
        #expect(controller.toolControls.selected == .pen)
        #expect(controller.view.interactions.contains { $0 is UIPencilInteraction })
        #expect(controller.toolButton.view != nil)
    }

    @Test("A tool tap keeps the palette open, and a size tap closes it (D-201)")
    func toolTapKeepsOpen() async throws {
        let controller = try makeController()
        let window = try makeWindow(for: controller)
        defer { window.isHidden = true }
        let host = try await openPalette(controller)
        let passthrough = host.popoverPresentationController?.passthroughViews ?? []
        #expect(passthrough.contains { $0 === controller.canvasView })
        controller.toolControls.select(.eraser)
        #expect(controller.tool == .eraser)
        #expect(controller.presentedViewController === host)
        #expect(!host.isBeingDismissed)
        controller.toolControls.selectEraserSize(.large)
        #expect(controller.eraserSettings.size == .large)
        try await waitForClose(controller)
    }

    @Test("A pen width tap and a touch on the canvas close the palette (D-201)")
    func widthTapAndTouchClose() async throws {
        let controller = try makeController()
        let window = try makeWindow(for: controller)
        defer { window.isHidden = true }
        _ = try await openPalette(controller)
        controller.toolControls.selectWidth(.thin)
        #expect(controller.penSettings.width == .thin)
        try await waitForClose(controller)
        _ = try await openPalette(controller)
        let hitTest = try #require(controller.canvasView.onTouchHitTest)
        hitTest()
        try await waitForClose(controller)
    }

    @Test("A touch during the open animation of the palette closes it after it (D-201)")
    func touchDuringOpen() async throws {
        let controller = try makeController()
        let window = try makeWindow(for: controller)
        defer { window.isHidden = true }
        controller.squeeze(isEnded: true, action: .showContextualPalette, hoverLocation: tip)
        #expect(controller.presentedViewController != nil)
        controller.dismissPalette()
        try await waitForClose(controller)
    }

    @Test("A touch on the canvas leaves another presented screen in place (D-201)")
    func touchKeepsOtherScreens() throws {
        let controller = try makeController()
        let window = try makeWindow(for: controller)
        defer { window.isHidden = true }
        let other = UIViewController()
        controller.present(other, animated: false)
        #expect(controller.presentedViewController === other)
        controller.dismissPalette()
        #expect(controller.presentedViewController === other)
        #expect(!other.isBeingDismissed)
        other.dismiss(animated: false)
    }
}
