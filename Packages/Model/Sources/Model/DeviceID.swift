import Foundation

/// The ID of a device. The hybrid clock uses it to break ties between devices.
public struct DeviceID: EntityIdentifier {
    /// The UUID of the device.
    public let rawValue: UUID

    /// Makes an ID from a UUID.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}
