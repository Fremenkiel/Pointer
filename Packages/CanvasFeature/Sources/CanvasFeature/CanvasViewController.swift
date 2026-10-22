import Geometry
import Model
import PencilKit
import Rendering
import SwiftUI
import UIKit
import os

/// The canvas screen: ink on one canvas with pen input, pan, and zoom (M2), saved to the
/// library (M3).
@MainActor
public final class CanvasViewController: UIViewController {
    let renderer: CanvasRenderer
    private let handoff: LiveStrokeHandoff
    let canvasView: CanvasView
    let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Canvas")
    let clock: AppClock
    var content: CanvasContent
    /// The undo and redo steps of the canvas (D-12).
    var history = History()
    /// The histories of the app, or `nil` for a canvas whose history ends with it.
    let sessions: CanvasSessions?
    /// The state of the undo and redo buttons.
    let historyControls = HistoryControls()
    /// The state of the current-tool button and the palette.
    let toolControls = ToolControls()
    /// The host of the current-tool button and the card button.
    private(set) lazy var toolButtonHost = UIHostingController(
        rootView: ToolChrome(controls: toolControls)
    )
    /// The current-tool button and the card button right of it. The app places them next to the
    /// workspace selector (D-64, D-117).
    public var toolButton: UIViewController { toolButtonHost }
    /// Runs when the GPU completes the first frame that holds an erase, an undo, or a redo, with
    /// the `gpuEndTime` of that frame. The acceptance test of M4 times the steps with it (D-69,
    /// D-74).
    var onStepDrawn: (@MainActor (Double) -> Void)?
    /// The last pencil location in view space. A squeeze without a hover pose opens the palette
    /// there.
    var lastPencilLocation: CGPoint?
    /// The tool and the rules of a tool change (D-70).
    private(set) var toolState = ToolState()
    /// The samples of the running eraser gesture in view space, or `nil` without a gesture.
    var eraserSamples: [Point]?
    /// The sample list of the last gesture, kept for its capacity.
    var spareEraserSamples: [Point] = []
    var cameraController: CameraController
    var palmGuard = PalmGuard()
    let panRecognizer = UIPanGestureRecognizer()
    let pinchRecognizer = UIPinchGestureRecognizer()
    let pencilObserver = PencilTouchObserver()
    let repository: (any LibraryRepository)?
    /// Sends the rows of the steps in order, or `nil` without a library (F-11).
    private let rowChannel: RowChannel?
    private let onCameraRest: @MainActor (Camera) -> Void
    /// True after a camera change, until the camera comes to rest.
    private var isCameraMoving = false
    /// True after `endSession()` kept the session.
    var hasEndedSession = false
    /// The key commands of undo and redo, made once (C-05).
    lazy var historyKeyCommands = makeHistoryKeyCommands()
    /// The edit view, the running edit, and the move of the text boxes.
    let textEditing = TextEditing()
    /// Shows a short message, for example at a limit.
    let onMessage: @MainActor (String) -> Void
    /// The level of the canvas in the card tree. A new card is refused at `Limits.maxDepth`.
    let level: Int
    /// Opens a card after a tap on it (CARD-03, D-115).
    let onOpenCard: @MainActor (Card) -> Void
    /// The open or the leave of a card that runs on this canvas, or `nil` (D-98).
    var cardTransition: CardTransition?
    /// The card of this canvas in its parent and the leave by a pinch (CARD-05).
    let parentLink: ParentLink
    /// `true` while the container shows this canvas. Two screens exist during a card flight, and
    /// only the shown one takes a double tap or a squeeze (architecture.md 4.5).
    public var isShownCanvas = false

