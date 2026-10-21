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

    /// A long press begins only on a text box (CARD-07, D-89).
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
}
