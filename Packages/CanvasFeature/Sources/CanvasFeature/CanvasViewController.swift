import Geometry
import Model
import PencilKit
import Rendering
import UIKit
import os

/// The canvas screen: ink on one canvas with pen input, pan, and zoom (M2).
@MainActor
public final class CanvasViewController: UIViewController {
    private let renderer: CanvasRenderer
    private let handoff: LiveStrokeHandoff
    private let canvasView: CanvasView
    private let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Canvas")
    private var content: CanvasContent
    private var cameraController: CameraController
    private var palmGuard = PalmGuard()
    private let panRecognizer = UIPanGestureRecognizer()
    private let pinchRecognizer = UIPinchGestureRecognizer()
    private let pencilObserver = PencilTouchObserver()

    /// Makes the canvas screen.
    ///
    /// - Precondition: The initial strokes belong to the canvas and fit its limit.
    public init(dependencies: CanvasDependencies) {
        precondition(
            dependencies.initialStrokes.count <= Limits.maxStrokesPerCanvas,
            "The canvas holds at most \(Limits.maxStrokesPerCanvas) strokes"
        )
        renderer = dependencies.renderer
        canvasView = CanvasView(renderer: renderer)
        content = CanvasContent(canvasID: dependencies.canvasID)
        cameraController = CameraController(camera: renderer.camera, viewSize: .zero)
        let converter = PencilKitStrokeConverter(
            factory: dependencies.strokeFactory,
            canvasID: dependencies.canvasID
        )
        handoff = LiveStrokeHandoff(
            canvasView: canvasView.liveCanvas,
            renderer: renderer,
            converter: converter
        )
        super.init(nibName: nil, bundle: nil)
        add(dependencies.initialStrokes)
        renderer.load(dependencies.initialStrokes)
        assert(
            content.strokes.count == dependencies.initialStrokes.count,
            "Each initial stroke is in the content"
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        // swiftlint:disable:next safe_07_fatal_error
        fatalError("CanvasViewController has no coder support")
    }

    /// Uses the canvas view as the root view.
    override public func loadView() {
        view = canvasView
    }

    /// Connects the live canvas, the gestures, and the frame loop.
    override public func viewDidLoad() {
        super.viewDidLoad()
        canvasView.liveCanvas.delegate = self
        handoff.onStrokes = { [weak self] strokes in self?.add(strokes) }
        handoff.remainingCapacity = { [weak self] in
            Limits.maxStrokesPerCanvas - (self?.content.strokes.count ?? Limits.maxStrokesPerCanvas)
        }
        canvasView.inkView.onFrame = { [weak self] time in self?.stepCamera(to: time) ?? false }
        installGestures()
    }

    /// Keeps the camera controller on the size of the view.
    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraController.viewSize = viewSize
    }

    private var viewSize: Size {
        Size(width: canvasView.bounds.width, height: canvasView.bounds.height)
    }

    private func add(_ strokes: [Stroke]) {
        for stroke in strokes {
            do {
                try content.add(stroke)
            } catch {
                logger.error("The canvas is at its stroke limit. A stroke is not stored.")
            }
        }
    }

    private func installGestures() {
        panRecognizer.maximumNumberOfTouches = 1
        for recognizer in [panRecognizer, pinchRecognizer] as [UIGestureRecognizer] {
            recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            recognizer.delegate = self
            canvasView.addGestureRecognizer(recognizer)
        }
        panRecognizer.addTarget(self, action: #selector(handlePan(_:)))
        pinchRecognizer.addTarget(self, action: #selector(handlePinch(_:)))
        pencilObserver.onBegan = { [weak self] in self?.pencilBegan() }
        pencilObserver.onEnded = { [weak self] time in self?.palmGuard.pencilEnded(at: time) }
        canvasView.addGestureRecognizer(pencilObserver)
    }

    /// The camera stops, and running finger gestures end (D-36).
    private func pencilBegan() {
        palmGuard.pencilBegan()
        cameraController.stopAnimation()
        for recognizer in [panRecognizer, pinchRecognizer] where recognizer.state != .possible {
            recognizer.isEnabled = false
            recognizer.isEnabled = true
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: canvasView)
        recognizer.setTranslation(.zero, in: canvasView)
        guard pinchRecognizer.state == .possible || pinchRecognizer.state == .failed else { return }
        cameraController.pan(byView: Vector(dx: translation.x, dy: translation.y))
        if recognizer.state == .ended {
            let velocity = recognizer.velocity(in: canvasView)
            cameraController.endPan(velocity: Vector(dx: velocity.x, dy: velocity.y))
        }
        applyCamera()
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        let location = recognizer.location(in: canvasView)
        let centroid = Point(x: location.x, y: location.y)
        switch recognizer.state {
        case .began:
            cameraController.beginPinch(centroid: centroid)
        case .changed where recognizer.numberOfTouches >= 2 && recognizer.scale > 0:
            cameraController.updatePinch(scale: recognizer.scale, centroid: centroid)
        case .ended, .cancelled, .failed:
            cameraController.endPinch()
        default:
            return
        }
        applyCamera()
    }

    private func stepCamera(to time: TimeInterval) -> Bool {
        let isAnimating = cameraController.step(to: time)
        applyCamera()
        return isAnimating
    }

    /// Sends the camera to the renderer and the matching pen width to the live canvas.
    private func applyCamera() {
        let camera = cameraController.camera
        if camera.zoom != renderer.camera.zoom {
            canvasView.liveCanvas.tool = PenTool.inkingTool(zoom: camera.zoom)
        }
        renderer.camera = camera
        if cameraController.isAnimating {
            canvasView.inkView.requestFrame()
        }
    }
}

extension CanvasViewController: PKCanvasViewDelegate {
    /// Hands off each finished stroke.
    public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        handoff.drawingDidChange(camera: cameraController.camera, viewSize: viewSize)
    }

    /// The pencil starts a live stroke. The removal of handed-off strokes waits.
    public func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        handoff.isToolInUse = true
    }

    /// The pencil lifted. Handed-off strokes can leave the drawing.
    public func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        handoff.isToolInUse = false
    }
}

extension CanvasViewController: UIGestureRecognizerDelegate {
    /// The palm guard filters the finger touches of pan and pinch (architecture.md 4.1).
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard touch.type == .direct else { return false }
        let isAllowed = palmGuard.allowsFingerTouch(
            at: touch.timestamp,
            majorRadius: Double(touch.majorRadius)
        )
        // A finger that touches down stops a glide at once, as in UIScrollView. The pan itself
        // begins only after the movement threshold of UIKit.
        if isAllowed {
            cameraController.stopAnimation()
        }
        return isAllowed
    }

    /// Pan and pinch run together, so a second finger can join a pan.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        let pair: Set<ObjectIdentifier> = [
            ObjectIdentifier(panRecognizer), ObjectIdentifier(pinchRecognizer),
        ]
        return pair.contains(ObjectIdentifier(gestureRecognizer))
            && pair.contains(ObjectIdentifier(otherGestureRecognizer))
    }
}
