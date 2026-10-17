import Foundation

/// The ID of a canvas. It equals the ID of its workspace or its card.
public struct CanvasID: EntityIdentifier {
    /// The UUID of the canvas.
    public let rawValue: UUID

    /// Makes an ID from a UUID.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}
