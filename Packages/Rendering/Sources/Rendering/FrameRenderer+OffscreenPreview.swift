import Geometry
import Metal
import Model

/// The checks of the offscreen preview of a canvas that is not on the screen (D-97, D-157).
extension FrameRenderer {
    /// Throws for a `status` other than `.completed`, with the text of `error`.
    static func checkCompleted(
        status: MTLCommandBufferStatus,
        error: (any Error)?
    ) throws(RenderingError) {
        guard status == .completed else {
            let reason = error.map { String(describing: $0) } ?? "no error"
            throw .resourceUnavailable("preview render, status \(status.rawValue), \(reason)")
        }
    }

    /// Returns true if the text of `box` can touch `region`. A box lays out its lines down and
    /// to the right of its origin, at most `TextStyle.maxWidth` wide, so a box that starts
    /// below the region or far to one side stays out. A line holds one UTF-16 unit at least, so
    /// a box has at most one line more than its units, each `TextLayout.lineHeight` high, and a
    /// box that ends above the region stays out too (m10-plan.md task 3.4). The glyphs can
    /// reach `TextStore.boundsMargin` lines past the line box on each side, as the bounds of the
    /// store do. The text store then checks the bounds.
    static func mayTouch(_ box: TextBox, _ region: Rect) -> Bool {
        let lines = Double(box.text.utf16.count + 1)
        let margin = TextLayout.lineHeight * TextStore.boundsMargin
        let top = box.origin.y - margin
        let bottom = box.origin.y + lines * TextLayout.lineHeight + margin
        let left = box.origin.x - margin
        let right = box.origin.x + TextStyle.maxWidth + margin
        return top <= region.maxY && bottom >= region.minY && left <= region.maxX
            && right >= region.minX
    }
}

/// The split of the strokes of an offscreen preview into passes under an arena byte budget.
enum PreviewPasses {
    /// The smallest budget: one stroke of `Limits.maxPointsPerStroke` points fits.
    static var minimumByteBudget: Int { arenaBytes(points: Limits.maxPointsPerStroke) }

    /// Returns the bytes of an arena for `points` points: a block holds at most twice its
    /// points, and each size class can leave one partial slab.
    static func arenaBytes(points: Int) -> Int {
        let slabs = (points * 2) / SlabAllocator.slabPoints + SlabAllocator.classCount + 1
        return slabs * PointArena.bytesPerSlab
    }

    /// Splits `strokes` into passes whose arenas keep `byteBudget`, in their order. Without a
    /// stroke, the result is one empty pass.
    ///
    /// - Precondition: `byteBudget` is at least `minimumByteBudget`.
    static func split(_ strokes: [Stroke], byteBudget: Int) -> [[Stroke]] {
        precondition(byteBudget >= minimumByteBudget, "Budget \(byteBudget) holds no long stroke")
        var passes: [[Stroke]] = [[]]
        var points = 0
        for stroke in strokes {
            let count = stroke.points.count
            if points > 0 && arenaBytes(points: points + count) > byteBudget {
                passes.append([])
                points = 0
            }
            passes[passes.count - 1].append(stroke)
            points += count
        }
        assert(passes.allSatisfy { !$0.isEmpty } || strokes.isEmpty, "No pass is empty")
        return passes
    }
}
