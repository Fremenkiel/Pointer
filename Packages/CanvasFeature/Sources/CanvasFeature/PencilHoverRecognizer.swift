import UIKit

/// The hover recognizer of the dot (architecture.md 4.6). It is its own delegate, as
/// `PencilTouchObserver` is, so that the touch rules of the canvas do not apply to it: UIKit
/// delivers a hover as a pencil touch, and the canvas refuses pencil touches for its finger
/// gestures. It recognizes together with every other recognizer, also the hover recognizers of
/// UIKit and PencilKit, so it blocks no gesture.
@MainActor
final class PencilHoverRecognizer: UIHoverGestureRecognizer, UIGestureRecognizerDelegate {
    /// Makes a recognizer of pencil hovers that sends its action to `target`.
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        delegate = self
    }

    /// The dot follows the pencil during every other gesture.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
