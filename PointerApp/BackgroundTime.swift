import UIKit

/// The extra time of the system for work that must end in the background, such as a restore
/// (D-164). Tests give their own, because a test cannot make the time of the system run out.
@MainActor
protocol BackgroundTime {
    /// Asks for extra time. `onExpiry` runs on the main actor when the time runs out, and the
    /// work must end within about 1 s then.
    ///
    /// - Returns: The task to end, or `.invalid` if the system gives no time.
    func begin(
        _ name: String,
        onExpiry: @escaping @MainActor @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier

    /// Ends the extra time of `task`. An invalid task does nothing.
    func end(_ task: UIBackgroundTaskIdentifier)
}

/// The extra time of `UIApplication`, about 30 s
/// (<https://developer.apple.com/forums/thread/85066>).
struct SystemBackgroundTime: BackgroundTime {
    func begin(
        _ name: String,
        onExpiry: @escaping @MainActor @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(withName: name) {
            MainActor.assumeIsolated { onExpiry() }
        }
    }

    func end(_ task: UIBackgroundTaskIdentifier) {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
    }
}
