/// A value of the hybrid logical clock: wall time, a counter, and the device (data-model.md 4).
///
/// Values compare by `wallMillis`, then `counter`, then `device`.
public struct HybridTimestamp: Hashable, Comparable, Codable, Sendable {
    /// Milliseconds since 1970, from the device clock.
    public let wallMillis: UInt64
    /// Breaks ties within one millisecond.
    public let counter: UInt32
    /// Breaks ties between devices.
    public let device: DeviceID

    /// Makes a timestamp.
    public init(wallMillis: UInt64, counter: UInt32, device: DeviceID) {
        self.wallMillis = wallMillis
        self.counter = counter
        self.device = device
    }

    /// Orders timestamps by wall time, then counter, then device.
    public static func < (left: HybridTimestamp, right: HybridTimestamp) -> Bool {
        if left.wallMillis != right.wallMillis { return left.wallMillis < right.wallMillis }
        if left.counter != right.counter { return left.counter < right.counter }
        return left.device < right.device
    }
}
