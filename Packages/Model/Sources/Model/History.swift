/// The undo and redo lists of one canvas (architecture.md section 8, D-12).
///
/// The history lives in memory while the app runs. It holds at most `Limits.maxHistoryDepth`
/// steps and drops the oldest step first. A new command clears the redo list.
public struct History: Sendable {
    /// The steps that an undo can revert, the newest last.
    public private(set) var undoSteps: [any CanvasCommand] = []
    /// The steps that a redo can apply again, the newest undo last.
    public private(set) var redoSteps: [any CanvasCommand] = []

    /// Makes an empty history.
    public init() {}

    /// True if an undo has a step to revert.
    public var canUndo: Bool { !undoSteps.isEmpty }

    /// True if a redo has a step to apply again.
    public var canRedo: Bool { !redoSteps.isEmpty }

    /// Applies a new command and records it as the newest undo step.
    ///
    /// - Throws: The `CommandError` of `apply`. The history and the content then stay as they
    ///   were.
    /// - Returns: The changed rows for the repository.
    public mutating func perform(
        _ command: any CanvasCommand,
        on content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        let changes = try command.apply(to: &content, clock: &clock)
        if undoSteps.count == Limits.maxHistoryDepth {
            undoSteps.removeFirst()
        }
        undoSteps.append(command)
        redoSteps.removeAll()
        assert(undoSteps.count <= Limits.maxHistoryDepth, "History over its depth")
        return changes
    }

    /// Reverts the newest undo step and moves it to the redo list.
    ///
    /// - Throws: The `CommandError` of `revert`. The step then stays in the undo list.
    /// - Returns: The changed rows, or an empty list if no step exists.
    public mutating func undo(
        on content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        guard let command = undoSteps.last else { return [] }
        let changes = try command.revert(on: &content, clock: &clock)
        undoSteps.removeLast()
        redoSteps.append(command)
        assert(redoSteps.count <= Limits.maxHistoryDepth, "Redo list over the history depth")
        return changes
    }

    /// Applies the newest redo step again and moves it back to the undo list.
    ///
    /// - Throws: The `CommandError` of `apply`. The step then stays in the redo list.
    /// - Returns: The changed rows, or an empty list if no step exists.
    public mutating func redo(
        on content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        guard let command = redoSteps.last else { return [] }
        let changes = try command.apply(to: &content, clock: &clock)
        redoSteps.removeLast()
        undoSteps.append(command)
        assert(undoSteps.count <= Limits.maxHistoryDepth, "History over its depth")
        return changes
    }
}
