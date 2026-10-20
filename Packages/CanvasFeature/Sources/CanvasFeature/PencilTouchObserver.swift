import QuartzCore
import UIKit

/// Reports pencil touches to the palm guard and the samples of each touch to the eraser,
/// without taking part in gesture recognition (D-34).
///
/// It never recognizes, it does not cancel or delay touches, and it recognizes together with
/// every other gesture recognizer, so the drawing recognizer of PencilKit is not affected.
@MainActor
final class PencilTouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    /// Called when a pencil touch begins.
    var onBegan: (() -> Void)?
    /// Called with each sample of a pencil touch in the coordinates of the view, the coalesced
    /// samples included.
    var onSample: ((CGPoint) -> Void)?
    /// Called with the touch time when a pencil touch ends, and `true` if UIKit cancelled it.
    var onEnded: ((TimeInterval, Bool) -> Void)?
    /// `true` while an erase runs. Only then does a move report the coalesced samples. Otherwise
    /// it reports the last location, the only one that the canvas uses then (C-06).
    var reportsCoalescedSamples = false
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
        for touch in touches {
            onBegan?()
            onSample?(touch.location(in: view))
        }
    }

    /// Reports the samples of each moved pencil touch.
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            report(touch, event: event)
        }
    }

    /// Reports the last samples and the end of each pencil touch.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            report(touch, event: event)
        }
        finish(touches, isCancelled: false)
    }

    /// Reports each pencil touch that was cancelled.
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches, isCancelled: true)
    }

    /// Ends the pencil touches that UIKit did not report, for example after it failed the
    /// observer while a pencil touched. Without this, the palm guard can stay in the pencil
    /// state, and the finger gestures stop working. `UITouch.timestamp` uses the same clock as
    /// `CACurrentMediaTime()`.
    override func reset() {
        super.reset()
        for _ in 0..<trackedTouches {
            onEnded?(CACurrentMediaTime(), true)
        }
        trackedTouches = 0
    }

    /// Returns `true` for a view whose pencil touches the observer takes, or `nil` to take all.
    /// The canvas sets it, so that a touch on a button reaches no tool (F-06).
    var isSurface: ((UIView) -> Bool)?

    /// Returns `true` if the observer takes a pencil touch on `view`.
    func receivesTouch(in view: UIView?) -> Bool {
        guard let view else { return false }
        return isSurface?(view) ?? true
    }

    /// Takes only the touches on the canvas surfaces, not on the buttons above them (F-06).
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        receivesTouch(in: touch.view)
    }

    /// The observer works next to every other recognizer.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    /// Reports the coalesced samples of a touch during an erase, or else the touch itself.
    private func report(_ touch: UITouch, event: UIEvent) {
        guard let onSample else { return }
        guard reportsCoalescedSamples else {
            onSample(touch.location(in: view))
            return
        }
        let samples = event.coalescedTouches(for: touch) ?? [touch]
        for sample in samples {
            onSample(sample.location(in: view))
        }
    }

    private func finish(_ touches: Set<UITouch>, isCancelled: Bool) {
        for touch in touches {
            onEnded?(touch.timestamp, isCancelled)
        }
        trackedTouches = max(0, trackedTouches - touches.count)
        if trackedTouches == 0 {
            state = .failed
        }
    }
}
