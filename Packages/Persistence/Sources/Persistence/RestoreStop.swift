import os

/// The stop flag of a restore (D-164). The app sets it from any thread, for example at the end
/// of the extra time in the background, while the repository copies. The repository reads it
/// between two steps.
public final class RestoreStop: Sendable {
    private let state: OSAllocatedUnfairLock<State>

    private struct State {
        var isStopped = false
        /// The reads before the flag sets itself, or `nil`. Only tests set it.
        var readsBeforeStop: Int?
    }

    /// Makes a flag that is not set.
    public init() {
        state = OSAllocatedUnfairLock(initialState: State())
    }

    /// Makes a flag that sets itself at the read after `reads` reads, so that a test can stop a
    /// restore in the middle.
    ///
    /// - Precondition: `reads` is not negative.
    init(stopsAfterReads reads: Int) {
        precondition(reads >= 0, "A stop after \(reads) reads")
        state = OSAllocatedUnfairLock(initialState: State(readsBeforeStop: reads))
    }

    /// Asks the restore to stop at its next step.
    public func stop() {
        state.withLock { $0.isStopped = true }
    }

    /// True after `stop()`.
    public var isStopped: Bool {
        state.withLock { state in
            if let reads = state.readsBeforeStop {
                state.isStopped = state.isStopped || reads == 0
                state.readsBeforeStop = max(reads - 1, 0)
            }
            return state.isStopped
        }
    }
}
