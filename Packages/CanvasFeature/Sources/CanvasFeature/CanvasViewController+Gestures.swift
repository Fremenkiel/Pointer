import Geometry
import Model
import UIKit

/// The gesture rules of the canvas: the palm guard, the text recognizers, and the pan with the
/// pinch (architecture.md 4.1, D-90).
extension CanvasViewController: UIGestureRecognizerDelegate {
    /// The palm guard filters the finger touches of pan and pinch (architecture.md 4.1).
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        // The text recognizers take only the touches on the canvas surface, not on the edit
        // view or the buttons (D-90, F-06).
        let isTextRecognizer =
            gestureRecognizer === textEditing.pencilTap
            || gestureRecognizer === textEditing.fingerTap
            || gestureRecognizer === textEditing.longPress
        if isTextRecognizer, !(touch.view.map(canvasView.isSurface) ?? false) { return false }
        if gestureRecognizer === textEditing.pencilTap { return touch.type == .pencil }
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

    /// A long press begins while editing is on (CARD-01, CARD-07).
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === textEditing.longPress else { return true }
        return longPressCanBegin(gestureRecognizer)
    }

    /// Pan and pinch run together, so a second finger can join a pan.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // An identity check, without a set per call (C-05).
        let first = gestureRecognizer === panRecognizer || gestureRecognizer === pinchRecognizer
        let second =
            otherGestureRecognizer === panRecognizer || otherGestureRecognizer === pinchRecognizer
        return first && second
    }

    /// `true` while a pinch runs. The edit view then scales until the pinch ends (D-85).
    var isPinchActive: Bool {
        pinchRecognizer.state == .began || pinchRecognizer.state == .changed
    }

    /// `true` if a recognizer takes finger touches. An empty list of touch types takes all.
    static func takesFingerTouches(_ recognizer: UIGestureRecognizer) -> Bool {
        let types = recognizer.allowedTouchTypes
        return types.isEmpty || types.contains(NSNumber(value: UITouch.TouchType.direct.rawValue))
    }

    /// A recognizer of PencilKit that takes finger touches waits for the finger tap and the long
    /// press of the canvas to fail. The selection of PencilKit, which Pointer does not use (D-10),
    /// took a finger tap on a box and ended the focus of the edit view 0.35 s later (manual test
    /// 4 of the M5 plan section 5.6). The drawing of the pencil waits for nothing.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        let isOwn =
            gestureRecognizer === textEditing.fingerTap
            || gestureRecognizer === textEditing.longPress
        guard isOwn, let view = otherGestureRecognizer.view,
            view.isDescendant(of: canvasView.liveCanvas)
        else { return false }
        return Self.takesFingerTouches(otherGestureRecognizer)
    }

    /// Adds the pan, the pinch, and the pencil observer to the canvas view.
    func installGestures() {
        panRecognizer.maximumNumberOfTouches = 1
        for recognizer in [panRecognizer, pinchRecognizer] as [UIGestureRecognizer] {
            recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            recognizer.delegate = self
            canvasView.addGestureRecognizer(recognizer)
        }
        panRecognizer.addTarget(self, action: #selector(handlePan(_:)))
        pinchRecognizer.addTarget(self, action: #selector(handlePinch(_:)))
        pencilObserver.onBegan = { [weak self] in self?.pencilBegan() }
        pencilObserver.onSample = { [weak self] location in
            self?.pencilMoved(to: Point(x: location.x, y: location.y))
        }
        pencilObserver.onEnded = { [weak self] time, isCancelled in
            self?.pencilEnded(at: time, isCancelled: isCancelled)
        }
        // The history buttons lie inside the canvas view, so their touches reach it too (F-06).
        // Weak, because the canvas view holds the observer (a strong capture leaked the canvas).
        pencilObserver.isSurface = { [weak canvasView] in canvasView?.isSurface($0) ?? false }
        canvasView.addGestureRecognizer(pencilObserver)
    }

    /// Moves the camera with a finger pan, or drags the pending card.
    @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
        if dragsPendingCard(recognizer) { return }
        let translation = recognizer.translation(in: canvasView)
        recognizer.setTranslation(.zero, in: canvasView)
        // A pan would stop the flight of an open or a leave, which then ends too early.
        guard !isInCardTransition else { return }
        guard pinchRecognizer.state == .possible || pinchRecognizer.state == .failed else { return }
        cameraController.pan(byView: Vector(dx: translation.x, dy: translation.y))
        if recognizer.state == .ended {
            let velocity = recognizer.velocity(in: canvasView)
            cameraController.endPan(velocity: Vector(dx: velocity.x, dy: velocity.y))
        }
        applyCamera()
        cameraMayRest(after: recognizer)
    }

    /// Zooms the camera with a pinch, and ends a pinch-out exit at the lift.
    @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        let location = recognizer.location(in: canvasView)
        let centroid = Point(x: location.x, y: location.y)
        switch recognizer.state {
        // A pinch during the flight of an open or a leave would stop the flight.
        case .began where !isInCardTransition:
            cameraController.beginPinch(centroid: centroid)
        case .changed
        where recognizer.numberOfTouches >= 2 && recognizer.scale > 0 && !isInCardTransition:
            cameraController.updatePinch(scale: recognizer.scale, centroid: centroid)
        case .ended, .cancelled, .failed:
            endPinchGesture()
        default:
            return
        }
        applyCamera()
        updatePinchExit()
        cameraMayRest(after: recognizer)
    }

    /// Ends a pinch: inside a card, a lift under the threshold leaves the card (CARD-05), and a
    /// zoom past a limit springs back (CARD-06). While the pencil touches, the spring waits for
    /// the end of the stroke, so that the camera stays under the pencil (D-135).
    func endPinchGesture() {
        if cameraController.endPinch(canLeave: level > 0) {
            startPinchLeave()
            return
        }
        if toolState.isPencilDown { cameraController.holdSpring() }
    }

    /// Starts a spring back that waited for the end of a pencil stroke (D-135).
    func releaseHeldSpring() {
        guard cameraController.isSpringHeld else { return }
        cameraController.releaseSpring()
        canvasView.inkView.requestFrame()
    }
}
