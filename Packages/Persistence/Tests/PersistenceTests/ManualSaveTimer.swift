import Foundation
import Model
import os

@testable import Persistence

/// A save timer that moves only when the test calls `advance(by:)` (TEST-04).
final class ManualSaveTimer: SaveTimer {
    private struct Sleeper {
        let id: UUID
        let deadline: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now: Duration = .zero
        var sleepers: [Sleeper] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func now() -> Duration {
        state.withLock { $0.now }
    }

    func sleep(until deadline: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let isDue = state.withLock { state in
                    guard state.now < deadline else { return true }
                    state.sleepers.append(
                        Sleeper(id: id, deadline: deadline, continuation: continuation)
                    )
                    return false
                }
                if isDue { continuation.resume() }
            }
        } onCancel: {
            let sleeper = state.withLock { state in
                state.sleepers.firstIndex { $0.id == id }.map { state.sleepers.remove(at: $0) }
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves the time and wakes each sleeper whose deadline has come.
    func advance(by duration: Duration) {
        let due = state.withLock { state in
            state.now += duration
            let now = state.now
            let due = state.sleepers.filter { $0.deadline <= now }
            state.sleepers.removeAll { $0.deadline <= now }
            return due
        }
        for sleeper in due { sleeper.continuation.resume() }
    }
}

/// A wall clock with a fixed time (TEST-04).
struct FixedWallClock: WallClock {
    let millis: UInt64

    func nowMillis() -> UInt64 { millis }
}