    /// Makes the canvas screen.
    ///
    /// - Precondition: The loaded and the transient strokes fit the bound after an erase
    ///   together (D-73).
    public init(dependencies: CanvasDependencies) {
        precondition(
            dependencies.content.strokes.count + dependencies.transientStrokes.count
                <= Limits.maxStrokesAfterErase,
            "The canvas holds at most \(Limits.maxStrokesAfterErase) strokes"
        )
        renderer = dependencies.renderer
        let camera = dependencies.camera ?? renderer.camera
        cameraController = CameraController(camera, dependencies.level)
        renderer.camera = cameraController.camera
        canvasView = CanvasView(renderer: renderer)
        // `applyCamera` sets the width only when the zoom changes, so a stored zoom needs it here.
        canvasView.liveCanvas.tool = PenTool.inkingTool(zoom: renderer.camera.zoom)
        content = dependencies.content
        clock = dependencies.clock
        repository = dependencies.repository
        rowChannel = dependencies.repository.map { RowChannel(repository: $0) }
        sessions = dependencies.sessions
        onCameraRest = dependencies.onCameraRest
        onMessage = dependencies.onMessage
        level = dependencies.level
        onOpenCard = dependencies.onOpenCard
        parentLink = ParentLink(card: dependencies.parentCard, onLeave: dependencies.onPinchLeave)
        let converter = PencilKitStrokeConverter(
            clock: dependencies.clock,
            canvasID: dependencies.canvasID
        )
        handoff = LiveStrokeHandoff(
            canvasView: canvasView.liveCanvas,
            renderer: renderer,
            converter: converter
        )
        super.init(nibName: nil, bundle: nil)
        takeSession()
        // The fill content stays in memory and is never saved (D-55).
        add(dependencies.transientStrokes)
        loadRenderer()
        assert(
            content.strokes.count
                == dependencies.content.strokes.count + dependencies.transientStrokes.count,
            "Each loaded and each transient stroke is in the content"
        )
    }

    /// The canvas that the screen shows.
    public var canvasID: CanvasID { content.canvasID }

    /// The camera that the canvas shows now.
    public var camera: Camera { cameraController.shownCamera }

    /// False while the library cannot save. The pencil then draws and erases nothing (storage.md
    /// 4, D-70).
    public var isEditingEnabled: Bool {
        get { toolState.isEditingEnabled }
        set {
            toolState.isEditingEnabled = newValue
            applyToolState()
        }
    }

    /// The tool that the user picked last.
    public var tool: Tool { toolState.selected }

    /// Picks a tool. It takes effect at the next pencil down (D-70). A running text edit ends at
    /// once (D-87).
    public func select(_ tool: Tool) {
        endTextEdit()
        toolState.select(tool)
        toolControls.selected = tool
        // The mask texture is made now, not at the first sample (D-78).
        renderer.setEraserReady(tool == .eraser)
        applyToolState()
        toolDidChangeForHover()
    }

    /// Turns the drawing gesture of PencilKit on only for an active pen (D-34, D-70).
    private func applyToolState() {
        canvasView.liveCanvas.drawingGestureRecognizer.isEnabled = toolState.isDrawingEnabled
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
        handoff.onStrokes = { [weak self] strokes in self?.addPenStrokes(strokes) }
        handoff.remainingCapacity = { [weak self] in
            Limits.maxStrokesPerCanvas - (self?.content.strokes.count ?? Limits.maxStrokesPerCanvas)
        }
        canvasView.inkView.onFrame = { [weak self] time in self?.stepCamera(to: time) ?? false }
        installGestures()
        installHistoryButtons()
        installToolControls()
        installTextControls()
        installHover()
    }

