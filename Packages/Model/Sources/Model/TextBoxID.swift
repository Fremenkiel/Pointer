import Foundation

/// The ID of a text box.
public struct TextBoxID: EntityIdentifier {
    /// The UUID of the text box.
    public let rawValue: UUID

    /// Makes an ID from a UUID.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}
