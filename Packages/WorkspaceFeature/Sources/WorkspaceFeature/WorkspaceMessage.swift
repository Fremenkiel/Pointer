import Model

/// A message that the selector shows to the user.
public enum WorkspaceMessage: Equatable, Sendable {
    /// The library holds `Limits.maxWorkspaces` workspaces.
    case limitReached
    /// A title is empty after the trim, too long, or holds U+0000.
    case invalidTitle
    /// The library has a newer schema and opens read-only.
    case readOnly
    /// The storage failed.
    case storageFailed

    /// Returns the message of a model error.
    init(_ error: ModelError) {
        switch error {
        case .workspaceLimitReached: self = .limitReached
        case .invalidTitle, .nullCharacter: self = .invalidTitle
        case .libraryIsReadOnly: self = .readOnly
        default: self = .storageFailed
        }
    }

    /// The text of the message.
    var text: String {
        switch self {
        case .limitReached: WorkspaceStrings.limitReached
        case .invalidTitle: WorkspaceStrings.invalidTitle
        case .readOnly: WorkspaceStrings.readOnly
        case .storageFailed: WorkspaceStrings.storageFailed
        }
    }
}
