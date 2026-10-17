import Model

/// Splits strokes into level-of-detail runs (docs/m2-fix-plan.md, phase 3, task 2).
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

    /// Appends the mean and the largest neighbor spacing of each block of a stroke.
    ///
    /// - Precondition: The stroke has 2 points at least.
    static func appendSpacings(of points: InkPoints, to spacings: inout [SIMD2<Float>]) {
        let values = points.values
        let blocks = blockCount(pointCount: values.count)
        let before = spacings.count
        for block in 0..<blocks {
            let first = block * segmentsPerBlock
            let last = min(first + segmentsPerBlock, values.count - 1)
            var total: Float = 0
            var largest: Float = 0
            for index in (first + 1)...last {
                let dx = values[index].x - values[index - 1].x
                let dy = values[index].y - values[index - 1].y
                let length = (dx * dx + dy * dy).squareRoot()
                total += length
                largest = max(largest, length)
            }
            // Equal segments can give a mean one rounding step above the largest spacing.
            spacings.append(SIMD2(min(total / Float(last - first), largest), largest))
        }
        assert(spacings.count == before + blocks, "Each block has one spacing")
    }

    /// Calls `body` with each run of a stroke, in order.
    ///
    /// - Precondition: One spacing per block, and a positive pixel scale and spacing.
    static func forEach(
        pointCount: Int,
        spacings: ArraySlice<SIMD2<Float>>,
        pixelsPerCanvasPoint: Double,
        minimumPixelSpacing: Double,
        _ body: (DetailRun) -> Void
    ) {
        precondition(
            spacings.count == blockCount(pointCount: pointCount),
            "Stroke of \(pointCount) points has \(spacings.count) block spacings"
        )
        precondition(pixelsPerCanvasPoint > 0, "Pixel scale must be positive")
        let scale = Scale(pixelsPerCanvasPoint: pixelsPerCanvasPoint, minimum: minimumPixelSpacing)
        var linker = RunLinker(pointCount: pointCount)
        var pending: Span?
        for (offset, spacing) in spacings.enumerated() {
            let start = offset * segmentsPerBlock
            let block = Span(
                start: start,
                end: min(start + segmentsPerBlock, pointCount - 1),
                spacing
            )
            let pieces = block.detail(scale).piecesPerSegment
            guard let current = pending else {
                pending = block.with(pieces: pieces)
                continue
            }
            if current.pieces == pieces {
                pending = current.merged(with: block)
            } else {
                linker.add(current.run(scale), body)
                pending = block.with(pieces: pieces)
            }
        }
        guard let last = pending else { preconditionFailure("A stroke has one run at least") }
        assert(last.end == pointCount - 1, "The last run ends at the last point")
        linker.add(last.run(scale), body)
        linker.finish(body)
    }
}

/// Holds back one run until the next run is known, and sets the neighbor offsets of each run.
private struct RunLinker {
    let pointCount: Int
    private var held: DetailRun?
    private var previousStride = 0

    init(pointCount: Int) {
        self.pointCount = pointCount
    }

    mutating func add(_ run: DetailRun, _ body: (DetailRun) -> Void) {
        if let held {
            emit(held, nextStride: run.stride, body)
        }
        held = run
    }

    mutating func finish(_ body: (DetailRun) -> Void) {
        guard let held else { preconditionFailure("A stroke has one run at least") }
        emit(held, nextStride: 0, body)
        self.held = nil
    }

    private mutating func emit(_ run: DetailRun, nextStride: Int, _ body: (DetailRun) -> Void) {
        var linked = run
        linked.previousOffset = min(previousStride, run.start)
        linked.nextOffset = min(nextStride, pointCount - 1 - run.end)
        assert(run.start == 0 || linked.previousOffset > 0, "An inner run has a neighbor before")
        previousStride = run.stride
        body(linked)
    }
}

/// The pixel scale and the spacing of one level-of-detail computation.
private struct Scale {
    let pixelsPerCanvasPoint: Double
    let minimum: Double
}

/// A part of a stroke with its total length and its largest neighbor spacing.
private struct Span {
    let start: Int
    let end: Int
    let length: Float
    let largest: Float
    /// The pieces per segment of the first block, the merge key.
    var pieces = 0

    init(start: Int, end: Int, _ spacing: SIMD2<Float>) {
        precondition(end > start, "A span has one segment at least")
        self.start = start
        self.end = end
        length = spacing.x * Float(end - start)
        largest = spacing.y
    }

    private init(start: Int, end: Int, length: Float, largest: Float, pieces: Int) {
        self.start = start
        self.end = end
        self.length = length
        self.largest = largest
        self.pieces = pieces
    }

    func with(pieces: Int) -> Span {
        Span(start: start, end: end, length: length, largest: largest, pieces: pieces)
    }

    func merged(with next: Span) -> Span {
        precondition(next.start == end, "Merged spans must touch")
        return Span(
            start: start,
            end: next.end,
            length: length + next.length,
            largest: max(largest, next.largest),
            pieces: pieces
        )
    }

    func detail(_ scale: Scale) -> LevelOfDetail {
        // A rounding step can give a mean above the largest spacing.
        let mean = min(Double(length) / Double(end - start), Double(largest))
        return LevelOfDetail(
            pointCount: end - start + 1,
            meanSpacing: mean,
            maxSpacing: Double(largest),
            pixelsPerCanvasPoint: scale.pixelsPerCanvasPoint,
            minimumPixelSpacing: scale.minimum
        )
    }

    func run(_ scale: Scale) -> DetailRun {
        let detail = detail(scale)
        let stride = min(detail.stride, DetailRuns.maxStride)
        assert(stride >= 1, "A run has a stride of 1 at least")
        return DetailRun(start: start, end: end, stride: stride, pieces: detail.piecesPerSegment)
    }
}
