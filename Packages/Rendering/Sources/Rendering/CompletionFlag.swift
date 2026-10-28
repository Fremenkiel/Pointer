import Synchronization

/// A flag that a completed handler of a command buffer sets from the thread of Metal, and that
/// a frame reads under its lock (review of 2026-10-28, 3.2.13).
final class CompletionFlag: Sendable {
    private let state = Mutex(false)

    /// Makes a flag that is not set.
    init() {}

    /// `true` after `set()`.
    var isSet: Bool { state.withLock { $0 } }

    /// Sets the flag. A second set changes nothing.
    func set() {
        state.withLock { $0 = true }
    }
}
