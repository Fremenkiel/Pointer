/// Makes hybrid logical clock values that always grow on one device (data-model.md section 4).
///
/// A change of the system time does not make the clock go back. Source: Kulkarni et al.,
/// "Logical Physical Clocks".
public struct HybridClock: Sendable {
    /// The device that makes the values.
    public let device: DeviceID
    /// The last value that the clock made. The device state stores it from M3 on.
    public private(set) var last: HybridTimestamp
    private let wallClock: any WallClock

    /// Makes a clock that continues after `last`.
    ///
    /// - Precondition: `last` belongs to `device`.
    public init(device: DeviceID, wallClock: any WallClock, last: HybridTimestamp? = nil) {
        let start = last ?? HybridTimestamp(wallMillis: 0, counter: 0, device: device)
        precondition(start.device == device, "Clock of \(device) cannot continue \(start.device)")
        self.device = device
        self.wallClock = wallClock
        self.last = start
    }

    /// Returns a new value that is greater than each value before it.
    public mutating func now() -> HybridTimestamp {
        let wall = wallClock.nowMillis()
        let next: HybridTimestamp
        if wall > last.wallMillis {
            next = HybridTimestamp(wallMillis: wall, counter: 0, device: device)
        } else if last.counter < UInt32.max {
            next = HybridTimestamp(
                wallMillis: last.wallMillis,
                counter: last.counter + 1,
                device: device
            )
        } else {
            next = HybridTimestamp(wallMillis: last.wallMillis + 1, counter: 0, device: device)
        }
        assert(next > last, "Clock value \(next) is not greater than \(last)")
        assert(next.device == device, "Clock value belongs to another device")
        last = next
        return next
    }
}
