import Foundation

/// The ID of a stroke.
public struct StrokeID: EntityIdentifier {
    /// The UUID of the stroke.
    public let rawValue: UUID

    /// Makes an ID from a UUID.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}
