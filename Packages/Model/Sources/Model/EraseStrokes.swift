import Geometry

/// One eraser gesture: the strokes that it removed and the parts that it left (D-06, D-30).
///
/// The parts can take the canvas past `Limits.maxStrokesPerCanvas`, because an erase never
/// fails (D-71). The undo removes the parts with erase records and turns the erase records of the
/// removed strokes into tombstones (data-model.md 7.5).
public struct EraseStrokes: CanvasCommand {
    /// The strokes that the gesture cut or removed whole.
    public let removed: [Stroke]
    /// The new strokes outside the eraser circles.
    public let parts: [Stroke]
    /// The canvas area where the ink changes, or `nil` if it is not known. Outside it, the
    /// parts show the same ink as the removed strokes, so the renderer redraws only this area
    /// at the erase, its undo, and its redo (D-66).
    public let area: Rect?

    /// Makes the command.
    ///
    /// - Precondition: At least one removed stroke, and each stroke ID appears once.
    public init(removed: [Stroke], parts: [Stroke], area: Rect? = nil) {
        precondition(!removed.isEmpty, "EraseStrokes needs a removed stroke")
        precondition(
            Set(removed.map(\.id) + parts.map(\.id)).count == removed.count + parts.count,
            "EraseStrokes holds a stroke twice"
        )
        self.removed = removed
        self.parts = parts
        self.area = area
    }

    /// Removes the cut strokes and adds the parts. A first apply returns the rows of the new
    /// parts, and a redo returns the tombstones of their erase records.
    ///
    /// - Throws: `CommandError.strokeNotLive` if a removed stroke is not live, or
    ///   `CommandError.strokeAlreadyLive` if a part is live.
    /// - Returns: The erase records of the removed strokes and the rows of the parts.
    public func apply(
        to content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        for stroke in removed where content.strokes[stroke.id] == nil {
            throw .strokeNotLive(stroke.id)
        }
        for part in parts where content.strokes[part.id] != nil {
            throw .strokeAlreadyLive(part.id)
        }
        let time = clock.now()
        var changes: [LibraryChange] = []
        changes.reserveCapacity(removed.count + parts.count)
        for stroke in removed {
            changes.append(.erase(content.remove(stroke.id, at: time)))
        }
        for part in parts {
            let tombstone: EraseRecord?
            do {
                tombstone = try content.restore(part, at: time, ignoringLimit: true)
            } catch {
                preconditionFailure("A part \(part.id) cannot hit the limit: \(error)")
            }
            changes.append(tombstone.map(LibraryChange.erase) ?? .stroke(part))
        }
        assert(changes.count == removed.count + parts.count, "Each stroke gives one row")
        return changes
    }

    /// Removes the parts and puts the cut strokes back.
    ///
    /// The undo fails at the limit only if it adds more strokes than it removes.
    ///
    /// - Throws: `CommandError.strokeNotLive` if a part is not live,
    ///   `CommandError.strokeAlreadyLive` if a removed stroke is live, or
    ///   `CommandError.strokeLimitReached` if the undo grows the canvas past the limit.
    /// - Returns: The erase records of the parts and the tombstones of the removed strokes.
    public func revert(
        on content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        for part in parts where content.strokes[part.id] == nil {
            throw .strokeNotLive(part.id)
        }
        for stroke in removed where content.strokes[stroke.id] != nil {
            throw .strokeAlreadyLive(stroke.id)
        }
        let count = content.strokes.count - parts.count + removed.count
        guard count <= Limits.maxStrokesPerCanvas || removed.count <= parts.count else {
            throw .strokeLimitReached
        }
        let time = clock.now()
        var changes: [LibraryChange] = []
        changes.reserveCapacity(removed.count + parts.count)
        for part in parts {
            changes.append(.erase(content.remove(part.id, at: time)))
        }
        for stroke in removed {
            let tombstone: EraseRecord?
            do {
                tombstone = try content.restore(stroke, at: time, ignoringLimit: true)
            } catch {
                preconditionFailure("The limit check above failed for stroke \(stroke.id)")
            }
            assert(tombstone != nil, "A removed stroke \(stroke.id) has an erase record")
            changes.append(tombstone.map(LibraryChange.erase) ?? .stroke(stroke))
        }
        assert(content.strokes.count == count, "The undo leaves \(count) strokes")
        return changes
    }
}
