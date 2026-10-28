import Model

/// Splits strokes into level-of-detail runs (the M2 fix plan, phase 3, task 2).
///
/// A stroke is cut into blocks of `segmentsPerBlock` segments. Neighbor blocks with the same
/// pieces per segment merge into one run, and each run gets its stride and pieces from its own
/// spacing. One long segment then sets the pieces of its block only, not of the whole stroke. A
/// stroke whose blocks all have the same pieces stays one run with the detail of the whole
/// stroke, because a split adds a used point at each run boundary.
enum DetailRuns {
    /// The segments of one block.
    static let segmentsPerBlock = 64
    /// The largest stride that a draw entry can hold.
    static let maxStride = 0xFFF

    /// The number of blocks of a stroke.
    ///
    /// - Precondition: `pointCount >= 2`.
    static func blockCount(pointCount: Int) -> Int {
        precondition(pointCount >= 2, "A stroke has 2 points at least, got \(pointCount)")
        let count = (pointCount - 2) / segmentsPerBlock + 1
        assert(count * segmentsPerBlock >= pointCount - 1, "The blocks cover all segments")
        return count
    }

    /// Calls `body` with each run of a stroke, in order.
    ///
    /// - Precondition: One spacing per block, and a positive pixel scale and spacing.
    static func forEach(
        pointCount: Int,
        spacings: ArraySlice<BlockSpacing>,
        scale: DetailScale,
        bend: (Int) -> Float,
        body: (DetailRun) -> Void
    ) {
        precondition(
            spacings.count == blockCount(pointCount: pointCount),
            "Stroke of \(pointCount) points has \(spacings.count) block spacings"
        )
        precondition(scale.pixelsPerCanvasPoint > 0, "Pixel scale must be positive")
        var linker = RunLinker(pointCount: pointCount)
        var pending: Span?
        for (offset, spacing) in spacings.enumerated() {
            let start = offset * segmentsPerBlock
            let block = Span(
                start: start,
                end: min(start + segmentsPerBlock, pointCount - 1),
                block: offset,
                spacing
            )
            let pieces = block.detail(scale, bend: bend).piecesPerSegment
            guard let current = pending else {
                pending = block.with(pieces: pieces)
                continue
            }
            if current.pieces == pieces {
                pending = current.merged(with: block)
            } else {
                linker.add(current.run(scale, bend: bend), body)
                pending = block.with(pieces: pieces)
            }
        }
        guard let last = pending else { preconditionFailure("A stroke has one run at least") }
        assert(last.end == pointCount - 1, "The last run ends at the last point")
        linker.add(last.run(scale, bend: bend), body)
        linker.finish(body)
    }
}

/// Holds back one run until the next run is known, and sets the neighbor offsets of each run.
private struct RunLinker {
    /// The points of the stroke.
    let pointCount: Int
    private var held: DetailRun?
    /// The step from the used point before the end of the held run to its end: its stride, or
    /// less when the stride does not divide its length.
    private var previousBack = 0

    /// Makes a linker for a stroke of `pointCount` points.
    init(pointCount: Int) {
        self.pointCount = pointCount
    }

    /// Takes the next run and gives the held run to `body`.
    mutating func add(_ run: DetailRun, _ body: (DetailRun) -> Void) {
        if let held {
            emit(held, nextStride: run.stride, body)
        }
        held = run
    }

    /// Gives the last run to `body`.
    mutating func finish(_ body: (DetailRun) -> Void) {
        guard let held else { preconditionFailure("A stroke has one run at least") }
        emit(held, nextStride: 0, body)
        self.held = nil
    }

    private mutating func emit(_ run: DetailRun, nextStride: Int, _ body: (DetailRun) -> Void) {
        var linked = run
        linked.previousOffset = min(previousBack, run.start)
        linked.nextOffset = min(nextStride, pointCount - 1 - run.end)
        assert(run.start == 0 || linked.previousOffset > 0, "An inner run has a neighbor before")
        // The last used point of a run is its end, so the step before it is shorter than the
        // stride when the stride does not divide the length. The next run reads that used point,
        // not the point one stride back, so the two curves meet (review of 2026-10-28).
        previousBack = run.end - (run.start + (run.usedPointCount - 2) * run.stride)
        assert(previousBack > 0 && previousBack <= run.stride, "A back step within the stride")
        body(linked)
    }
}

