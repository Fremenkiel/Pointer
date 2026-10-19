import Geometry
import Model

/// Turns one eraser gesture into one `EraseStrokes` command (architecture.md 4.4, D-30).
public enum Eraser {
    /// Returns the command of a gesture, or `nil` if the path touches no stroke.
    ///
    /// Each stroke that the path covers is removed. Its parts outside the eraser come back as new
    /// strokes (D-65, D-71). A stroke that the path covers whole leaves no part.
    ///
    /// - Parameters:
    ///   - candidates: The strokes whose bounds touch the path, for example from the spatial grid
    ///     of the canvas. Other strokes are ignored.
    ///   - path: The path of the gesture.
    ///   - factory: The source of the IDs and the clock values of the parts.
    /// - Precondition: Each candidate appears once.
    /// - Returns: The command, with the removed strokes in the order of `candidates`.
    public static func command(
        erasing candidates: [Stroke],
        along path: EraserPath,
        factory: inout StrokeFactory
    ) -> EraseStrokes? {
        precondition(
            Set(candidates.map(\.id)).count == candidates.count,
            "A candidate stroke appears twice"
        )
        let pathBounds = path.bounds
        var removed: [Stroke] = []
        var parts: [Stroke] = []
        for stroke in candidates where stroke.bounds.intersects(pathBounds) {
            let covered = StrokeHitTest.coveredRanges(of: stroke, by: path)
            guard !covered.isEmpty else { continue }
            removed.append(stroke)
            parts += StrokeSplitter.parts(of: stroke, outside: covered, factory: &factory)
        }
        assert(removed.count <= candidates.count, "More strokes removed than given")
        guard !removed.isEmpty else { return nil }
        return EraseStrokes(removed: removed, parts: parts)
    }
}
