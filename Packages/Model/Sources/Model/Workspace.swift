import Foundation

/// A named top-level entry of the library that owns one root canvas (data-model.md 7.1).
public struct Workspace: Identifiable, Hashable, Sendable {
    /// The ID of the workspace and of its root canvas.
    public let id: WorkspaceID
    /// The clock values and the tombstone flag.
    public let meta: RecordMeta
    /// The title, trimmed, with 1 to `Limits.maxTitleLength` code points.
    public let title: String
    /// The position of the workspace in the selector.
    public let sortKey: FractionalIndex

    /// Makes a workspace with a trimmed title.
    ///
    /// - Throws: `ModelError.invalidTitle` if the trimmed title has a length outside
    ///   `1...Limits.maxTitleLength` code points.
    public init(
        id: WorkspaceID,
        meta: RecordMeta,
        title: String,
        sortKey: FractionalIndex
    ) throws(ModelError) {
        self.id = id
        self.meta = meta
        self.title = try Self.validatedTitle(title)
        self.sortKey = sortKey
    }

    /// The ID of the root canvas.
    public var canvasID: CanvasID { CanvasID(id) }

    /// Returns the title without white space and line breaks at its ends.
    ///
    /// - Throws: `ModelError.invalidTitle` if the trimmed title has a length outside
    ///   `1...Limits.maxTitleLength` code points (D-57).
    public static func validatedTitle(_ title: String) throws(ModelError) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let length = TextLength.of(trimmed)
        guard length >= 1, length <= Limits.maxTitleLength else {
            throw .invalidTitle(length: length)
        }
        return trimmed
    }
}
