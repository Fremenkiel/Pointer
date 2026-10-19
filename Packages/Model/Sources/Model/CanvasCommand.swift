/// One user action on a canvas that the history can undo and redo (architecture.md section 8).
///
/// `revert` after `apply` gives back the live content of before `apply`. The erase records of the
/// session stay as tombstones (D-67). A command checks the content before it changes it, so a
/// thrown error leaves the content as it was. Commands never touch disk: the canvas sends the
/// returned rows to the repository.
public protocol CanvasCommand: Sendable {
    /// Does the action, or does it again after an undo.
    ///
    /// - Throws: `CommandError` if the content does not allow the action. The content then
    ///   stays as it was.
    /// - Returns: The changed rows for the repository.
    func apply(
        to content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange]

    /// Undoes the action.
    ///
    /// - Throws: `CommandError` if the content does not allow the undo. The content then stays
    ///   as it was.
    /// - Returns: The changed rows for the repository.
    func revert(
        on content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange]
}
