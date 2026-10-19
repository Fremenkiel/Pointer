/// Adds the strokes of one pen path (architecture.md section 8).
///
/// A path above `Limits.maxPointsPerStroke` control points gives several strokes, and they form
/// one undo step. The undo removes the strokes and writes an erase record for each one. A redo
/// turns these records into tombstones (D-68).
public struct AddStroke: CanvasCommand {
    /// The strokes of the path, in drawing order.
    public let strokes: [Stroke]

    /// Makes the command.
    ///
    /// - Precondition: 1 or more strokes, each with its own ID.
    public init(strokes: [Stroke]) {
        precondition(!strokes.isEmpty, "AddStroke needs a stroke")
        precondition(
            Set(strokes.map(\.id)).count == strokes.count,
            "AddStroke holds a stroke twice"
        )
        self.strokes = strokes
    }

    /// Adds the strokes. A first apply returns the stroke rows, and a redo returns the
    /// tombstones of their erase records.
    ///
    /// - Precondition: The strokes belong to the canvas of `content`.
    /// - Throws: `CommandError.strokeAlreadyLive` if a stroke is live, or
    ///   `CommandError.strokeLimitReached` if the strokes do not fit.
    /// - Returns: The changed rows.
    public func apply(
        to content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        for stroke in strokes where content.strokes[stroke.id] != nil {
            throw .strokeAlreadyLive(stroke.id)
        }
        guard content.strokes.count + strokes.count <= Limits.maxStrokesPerCanvas else {
            throw .strokeLimitReached
        }
        let time = clock.now()
        var changes: [LibraryChange] = []
        changes.reserveCapacity(strokes.count)
        for stroke in strokes {
            let tombstone: EraseRecord?
            do {
                tombstone = try content.restore(stroke, at: time, ignoringLimit: false)
            } catch {
                preconditionFailure("The limit check above failed for stroke \(stroke.id)")
            }
            changes.append(tombstone.map(LibraryChange.erase) ?? .stroke(stroke))
        }
        assert(changes.count == strokes.count, "Each stroke gives one row")
        return changes
    }

    /// Removes the strokes and writes a live erase record for each one.
    ///
    /// - Throws: `CommandError.strokeNotLive` if a stroke is not live.
    /// - Returns: The erase records.
    public func revert(
        on content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        for stroke in strokes where content.strokes[stroke.id] == nil {
            throw .strokeNotLive(stroke.id)
        }
        let time = clock.now()
        let changes = strokes.map { stroke in
            LibraryChange.erase(content.remove(stroke.id, at: time))
        }
        assert(changes.count == strokes.count, "Each stroke gives one erase record")
        return changes
    }
}
