import Foundation

/// The ID of a workspace. Its root canvas has the same ID.
public struct WorkspaceID: EntityIdentifier {
    /// The UUID of the workspace.
    public let rawValue: UUID

    /// Makes an ID from a UUID.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}
