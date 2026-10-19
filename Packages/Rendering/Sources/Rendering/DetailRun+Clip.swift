import Model

/// A box in the offsets of one stroke, for the clipped draw of a redraw (D-66).
struct ClipBox {
    /// The low corner.
    let low: SIMD2<Float>
    /// The high corner.
    let high: SIMD2<Float>

    /// Returns one bit for each side of the box that the point lies beyond.
    func code(_ point: InkPoint) -> UInt8 {
        (point.x < low.x ? 1 : 0) | (point.x > high.x ? 2 : 0) | (point.y < low.y ? 4 : 0)
            | (point.y > high.y ? 8 : 0)
    }
}

extension DetailRun {
    /// Calls `body` with each part of the run whose segments can touch `box`.
    ///
    /// A segment stays inside the bounds of its 4 shaping points, so a segment whose 4 points
    /// all lie beyond one side of the box misses it. Each part keeps the stride and the pieces
    /// of the run, and its neighbor offsets point at the used points next to it. Thus the
    /// curve of a part equals the curve of the run there.
    ///
    /// - Precondition: `points` are the points of the stroke of the run.
    func forEachClipped(points: [InkPoint], box: ClipBox, body: (DetailRun) -> Void) {
        precondition(end < points.count, "Run end \(end) is past the stroke")
        let count = usedPointCount
        assert(count >= 2, "A run uses two points at least")
        var window = (code(-1, points, box), code(0, points, box), code(1, points, box))
        var first: Int?
        for segment in 0..<(count - 1) {
            let next = code(segment + 2, points, box)
            let isNear = window.0 & window.1 & window.2 & next == 0
            if isNear, first == nil {
                first = segment
            } else if !isNear, let start = first {
                body(part(from: start, through: segment - 1))
                first = nil
            }
            window = (window.1, window.2, next)
        }
        if let start = first {
            body(part(from: start, through: count - 2))
        }
    }

    /// Returns the stroke index of used point `index` of the run.
    private func usedIndex(_ index: Int) -> Int {
        index < usedPointCount - 1 ? start + index * stride : end
    }

    /// Returns the outcode of used point `index`, with the neighbor or phantom point at -1 and
    /// at `usedPointCount`, as the shader reads them.
    private func code(_ index: Int, _ points: [InkPoint], _ box: ClipBox) -> UInt8 {
        let count = usedPointCount
        assert(index >= -1 && index <= count, "Used point \(index) out of -1...\(count)")
        if index == -1 {
            if previousOffset > 0 { return box.code(points[start - previousOffset]) }
            return box.code(Self.mirror(points[start], points[usedIndex(1)]))
        }
        if index >= count {
            if nextOffset > 0 { return box.code(points[end + nextOffset]) }
            return box.code(Self.mirror(points[end], points[usedIndex(count - 2)]))
        }
        return box.code(points[usedIndex(index)])
    }

    /// Returns the part from segment `first` through segment `last`.
    private func part(from first: Int, through last: Int) -> DetailRun {
        precondition(first >= 0 && first <= last, "Clipped segments \(first)...\(last) invalid")
        let partStart = usedIndex(first)
        let partEnd = usedIndex(last + 1)
        let isRunEnd = last + 1 == usedPointCount - 1
        assert(partEnd <= end, "A clipped part ends after its run")
        return DetailRun(
            start: partStart,
            end: partEnd,
            stride: stride,
            pieces: pieces,
            previousOffset: first == 0 ? previousOffset : partStart - usedIndex(first - 1),
            nextOffset: isRunEnd ? nextOffset : usedIndex(last + 2) - partEnd
        )
    }

    private static func mirror(_ end: InkPoint, _ next: InkPoint) -> InkPoint {
        InkPoint(x: 2 * end.x - next.x, y: 2 * end.y - next.y, force: 0, time: 0)
    }
}
