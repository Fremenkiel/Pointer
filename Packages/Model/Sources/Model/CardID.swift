import Foundation

/// The ID of a card. Its child canvas has the same ID.
public struct CardID: EntityIdentifier {
    /// The UUID of the card.
    public let rawValue: UUID

    /// Makes an ID from a UUID.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}
