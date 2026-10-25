import Model

/// The spacing of one block of 64 segments of a stroke, in canvas points (`DetailRuns`).
struct BlockSpacing: Equatable {
    /// The mean distance between neighbor control points.
    let mean: Float
    /// The largest distance between neighbor control points.
    let largest: Float

    /// Appends the spacing of each block of a stroke. It runs for every stroke of a canvas at
    /// load time, so it measures lengths only. `bend(of:block:)` measures the curvature later,
    /// for the blocks that need it.
    ///
    /// - Precondition: The stroke has 2 points at least.
    static func append(of points: InkPoints, to spacings: inout [BlockSpacing]) {
        let values = points.values
        let blocks = DetailRuns.blockCount(pointCount: values.count)
        let before = spacings.count
        var block = Accumulator()
        for index in 1..<values.count {
            block.add(length: Edge(values[index - 1], values[index]).length)
            if index == values.count - 1 || (index % DetailRuns.segmentsPerBlock) == 0 {
                spacings.append(block.spacing())
                block = Accumulator()
            }
        }
        assert(spacings.count == before + blocks, "Each block has one spacing")
    }

    /// Returns the largest bend of a segment of one block: its length times its turn, in canvas
    /// points times radians. The turn of a segment is the larger angle of the control polygon
    /// at its two ends. The bend can lower the pieces (`LevelOfDetail`, docs/m2-fix-plan.md,
    /// phase 3, task 3).
    ///
    /// - Precondition: `block` is a block of the stroke.
    static func bend(of points: InkPoints, block: Int) -> Float {
        let values = points.values
        precondition(
            block >= 0 && block < DetailRuns.blockCount(pointCount: values.count),
            "Block \(block) is not in the stroke"
        )
        let first = block * DetailRuns.segmentsPerBlock
        let last = min(first + DetailRuns.segmentsPerBlock, values.count - 1)
        var edge = Edge(values[first], values[first + 1])
        var turnBefore =
            first > 0 ? turn(between: Edge(values[first - 1], values[first]), and: edge) : 0
        var bend: Float = 0
        for index in (first + 1)...last {
            let hasNext = index < values.count - 1
            let next = hasNext ? Edge(values[index], values[index + 1]) : edge
            let turnAfter = hasNext ? turn(between: edge, and: next) : 0
            bend = max(bend, edge.length * max(turnBefore, turnAfter))
            edge = next
            turnBefore = turnAfter
        }
        assert(bend >= 0 && bend.isFinite, "Bend \(bend) is invalid")
        return bend
    }

    /// The angle between two edges. The end points of a stroke turn by 0, because the mirrored
    /// phantom point continues the edge (D-26). An edge of zero length has no direction, so its
    /// point counts as a full turn.
    private static func turn(between first: Edge, and second: Edge) -> Float {
        let cross = first.dx * second.dy - first.dy * second.dx
        let dot = first.dx * second.dx + first.dy * second.dy
        guard cross != 0 || dot > 0 else { return .pi }
        let angle = angle(y: abs(cross), x: dot)
        assert(angle >= 0 && angle <= .pi, "Turn \(angle) is outside 0 to pi")
        return angle
    }

    /// Returns `atan2(y, x)` for `y >= 0` within about 0.004 radians, without a call to `atan2`:
    /// the load of 12 million control points spent tens of milliseconds in `atan2`.
    private static func angle(y: Float, x: Float) -> Float {
        precondition(y >= 0, "The angle needs y >= 0, got \(y)")
        let quarter = Float.pi / 4
        let ratio = x >= 0 ? (x - y) / (x + y) : (x + y) / (y - x)
        let base = x >= 0 ? quarter : 3 * quarter
        // The polynomial can leave the range by a rounding step, for example -2e-6 at 0.
        return min(max(base + (0.1963 * ratio * ratio - 0.9817) * ratio, 0), .pi)
    }
}

/// One edge of the control polygon.
private struct Edge {
    /// The horizontal extent.
    let dx: Float
    /// The vertical extent.
    let dy: Float
    /// The length.
    let length: Float

    /// Makes the edge from `from` to `to`.
    init(_ from: InkPoint, _ to: InkPoint) {
        dx = to.x - from.x
        dy = to.y - from.y
        length = (dx * dx + dy * dy).squareRoot()
    }
}

/// The running sums of one block.
private struct Accumulator {
    private var segments = 0
    private var total: Float = 0
    private var largest: Float = 0

    /// Adds one segment.
    mutating func add(length: Float) {
        segments += 1
        total += length
        largest = max(largest, length)
    }

    /// Returns the mean and the largest spacing of the block.
    func spacing() -> BlockSpacing {
        precondition(segments > 0, "A block has one segment at least")
        // Equal segments can give a mean one rounding step above the largest spacing.
        let mean = min(total / Float(segments), largest)
        return BlockSpacing(mean: mean, largest: largest)
    }
}
