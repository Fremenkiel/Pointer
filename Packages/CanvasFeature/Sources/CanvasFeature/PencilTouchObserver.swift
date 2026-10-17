import QuartzCore
import UIKit

/// Reports pencil touches to the palm guard without taking part in gesture recognition.
///
/// It never recognizes, it does not cancel or delay touches, and it recognizes together with
/// every other gesture recognizer, so the drawing recognizer of PencilKit is not affected.
@MainActor
final class PencilTouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    /// Called when a pencil touch begins.
    var onBegan: (() -> Void)?
    /// Called with the touch time when a pencil touch ends or is cancelled.
    var onEnded: ((TimeInterval) -> Void)?
    private var trackedTouches = 0

    /// Makes an observer.
    init() {
        super.init(target: nil, action: nil)
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    /// Reports each new pencil touch.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        trackedTouches += touches.count
        for _ in touches {
            onBegan?()
        }
    }

    /// Reports each pencil touch that ended.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches)
    }

    /// Reports each pencil touch that was cancelled.
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches)
    }

    /// Ends the pencil touches that UIKit did not report, for example after it failed the
    /// observer while a pencil touched. Without this, the palm guard can stay in the pencil
    /// state, and the finger gestures stop working. `UITouch.timestamp` uses the same clock as
    /// `CACurrentMediaTime()`.
    override func reset() {
        super.reset()
        for _ in 0..<trackedTouches {
            onEnded?(CACurrentMediaTime())
        }
        trackedTouches = 0
    }

    /// The observer works next to every other recognizer.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    private func finish(_ touches: Set<UITouch>) {
        for touch in touches {
            onEnded?(touch.timestamp)
        }
        trackedTouches = max(0, trackedTouches - touches.count)
        if trackedTouches == 0 {
            state = .failed
        }
    }
}
