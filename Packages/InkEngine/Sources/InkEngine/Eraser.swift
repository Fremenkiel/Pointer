import Foundation
import Geometry
import Model
import os

/// Turns one eraser gesture into one `EraseStrokes` command (architecture.md 4.4, D-30).
public enum Eraser {
    /// The control points on each side of a cut whose segments change with it (D-65, D-72).
    static let changedPointsPerSide = 3
    /// The distance up to which the end of a part is the end of its old stroke, in canvas
    /// points. A part stores `Float` offsets from its new origin, so its kept end moves by the
    /// rounding of a `Float`.
    static let endTolerance = 0.001

    /// One stroke that the path touches, with the shapes of its parts and the canvas area where
    /// its ink changes.
    private struct Cut: Sendable {
        let stroke: Stroke
        let shapes: [Stroke]
        let changed: Rect
    }

    /// Returns the command of a gesture, or `nil` if the path touches no stroke.
    ///
    /// Each stroke that the path covers is removed. Its parts outside the eraser come back as new
    /// strokes (D-65, D-71). A stroke that the path covers whole leaves no part. The split of many
    /// strokes runs on several threads. The parts get their IDs afterward, in order.
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
        // The set costs about 2 % of an erase of 1,000 strokes in a release build, so the check
        // runs in debug builds only (the M10 plan task 3.2). A stroke twice in release fails the
        // apply with `strokeNotLive`, which rolls the content back.
        assert(
            Set(candidates.map(\.id)).count == candidates.count,
            "A candidate stroke appears twice"
        )
        let pathBounds = path.bounds
        // A serial filter of the bounds first: a miss costs about 0.4 µs on the threads of the
        // split and much less here (review M9 section 3.3, item 8, the M10 plan task 3.2).
        let near = candidates.filter {
            $0.bounds.expanded(by: path.radius).intersects(pathBounds)
        }
        let cuts = split(near, along: path)
        guard !cuts.isEmpty else { return nil }
        var parts: [Stroke] = []
        for cut in cuts {
            for shape in cut.shapes {
                parts.append(StrokeSplitter.finish(shape, factory: &factory))
            }
        }
        // Covered ink lies within the radius plus the width of the path, and the round end of
        // a part stays inside it too. The curve of a part also changes next to a cut (F-07).
        let width = cuts.map { Double($0.stroke.width) }.max() ?? 0
        let area = cuts.reduce(pathBounds.expanded(by: width)) { union($0, $1.changed) }
        return EraseStrokes(removed: cuts.map(\.stroke), parts: parts, area: area)
    }

    /// Returns the area where the ink of a cut stroke changes: the old control points next to
    /// each cut, the control points of each part next to a cut, and half the width. A stroke
    /// without a part changes whole (D-71).
    ///
    /// - Precondition: `covered` is not empty.
    static func changedArea(
        of stroke: Stroke,
        covered: [ClosedRange<Double>],
        shapes: [Stroke]
    ) -> Rect {
        precondition(!covered.isEmpty, "A cut stroke has a covered range")
        let half = Double(stroke.width) / 2
        guard !shapes.isEmpty else { return stroke.bounds.expanded(by: half) }
        let side = changedPointsPerSide
        let last = stroke.points.count - 1
        var area: Rect?
        for range in covered {
            // The part before the cut keeps the control points up to the one before the cut
            // parameter rounded up, and the part after keeps them from the one after the cut
            // parameter rounded down, as `StrokeSplitter.partPoints` does. The `side` old
            // segments next to each kept end change (review of 2026-10-28, 3.2.7).
            let low = max(Int(range.lowerBound.rounded(.up)) - side, 0)
            let high = min(Int(range.upperBound.rounded(.down)) + side, last)
            for index in low...high { area = union(area, stroke.canvasPoint(at: index)) }
        }
        // Only an end at a cut changes. An end of the old stroke keeps its point, so it is no cut.
        let first = stroke.canvasPoint(at: 0)
        let end = stroke.canvasPoint(at: last)
        for shape in shapes {
            let count = shape.points.count
            let startsAtCut = shape.canvasPoint(at: 0).distance(to: first) > endTolerance
            let endsAtCut = shape.canvasPoint(at: count - 1).distance(to: end) > endTolerance
            for index in 0..<count
            where (startsAtCut && index < side) || (endsAtCut && index >= count - side) {
                area = union(area, shape.canvasPoint(at: index))
            }
        }
        guard let area else { preconditionFailure("A cut changes the ink somewhere") }
        return area.expanded(by: half)
    }

    private static func union(_ first: Rect, _ second: Rect) -> Rect {
        Rect(
            minX: min(first.minX, second.minX),
            minY: min(first.minY, second.minY),
            maxX: max(first.maxX, second.maxX),
            maxY: max(first.maxY, second.maxY)
        )
    }

    private static func union(_ rect: Rect?, _ point: Point) -> Rect {
        let dot = Rect(minX: point.x, minY: point.y, maxX: point.x, maxY: point.y)
        return rect.map { union($0, dot) } ?? dot
    }

    /// Returns the strokes that the path covers, with the shapes of their parts, in the order of
    /// `strokes`.
    private static func split(_ strokes: [Stroke], along path: EraserPath) -> [Cut] {
        // The chunks of the split follow `ParallelChunks`, as the layouts of a load do.
        let chunkCount = ParallelChunks.count(of: strokes.count)
        let results = OSAllocatedUnfairLock(initialState: [[Cut]](repeating: [], count: chunkCount))
        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunk in
            let range = ParallelChunks.range(
                of: chunk,
                chunkCount: chunkCount,
                itemCount: strokes.count
            )
            var local: [Cut] = []
            for stroke in strokes[range] {
                let covered = StrokeHitTest.coveredRanges(of: stroke, by: path)
                guard !covered.isEmpty else { continue }
                let shapes = StrokeSplitter.shapes(of: stroke, outside: covered)
                let changed = changedArea(of: stroke, covered: covered, shapes: shapes)
                local.append(Cut(stroke: stroke, shapes: shapes, changed: changed))
            }
            let done = local
            results.withLock { $0[chunk] = done }
        }
        let cuts = results.withLock { $0 }.flatMap { $0 }
        assert(cuts.count <= strokes.count, "More cuts than strokes")
        return cuts
    }
}