    /// Keeps the session when the canvas leaves its parent, for example at a workspace switch.
    override public func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        guard parent == nil else { return }
        endSession()
        rowChannel?.finish()
    }

    /// Takes the key commands of the hardware keyboard.
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    /// Keeps the camera controller on the size of the view.
    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraController.viewSize = viewSize
    }

    /// The size of the canvas view in view points.
    var viewSize: Size {
        Size(width: canvasView.bounds.width, height: canvasView.bounds.height)
    }

    /// Adds the strokes of one pen path as one undo step (task 3.6 of docs/m4-plan.md). The
    /// handoff gave them to the renderer already.
    func addPenStrokes(_ strokes: [Stroke]) {
        guard !strokes.isEmpty else { return }
        do {
            send(try perform(AddStroke(strokes: strokes)))
        } catch {
            logger.error("The canvas did not take a pen stroke: \(String(describing: error))")
        }
    }

    /// Adds strokes to the content. At the stroke limit, a stroke is refused and logged.
    private func add(_ strokes: [Stroke]) {
        let start = content.strokes.count
        for stroke in strokes {
            do {
                try content.add(stroke)
            } catch {
                logger.error("The canvas is at its stroke limit. A stroke is not stored.")
            }
        }
        assert(content.strokes.count - start <= strokes.count, "More strokes added than given")
    }

    /// Sends changed rows to the pending set of the library, in the order of the steps
    /// (storage.md section 4).
    func send(_ rows: [LibraryChange]) {
        guard !rows.isEmpty else { return }
        rowChannel?.send(rows)
    }

    /// Tells the app once that the camera is at rest: no gesture and no animation (D-53).
    private func cameraMayRest() {
        let isGestureActive = [panRecognizer, pinchRecognizer].contains {
            $0.state == .began || $0.state == .changed
        }
        guard isCameraMoving, !isGestureActive, !cameraController.isAnimating else { return }
        isCameraMoving = false
        // A flight of a card or a pinch-out exit leaves the camera outside the zoom range, and
        // the device state stores cameras of the range only (D-53).
        let camera = cameraController.shownCamera
        guard cardTransition == nil, parentLink.exit == nil, Limits.zoomRange.contains(camera.zoom)
        else { return }
        onCameraRest(camera)
    }

    /// The camera stops, and running finger gestures end (D-36). The selected tool becomes the
    /// tool of the touch (D-70).
    func pencilBegan() {
        if toolState.pencilDown() == .eraser, toolState.isErasingEnabled {
            beginErase()
        }
        hideHoverDot()
        palmGuard.pencilBegan()
        cameraController.stopAnimation()
        for recognizer in [panRecognizer, pinchRecognizer] where recognizer.state != .possible {
            recognizer.isEnabled = false
            recognizer.isEnabled = true
        }
    }

    /// Gives a pencil sample to a running eraser gesture.
    func pencilMoved(to location: Point) {
        lastPencilLocation = CGPoint(x: location.x, y: location.y)
        guard eraserSamples != nil else { return }
        addEraserSample(location)
    }

    /// Ends the pencil touch: the eraser gesture ends, and a tool picked during the touch becomes
    /// active.
    func pencilEnded(at time: TimeInterval, isCancelled: Bool) {
        palmGuard.pencilEnded(at: time)
        if eraserSamples != nil {
            finishErase(isCancelled: isCancelled)
        }
        toolState.pencilUp()
        applyToolState()
    }

    @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
        if dragsPendingCard(recognizer) { return }
        let translation = recognizer.translation(in: canvasView)
        recognizer.setTranslation(.zero, in: canvasView)
        guard pinchRecognizer.state == .possible || pinchRecognizer.state == .failed else { return }
        cameraController.pan(byView: Vector(dx: translation.x, dy: translation.y))
        if recognizer.state == .ended {
            let velocity = recognizer.velocity(in: canvasView)
            cameraController.endPan(velocity: Vector(dx: velocity.x, dy: velocity.y))
        }
        applyCamera()
        cameraMayRest()
    }

    @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        let location = recognizer.location(in: canvasView)
        let centroid = Point(x: location.x, y: location.y)
        switch recognizer.state {
        case .began:
            cameraController.beginPinch(centroid: centroid)
        case .changed where recognizer.numberOfTouches >= 2 && recognizer.scale > 0:
            cameraController.updatePinch(scale: recognizer.scale, centroid: centroid)
        case .ended, .cancelled, .failed:
            if cameraController.endPinch(canLeave: level > 0) { startPinchLeave() }
        default:
            return
        }
        applyCamera()
        updatePinchExit()
        cameraMayRest()
    }

    private func stepCamera(to time: TimeInterval) -> Bool {
        let isAnimating = cameraController.step(to: time)
        applyCamera()
        stepCardTransition()
        updatePinchExit()
        if !isAnimating { cameraMayRest() }
        return isAnimating
    }

    /// Sends the camera to the renderer and the matching pen width to the live canvas.
    private func applyCamera() {
        let camera = cameraController.shownCamera
        if camera != renderer.camera { isCameraMoving = true }
        if camera.zoom != renderer.camera.zoom {
            canvasView.liveCanvas.tool = PenTool.inkingTool(zoom: camera.zoom)
        }
        // During a flight, the render thread takes the camera from the flight itself (D-121).
        if cameraController.flightProgress == nil { renderer.camera = camera }
        textCameraDidChange(isPinching: isPinchActive)
        if cameraController.isAnimating {
            canvasView.inkView.requestFrame()
        }
    }
}

extension CanvasViewController: PKCanvasViewDelegate {
    /// Hands off each finished stroke.
    public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        handoff.drawingDidChange(camera: cameraController.shownCamera, viewSize: viewSize)
    }

    /// The pencil starts a live stroke. The removal of handed-off strokes waits.
    public func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        handoff.isToolInUse = true
    }

    /// The pencil lifted. Handed-off strokes can leave the drawing.
    public func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        handoff.isToolInUse = false
        guard let repository else { return }
        Task { await repository.requestSave() }
    }
}
