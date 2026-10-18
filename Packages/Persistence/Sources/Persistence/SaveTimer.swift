/// The monotonic time and the sleep of the save throttle. Tests inject a manual timer (TEST-04).
public protocol SaveTimer: Sendable {
    /// The time since an arbitrary start. It never goes back.
    func now() -> Duration

    /// Returns at `deadline`, or throws `CancellationError` if the task is cancelled.
    func sleep(until deadline: Duration) async throws
}

/// The save timer of the app, on `ContinuousClock`.
public struct ContinuousSaveTimer: SaveTimer {
    private let clock = ContinuousClock()
    private let start: ContinuousClock.Instant

    /// Makes a timer that starts now.
    public init() {
        start = clock.now
    }

    /// The time since the start of the timer.
    public func now() -> Duration {
        start.duration(to: clock.now)
    }

    /// Returns at `deadline`, or throws `CancellationError` if the task is cancelled.
    public func sleep(until deadline: Duration) async throws {
        try await clock.sleep(until: start.advanced(by: deadline))
    }
}
