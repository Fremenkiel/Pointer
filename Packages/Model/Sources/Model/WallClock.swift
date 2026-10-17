import Foundation

/// A source of the wall-clock time. Tests inject a fixed clock (TEST-04).
public protocol WallClock: Sendable {
    /// The current time in milliseconds since 1970.
    func nowMillis() -> UInt64
}

/// The wall clock of the device.
public struct SystemWallClock: WallClock {
    /// Makes the clock.
    public init() {}

    /// The current time of the device in milliseconds since 1970. A time before 1970 gives 0.
    public func nowMillis() -> UInt64 {
        let millis = (Date().timeIntervalSince1970 * 1000).rounded(.down)
        guard millis > 0, let value = UInt64(exactly: millis) else { return 0 }
        return value
    }
}
