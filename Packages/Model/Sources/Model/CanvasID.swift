import Foundation

/// The ID of a canvas. It equals the ID of its workspace or its card.
public struct CanvasID: EntityIdentifier {
    /// The UUID of the canvas.
    public let rawValue: UUID

    /// Makes an ID from a UUID.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// Makes the ID of the root canvas of a workspace.
    public init(_ workspace: WorkspaceID) {
        self.rawValue = workspace.rawValue
    }

    /// Makes the ID of the child canvas of a card.
    public init(_ card: CardID) {
        self.rawValue = card.rawValue
    }
}
