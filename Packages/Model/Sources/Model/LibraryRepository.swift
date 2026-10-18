/// The store of the library: all workspaces and their canvases (storage.md sections 4 and 5).
///
/// `Persistence` implements it. Features get it through their initializers (ARCH-05).
public protocol LibraryRepository: Actor {
    /// Returns the live workspaces, ordered by sort key and then by ID.
    ///
    /// - Throws: `ModelError.storageFailed` if the read fails.
    func workspaces() throws(ModelError) -> [Workspace]

    /// Writes a new workspace at once.
    ///
    /// - Precondition: `workspace` is not a tombstone, and its ID is new.
    /// - Throws: `ModelError.workspaceLimitReached` at `Limits.maxWorkspaces` live workspaces,
    ///   `ModelError.libraryIsReadOnly`, or `ModelError.storageFailed`.
    func create(_ workspace: Workspace) throws(ModelError)

    /// Gives a workspace a new title at once. The title is trimmed.
    ///
    /// - Throws: `ModelError.invalidTitle`, `ModelError.libraryIsReadOnly`, or
    ///   `ModelError.storageFailed`.
    func rename(_ id: WorkspaceID, to title: String, modified: HybridTimestamp) throws(ModelError)

    /// Marks a workspace as deleted at once. The row stays as a tombstone (data-model.md 5).
    ///
    /// - Throws: `ModelError.libraryIsReadOnly` or `ModelError.storageFailed`.
    func delete(_ id: WorkspaceID, modified: HybridTimestamp) throws(ModelError)

    /// Returns the live content of one canvas: no tombstones and no erased strokes.
    ///
    /// - Throws: `ModelError.storageFailed` if the read fails, or a limit error if the stored
    ///   content is above a limit of `Limits`.
    func content(of canvasID: CanvasID) throws(ModelError) -> CanvasContent

    /// Adds changed rows to the pending set. A later save writes them (D-27).
    ///
    /// - Throws: `ModelError.libraryIsReadOnly` if the library has a newer schema.
    func send(_ changes: [LibraryChange]) throws(ModelError)
}
