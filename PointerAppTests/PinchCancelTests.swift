import Foundation
import Geometry
import Model
import Testing
import UIKit.UIGestureRecognizerSubclass

@testable import CanvasFeature
@testable import Pointer

/// A pinch recognizer whose state, scale, and midpoint the test sets.
private final class ScriptedPinch: UIPinchGestureRecognizer {
    var midpoint = CGPoint(x: 400, y: 300)
    private var scripted = UIGestureRecognizer.State.possible
    private var scriptedScale: CGFloat = 1

    override var state: UIGestureRecognizer.State {
        get { scripted }
        set { scripted = newValue }
    }

    override var scale: CGFloat {
        get { scriptedScale }
        set { scriptedScale = newValue }
    }

    override var numberOfTouches: Int { 2 }

    override func location(in view: UIView?) -> CGPoint { midpoint }

    /// Sends one step of the pinch to the canvas.
    func send(_ state: UIGestureRecognizer.State, scale: CGFloat, to canvas: CanvasViewController) {
        self.state = state
        self.scale = scale
        canvas.handlePinch(self)
    }
}

/// Acceptance 3 of M6: a lift above the threshold cancels the pinch-out exit (m6-plan.md task
/// 5.3, CARD-05, D-104).
@MainActor
@Suite("Pinch-out cancel")
struct PinchCancelTests {
    /// The child of a tree of one card on the screen, at zoom 1.
    private static func child() async throws -> (NavigationTests.Tree, AppComposition) {
        let tree = try await NavigationTests.makeTree(depth: 1)
        let composition = try NavigationTests.composition(for: tree)
        await composition.selector?.start(lastWorkspace: tree.workspace.id)
        try await NavigationTests.waitForCanvas(tree.workspace.canvasID, in: composition)
        let card = try #require(composition.container.canvas?.content.cards[tree.chain[0]])
        composition.openChild(card)
        try await NavigationTests.waitForCanvas(CanvasID(tree.chain[0]), in: composition)
        return (tree, composition)
    }

    /// Pinches the shown canvas from zoom 1 to a raw zoom of `factor` times the exit zoom. Inside
    /// a card, the exit zoom is `exitZoomRatio` times zoom 1 (D-119).
    private static func pinch(_ canvas: CanvasViewController, to factor: Double) {
        let pinch = ScriptedPinch()
        let raw = Limits.standardZoom * CameraController.exitZoomRatio * factor
        pinch.send(.began, scale: 1, to: canvas)
        for step in 1...20 {
            let scale = 1 + (raw - 1) * Double(step) / 20
            pinch.send(.changed, scale: scale, to: canvas)
        }
        pinch.send(.ended, scale: raw, to: canvas)
    }

    @Test("A lift above the threshold keeps the child at zoom 1 (D-119)")
    func liftAbove() async throws {
        let (tree, composition) = try await Self.child()
        defer {
            composition.container.view.removeFromSuperview()
            tree.remove()
        }
        let child = try #require(composition.container.canvas)
        #expect(child.camera.zoom == Limits.standardZoom)
        let start = child.camera
        Self.pinch(child, to: 1.05)
        // Inside a card, the screen shows no zoom (D-119).
        #expect(child.renderer.camera == start)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: NavigationTests.timeout)
        while child.cameraController.isAnimating {
            guard clock.now < deadline else {
                Issue.record("The spring did not end at zoom \(child.cameraController.camera.zoom)")
                throw OpenTimedOut()
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(child.cameraController.camera == start)
        #expect(child.renderer.camera == start)
        #expect(composition.container.canvas === child)
        #expect(composition.path?.level == 1)
        #expect(composition.opening == nil, "No leave started")
    }

    @Test("A lift under the threshold leaves the child and ends at the region of the preview")
    func liftUnder() async throws {
        let (tree, composition) = try await Self.child()
        defer {
            composition.container.view.removeFromSuperview()
            tree.remove()
        }
        let child = try #require(composition.container.canvas)
        // A pan moves the child away from the camera of the open, which the preview shows.
        child.cameraController.pan(byView: Vector(dx: 300, dy: -120))
        let open = child.content.openCamera
        #expect(child.cameraController.camera.center != open.center)
        Self.pinch(child, to: 0.95)
        try await NavigationTests.waitForCanvas(tree.workspace.canvasID, in: composition)
        // The minimize animation slides the child to the region of the preview (D-109).
        #expect(child.camera == open)
        #expect(composition.path?.level == 0)
    }
}
