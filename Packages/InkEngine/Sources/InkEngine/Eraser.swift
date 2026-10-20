import Foundation
import Geometry
import Model
import os

/// Turns one eraser gesture into one `EraseStrokes` command (architecture.md 4.4, D-30).
public enum Eraser {
    /// The fewest candidates of one chunk of the split. Fewer strokes run on one thread.
    static let minimumChunk = 64
    /// The most chunks of the split. The iPad Pro (M4) has 4 performance cores.
    static let maxChunks = 8

    /// One stroke that the path touches, with the shapes of its parts.
    private struct Cut: Sendable {
        let stroke: Stroke
        let shapes: [Stroke]
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
        precondition(
            Set(candidates.map(\.id)).count == candidates.count,
            "A candidate stroke appears twice"
        )
        let pathBounds = path.bounds
        let touched = candidates.filter { $0.bounds.intersects(pathBounds) }
        let cuts = split(touched, along: path)
        guard !cuts.isEmpty else { return nil }
        var parts: [Stroke] = []
        for cut in cuts {
            for shape in cut.shapes {
                parts.append(StrokeSplitter.finish(shape, factory: &factory))
            }
        }
        assert(cuts.count <= candidates.count, "More strokes removed than given")
        // Covered ink lies within the radius plus the width of the path, and the round end of
        // a part stays inside it too.
        let width = cuts.map { Double($0.stroke.width) }.max() ?? 0
        return EraseStrokes(
            removed: cuts.map(\.stroke),
            parts: parts,
            area: pathBounds.expanded(by: width)
        )
    }

    /// Returns the strokes that the path covers, with the shapes of their parts, in the order of
    /// `strokes`.
    private static func split(_ strokes: [Stroke], along path: EraserPath) -> [Cut] {
        let chunkCount = min(max(strokes.count / minimumChunk, 1), maxChunks)
        precondition(
            chunkCount >= 1 && chunkCount <= maxChunks,
            "Chunk count \(chunkCount) invalid"
        )
        let chunkSize = (strokes.count + chunkCount - 1) / max(chunkCount, 1)
        let results = OSAllocatedUnfairLock(initialState: [[Cut]](repeating: [], count: chunkCount))
        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunk in
            let range =
                min(chunk * chunkSize, strokes.count)..<min((chunk + 1) * chunkSize, strokes.count)
            var local: [Cut] = []
            for stroke in strokes[range] {
                let covered = StrokeHitTest.coveredRanges(of: stroke, by: path)
                guard !covered.isEmpty else { continue }
                local.append(
                    Cut(stroke: stroke, shapes: StrokeSplitter.shapes(of: stroke, outside: covered))
                )
            }
            let done = local
            results.withLock { $0[chunk] = done }
        }
        let cuts = results.withLock { $0 }.flatMap { $0 }
        assert(cuts.count <= strokes.count, "More cuts than strokes")
        return cuts
    }
}
