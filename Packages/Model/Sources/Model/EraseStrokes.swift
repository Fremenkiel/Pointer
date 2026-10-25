import Geometry

/// One eraser gesture: the strokes that it removed and the parts that it left (D-06, D-30).
///
/// The parts can take the canvas past `Limits.maxStrokesPerCanvas`, because an erase never
/// fails (D-71). They never take it past `Limits.maxStrokesAfterErase`: the eraser then makes
/// a command without parts (D-73). The undo removes the parts with erase records and turns the
/// erase records of the removed strokes into tombstones (data-model.md 7.5).
public struct EraseStrokes: CanvasCommand {
    /// The strokes that the gesture cut or removed whole.
    public let removed: [Stroke]
    /// The new strokes outside the eraser circles.
    public let parts: [Stroke]
    /// The canvas area where the ink changes, or `nil` if it is not known. Outside it, the
    /// parts show the same ink as the removed strokes, so the renderer redraws only this area
    /// at the erase, its undo, and its redo (D-66).
    public let area: Rect?
    /// The control points of the removed strokes and the parts (D-76).
    public let heldPointCount: Int

    /// Makes the command.
    ///
    /// - Precondition: At least one removed stroke, and each stroke ID appears once.
    public init(removed: [Stroke], parts: [Stroke], area: Rect? = nil) {
        precondition(!removed.isEmpty, "EraseStrokes needs a removed stroke")
        // The set costs about 8 % of an erase of 1,000 strokes in a release build, so the check
        // runs in debug builds only (m10-plan.md task 3.2). A stroke twice in release fails the
        // apply with `strokeNotLive` or `strokeAlreadyLive`, which rolls the content back.
        assert(
            Set(removed.map(\.id) + parts.map(\.id)).count == removed.count + parts.count,
            "EraseStrokes holds a stroke twice"
        )
        self.removed = removed
        self.parts = parts
        self.area = area
        heldPointCount =
            removed.reduce(0) { $0 + $1.points.count } + parts.reduce(0) { $0 + $1.points.count }
    }

    /// Calls `body` with the ID of each removed stroke and each part.
    public func forEachHeldStroke(_ body: (StrokeID) -> Void) {
        for stroke in removed { body(stroke.id) }
        for part in parts { body(part.id) }
    }

    /// Removes the cut strokes and adds the parts. A first apply returns the rows of the new
    /// parts, and a redo returns the tombstones of their erase records.
    ///
    /// - Throws: `CommandError.strokeNotLive` if a removed stroke is not live,
    ///   `CommandError.strokeAlreadyLive` if a part is live, or
    ///   `CommandError.strokeLimitReached` if the parts pass `Limits.maxStrokesAfterErase`.
    /// - Returns: The erase records of the removed strokes and the rows of the parts.
    public func apply(
        to content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        let count = content.strokes.count - removed.count + parts.count
        guard count <= Limits.maxStrokesAfterErase || parts.count <= removed.count else {
            throw .strokeLimitReached
        }
        let time = clock.now()
        var changes: [LibraryChange] = []
        changes.reserveCapacity(removed.count + parts.count)
        // Each stroke is checked and changed with one lookup. A failed check takes the step back,
        // so the content stays as it was (P-07).
        var log = CanvasContent.ChangeLog(capacity: removed.count + parts.count)
        do {
            try content.remove(removed, at: time, log: &log, changes: &changes)
            try content.restore(parts, at: time, needsRecords: false, log: &log, changes: &changes)
        } catch {
            content.rollBack(log)
            throw error
        }
        assert(changes.count == removed.count + parts.count, "Each stroke gives one row")
        return changes
    }

    /// Removes the parts and puts the cut strokes back.
    ///
    /// The undo takes the canvas up to `Limits.maxStrokesAfterErase`, because the state that it
    /// gives back existed one step before (D-159).
    ///
    /// - Throws: `CommandError.strokeNotLive` if a part is not live,
    ///   `CommandError.strokeAlreadyLive` if a removed stroke is live,
    ///   `CommandError.eraseRecordMissing` if the content has no erase record of a removed
    ///   stroke, or `CommandError.strokeLimitReached` if the undo grows the canvas past
    ///   `Limits.maxStrokesAfterErase`. The content then stays as it was.
    /// - Returns: The erase records of the parts and the tombstones of the removed strokes.
    public func revert(
        on content: inout CanvasContent,
        clock: inout HybridClock
    ) throws(CommandError) -> [LibraryChange] {
        let count = content.strokes.count - parts.count + removed.count
        guard count <= Limits.maxStrokesAfterErase || removed.count <= parts.count else {
            throw .strokeLimitReached
        }
        let time = clock.now()
        var changes: [LibraryChange] = []
        changes.reserveCapacity(removed.count + parts.count)
        // A load without the session records would turn the erase records into live ones, so a
        // removed stroke needs its record (F-14). One lookup per stroke, as in `apply` (P-07).
        var log = CanvasContent.ChangeLog(capacity: removed.count + parts.count)
        do {
            try content.remove(parts, at: time, log: &log, changes: &changes)
            try content.restore(removed, at: time, needsRecords: true, log: &log, changes: &changes)
        } catch {
            content.rollBack(log)
            throw error
        }
        assert(content.strokes.count == count, "The undo leaves \(count) strokes")
        return changes
    }
}
