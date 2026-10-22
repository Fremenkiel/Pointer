import Foundation
import Geometry
import Model
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

@MainActor
@Suite("Hover dot on the canvas")
struct HoverTests {
    private static let tip = CGPoint(x: 120, y: 80)

    /// A shown canvas of 400 x 300 points with one card, so that a test can start a flight.
    private func makeController() throws -> CanvasViewController {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        try content.add(Self.card())
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: content
        )
        dependencies.camera = Camera(center: .zero, zoom: 1)
        let controller = CanvasViewController(dependencies: dependencies)
        controller.isShownCanvas = true
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        controller.view.layoutIfNeeded()
        return controller
    }

    private static func card() throws -> Card {
        try NewCardTests.card(
            1,
            frame: Rect(origin: Point(x: 10, y: 10), size: Size(width: 100, height: 70))
        )
    }

    @Test("The dot layer lies above the live canvas and starts hidden (D-126)")
    func layerOrder() throws {
        let controller = try makeController()
        let sublayers = try #require(controller.canvasView.layer.sublayers)
        let dotIndex = try #require(
            sublayers.firstIndex { $0 === controller.canvasView.hoverDot.layer }
        )
        let liveIndex = try #require(
            sublayers.firstIndex { $0 === controller.canvasView.liveCanvas.layer }
        )
        #expect(dotIndex > liveIndex)
        #expect(controller.canvasView.hoverDot.layer.isHidden)
    }

    @Test("A move of the dot does not animate (D-126)")
    func noAnimation() throws {
        let controller = try makeController()
        let layer = controller.canvasView.hoverDot.layer
        for key in ["position", "path", "hidden", "fillColor", "strokeColor"] {
            #expect(layer.action(forKey: key) == nil, "Key \(key)")
        }
        controller.hoverBegan(at: Self.tip, isPreviewOn: true)
        controller.hoverMoved(to: CGPoint(x: 200, y: 150))
        #expect(layer.animationKeys() == nil)
    }

    @Test("A hover shows the dot of the pen at the tip and follows it, and its end hides it")
    func penDot() throws {
        let controller = try makeController()
        let hover = controller.canvasView.hoverDot
        controller.hoverBegan(at: Self.tip, isPreviewOn: true)
        #expect(hover.shownCenter == Self.tip)
        #expect(!hover.showsRing)
        let next = CGPoint(x: 130.5, y: 90.25)
        controller.hoverMoved(to: next)
        #expect(hover.shownCenter == next)
        controller.hideHoverDot()
        #expect(hover.shownCenter == nil)
    }

    @Test("The eraser shows its circle, and a tool change during a hover switches the shape")
    func eraserRing() throws {
        let controller = try makeController()
        let hover = controller.canvasView.hoverDot
        controller.hoverBegan(at: Self.tip, isPreviewOn: true)
        controller.select(.eraser)
        #expect(hover.showsRing)
        #expect(hover.shownCenter == Self.tip)
        #expect(hover.layer.fillColor == nil)
        #expect(hover.layer.strokeColor != nil)
        controller.select(.text)
        #expect(!hover.showsRing)
        #expect(hover.layer.fillColor != nil)
    }

    @Test("No dot shows while Show Hover Preview is off, read at the start of each hover")
    func previewOff() throws {
        let controller = try makeController()
        let hover = controller.canvasView.hoverDot
        controller.hoverBegan(at: Self.tip, isPreviewOn: false)
        #expect(hover.shownCenter == nil)
        controller.hoverMoved(to: CGPoint(x: 10, y: 10))
        #expect(hover.shownCenter == nil)
        controller.hideHoverDot()
        controller.hoverBegan(at: Self.tip, isPreviewOn: true)
        #expect(hover.shownCenter == Self.tip)
    }

    @Test("A pencil down hides the dot until the pencil lifts")
    func pencilDown() throws {
        let controller = try makeController()
        let hover = controller.canvasView.hoverDot
        controller.hoverBegan(at: Self.tip, isPreviewOn: true)
        controller.pencilBegan()
        #expect(hover.shownCenter == nil)
        controller.hoverMoved(to: Self.tip)
        #expect(hover.shownCenter == nil)
        controller.pencilEnded(at: 1, isCancelled: false)
        controller.hoverMoved(to: Self.tip)
        #expect(hover.shownCenter == Self.tip)
    }

    @Test("The start of a card flight hides the dot, and no dot shows during it")
    func flight() throws {
        let controller = try makeController()
        let hover = controller.canvasView.hoverDot
        controller.hoverBegan(at: Self.tip, isPreviewOn: true)
        controller.beginOpen(of: try Self.card()) {}
        #expect(controller.isInCardTransition)
        #expect(hover.shownCenter == nil)
        controller.hoverMoved(to: Self.tip)
        #expect(hover.shownCenter == nil)
    }

    @Test("A canvas that the container does not show shows no dot")
    func notShown() throws {
        let controller = try makeController()
        controller.isShownCanvas = false
        controller.hoverBegan(at: Self.tip, isPreviewOn: true)
        #expect(controller.canvasView.hoverDot.shownCenter == nil)
    }

    @Test("The hover recognizer takes the pencil only and recognizes with every recognizer")
    func recognizer() throws {
        let controller = try makeController()
        let recognizers = controller.canvasView.gestureRecognizers ?? []
        let hover = try #require(
            recognizers.compactMap { $0 as? UIHoverGestureRecognizer }
                .first { $0.delegate === controller }
        )
        #expect(hover.allowedTouchTypes == [NSNumber(value: UITouch.TouchType.pencil.rawValue)])
        let others: [UIGestureRecognizer] =
            [
                controller.panRecognizer, controller.pinchRecognizer,
                controller.canvasView.liveCanvas.drawingGestureRecognizer,
                controller.textEditing.pencilTap, controller.textEditing.fingerTap,
            ] + recognizers.filter { $0 !== hover }
        for other in others {
            #expect(controller.gestureRecognizer(hover, shouldRecognizeSimultaneouslyWith: other))
        }
        #expect(controller.gestureRecognizerShouldBegin(hover))
    }
}
