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

/// One grant of extra time, which ends once: at `end()`, or when the time runs out. The expiry
/// must end the task inside its handler, or the system stops the app (review after M9). Each
/// save and each restore has its own grant, so that the end of one never ends another (review
/// of 2026-10-24, section 3.2, item 3).
@MainActor
final class ExtraTime {
    private let time: any BackgroundTime
    private var task = UIBackgroundTaskIdentifier.invalid
    private var hasExpired = false

    /// Asks `time` for extra time. `onExpiry` runs first when the time runs out, and then the
    /// grant ends.
    init(
        _ name: String,
        time: any BackgroundTime,
        onExpiry: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.time = time
        // The handler keeps the grant until the system drops the handler at the end.
        task = time.begin(name) {
            onExpiry()
            self.expire()
        }
        // A test time can run out inside `begin`, before the task is known.
        if hasExpired { end() }
    }

    /// Ends the grant. A second call does nothing.
    func end() {
        guard task != .invalid else { return }
        time.end(task)
        task = .invalid
    }

    private func expire() {
        hasExpired = true
        end()
    }
}