/// The pixel scale and the rules of one level-of-detail computation.
struct DetailScale {
    /// Pixels per canvas point of the target.
    let pixelsPerCanvasPoint: Double
    /// The smallest screen distance between two used control points.
    var minimum = LevelOfDetail.minimumPixelSpacing
    /// `false` cuts the segments by length, into pieces of `LevelOfDetail.targetPiecePixels`, as
    /// before phase 3, task 3. Only the tests turn it off.
    var usesSmoothPieces = true
}

/// A part of a stroke with its total length and its largest neighbor spacing.
private struct Span {
    /// The first point of the span.
    let start: Int
    /// The last point of the span.
    let end: Int
    /// The first and the last block of the span, in the stroke.
    let blocks: ClosedRange<Int>
    /// The total length of the span.
    let length: Float
    /// The largest neighbor spacing of the span.
    let largest: Float
    /// The pieces per segment of the first block, the merge key.
    var pieces = 0

    /// Makes the span of one block.
    init(start: Int, end: Int, block: Int, _ spacing: BlockSpacing) {
        precondition(end > start, "A span has one segment at least")
        self.start = start
        self.end = end
        blocks = block...block
        length = spacing.mean * Float(end - start)
        largest = spacing.largest
    }

    private init(start: Int, end: Int, blocks: ClosedRange<Int>, length: Float, largest: Float) {
        self.start = start
        self.end = end
        self.blocks = blocks
        self.length = length
        self.largest = largest
    }

    /// Returns the span with `pieces` as its merge key.
    func with(pieces: Int) -> Span {
        var span = Span(start: start, end: end, blocks: blocks, length: length, largest: largest)
        span.pieces = pieces
        return span
    }

    /// Returns the span joined with the span after it.
    func merged(with next: Span) -> Span {
        precondition(next.start == end, "Merged spans must touch")
        precondition(next.blocks.lowerBound == blocks.upperBound + 1, "Merged blocks must touch")
        return Span(
            start: start,
            end: next.end,
            blocks: blocks.lowerBound...next.blocks.upperBound,
            length: length + next.length,
            largest: max(largest, next.largest)
        ).with(pieces: pieces)
    }

    /// The bend can only lower the pieces, so the span asks for it only if the length rule
    /// gives more than one piece. At low zoom, no block measures its bend.
    func detail(_ scale: DetailScale, bend: (Int) -> Float) -> LevelOfDetail {
        let byLength = detail(scale, bend: nil)
        guard scale.usesSmoothPieces, byLength.piecesPerSegment > 1 else { return byLength }
        let largestBend = blocks.reduce(Float(0)) { max($0, bend($1)) }
        return detail(scale, bend: Double(largestBend))
    }

    private func detail(_ scale: DetailScale, bend: Double?) -> LevelOfDetail {
        // A rounding step can give a mean above the largest spacing.
        let mean = min(Double(length) / Double(end - start), Double(largest))
        return LevelOfDetail(
            pointCount: end - start + 1,
            meanSpacing: mean,
            maxSpacing: Double(largest),
            pixelsPerCanvasPoint: scale.pixelsPerCanvasPoint,
            minimumPixelSpacing: scale.minimum,
            bend: bend
        )
    }

    /// Returns the run of the span at the scale.
    func run(_ scale: DetailScale, bend: (Int) -> Float) -> DetailRun {
        let detail = detail(scale, bend: bend)
        let stride = min(detail.stride, DetailRuns.maxStride)
        assert(stride >= 1, "A run has a stride of 1 at least")
        return DetailRun(start: start, end: end, stride: stride, pieces: detail.piecesPerSegment)
    }
}
