import UIKit

/// A tap recognizer that notes the time of the last finger lift, so that the canvas can log the
/// wait of a single tap on a card for the double tap (m6-plan.md task 4.3, D-100).
final class LiftTimedTap: UITapGestureRecognizer {
    /// The time of the last lift in the clock of `CACurrentMediaTime()`, or `nil`.
    private(set) var liftTime: TimeInterval?

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        liftTime = event.timestamp
        super.touchesEnded(touches, with: event)
    }
}
