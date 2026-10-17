import Foundation
import Testing
import os

@testable import Model

/// A wall clock that returns the times of a list, then the last time again.
final class ScriptedWallClock: WallClock {
    let times: [UInt64]
    let index = OSAllocatedUnfairLock(initialState: 0)

    init(_ times: [UInt64]) { self.times = times }

    func nowMillis() -> UInt64 {
        index.withLock { position in
            defer { position += 1 }
            return times[min(position, times.count - 1)]
        }
    }
}

@Suite("Hybrid logical clock")
struct HybridClockTests {
    @Test("A later wall time gives counter zero")
    func laterWall() {
        var clock = HybridClock(device: Fixtures.device, wallClock: ScriptedWallClock([10, 20]))
        #expect(clock.now() == HybridTimestamp(wallMillis: 10, counter: 0, device: Fixtures.device))
        #expect(clock.now() == HybridTimestamp(wallMillis: 20, counter: 0, device: Fixtures.device))
    }

    @Test("A wall time that goes back still gives a greater value")
    func wallGoesBack() {
        var clock = HybridClock(
            device: Fixtures.device,
            wallClock: ScriptedWallClock([50, 40, 40])
        )
        let first = clock.now()
        let second = clock.now()
        let third = clock.now()
        #expect(second == HybridTimestamp(wallMillis: 50, counter: 1, device: Fixtures.device))
        #expect(third == HybridTimestamp(wallMillis: 50, counter: 2, device: Fixtures.device))
        #expect(first < second && second < third)
    }

    @Test("A full counter moves to the next millisecond")
    func counterOverflow() {
        let last = HybridTimestamp(wallMillis: 5, counter: .max, device: Fixtures.device)
        var clock = HybridClock(
            device: Fixtures.device,
            wallClock: FixedWallClock(millis: 5),
            last: last
        )
        #expect(clock.now() == HybridTimestamp(wallMillis: 6, counter: 0, device: Fixtures.device))
        #expect(clock.last.wallMillis == 6)
    }

    @Test("Timestamps compare by wall time, counter, then device")
    func comparison() {
        let other = DeviceID(rawValue: UUID(uuid: (9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
        let base = HybridTimestamp(wallMillis: 1, counter: 1, device: Fixtures.device)
        #expect(base < HybridTimestamp(wallMillis: 2, counter: 0, device: Fixtures.device))
        #expect(base < HybridTimestamp(wallMillis: 1, counter: 2, device: Fixtures.device))
        #expect(base < HybridTimestamp(wallMillis: 1, counter: 1, device: other))
        #expect(!(base < base))
    }
}
