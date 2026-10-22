/// The undo and redo lists of one canvas (architecture.md section 8, D-12).
///
/// The history lives in memory while the app runs. It holds at most `Limits.maxHistoryDepth`
/// steps and at most `pointBudget` control points (D-76), and drops the oldest step first. A new
/// command clears the redo list.
public struct History: Sendable {
    /// The result of a new step: the changed rows and the oldest steps that the history dropped.
    public struct Performed: Sendable {
        /// The changed rows for the repository.
        public let changes: [LibraryChange]
        /// The steps that left the history, the oldest first. Their session erase records can go
        /// (D-76).
        public let dropped: [any CanvasCommand]
    }

    /// The steps that an undo can revert, the newest last.
    public private(set) var undoSteps: [any CanvasCommand] = []
    /// The steps that a redo can apply again, the newest undo last.
    public private(set) var redoSteps: [any CanvasCommand] = []
    /// The control points of all steps (D-76).
    public private(set) var pointCount = 0
    /// The most control points that the steps hold.
    public let pointBudget: Int

    /// Makes an empty history.
    ///
    /// - Precondition: `pointBudget` is not negative.
    public init(pointBudget: Int = Limits.maxHistoryPointsPerCanvas) {
        precondition(pointBudget >= 0, "A point budget is not negative, got \(pointBudget)")
        self.pointBudget = pointBudget
    }

    /// True if an undo has a step to revert.
    public var canUndo: Bool { !undoSteps.isEmpty }

    /// True if a redo has a step to apply again.
    public var canRedo: Bool { !redoSteps.isEmpty }

    /// Applies a new command and records it as the newest undo step. Past the step limit or the
    /// point budget, the oldest steps go, also the new one if it alone passes the budget.
    ///
    /// - Throws: The `CommandError` of `apply`. The history and the content then stay as they
    ///   were.
    /// - Returns: The changed rows and the dropped steps.
    public mutating func perform(
        _ command: any CanvasCommand,
        on content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> Performed {
        let changes = try command.apply(to: &content, clock: &clock)
        var dropped = redoSteps
        pointCount -= redoSteps.reduce(0) { $0 + $1.heldPointCount }
        redoSteps.removeAll()
        if undoSteps.count == Limits.maxHistoryDepth {
            pointCount -= undoSteps[0].heldPointCount
            dropped.append(undoSteps.removeFirst())
        }
        undoSteps.append(command)
        pointCount += command.heldPointCount
        dropped += dropOldest(toFit: pointBudget)
        assert(undoSteps.count <= Limits.maxHistoryDepth, "History over its depth")
        assert(pointCount <= pointBudget, "History over its point budget")
        return Performed(changes: changes, dropped: dropped)
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

    /// Drops the oldest steps until the history holds at most `budget` control points. The
    /// oldest undo steps go first, then the redo steps from the oldest one.
    ///
    /// - Precondition: `budget` is not negative.
    /// - Returns: The dropped steps, the oldest first.
    public mutating func dropOldest(toFit budget: Int) -> [any CanvasCommand] {
        precondition(budget >= 0, "A point budget is not negative, got \(budget)")
        guard pointCount > budget else { return [] }
        var undoDrops = 0
        for step in undoSteps where pointCount > budget {
            pointCount -= step.heldPointCount
            undoDrops += 1
        }
        var dropped = Array(undoSteps.prefix(undoDrops))
        undoSteps.removeFirst(undoDrops)
        // The redo list holds the newest step first, so its oldest step is the last one.
        for step in redoSteps.reversed() where pointCount > budget {
            pointCount -= step.heldPointCount
            dropped.append(step)
        }
        redoSteps.removeLast(dropped.count - undoDrops)
        assert(pointCount <= budget, "The history still passes \(budget) points")
        return dropped
    }

    /// Returns the IDs of the strokes of `dropped` that no step of this history holds. Their
    /// session erase records can go (D-76).
    public func unheldStrokeIDs(of dropped: [any CanvasCommand]) -> [StrokeID] {
        guard !dropped.isEmpty else { return [] }
        // The dropped steps hold few strokes and the kept steps many, so only the dropped IDs
        // go into a set. On a full history with 4 erases of the D-69 size, a set of all held IDs
        // took 1.19 ms per call, and this form 0.39 ms (Mac, Release, 2026-10-22).
        var unheld = Set<StrokeID>()
        for step in dropped {
            step.forEachHeldStroke { unheld.insert($0) }
        }
        for step in undoSteps where !unheld.isEmpty {
            step.forEachHeldStroke { unheld.remove($0) }
        }
        for step in redoSteps where !unheld.isEmpty {
            step.forEachHeldStroke { unheld.remove($0) }
        }
        var result: [StrokeID] = []
        for step in dropped {
            step.forEachHeldStroke { if unheld.contains($0) { result.append($0) } }
        }
        assert(result.count >= unheld.count, "Each unheld stroke is in the result")
        return result
    }
}
