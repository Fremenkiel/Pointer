import UIKit

/// The window of the app. It notes the time of the last touch, so the app can find an idle
/// moment for the daily snapshot (storage.md section 7.2).
final class InputTrackingWindow: UIWindow {
    /// The time of the last touch, on the clock of `UIEvent.timestamp`.
    private(set) var lastInputTime: TimeInterval = 0

    /// Notes the time of each touch event and passes the event on. It only stores one number,
    /// so it adds nothing to the touch path (PERF-01).
    override func sendEvent(_ event: UIEvent) {
        if event.type == .touches {
            lastInputTime = event.timestamp
        }
        super.sendEvent(event)
    }
}
