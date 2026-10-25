import Geometry
import Model

/// Finds the parts of a stroke curve that an eraser path covers (architecture.md 4.4, TOOL-04).
///
/// A point of the curve is covered if its distance to the eraser path is less than the eraser
/// radius plus half the stroke width. Thus the cut is where the edge of the ink meets the eraser.
/// The test skips each segment whose hull is far from the path, because a B-spline segment stays
/// inside the hull of its 4 points. It samples the other segments and refines each change between
/// covered and free with a bisection.
enum StrokeHitTest {
    /// The most samples per segment. A segment is never longer than a few eraser radii in use.
    static let maxSamplesPerSegment = 64
    /// The sample spacing in parts of the covered distance (the radius plus half the width).
    static let samplesPerCoveredDistance = 4.0
    /// The bisection steps per cut. 14 steps place a cut within 1/16,384 of a segment.
    static let refinementSteps = 14

    /// Returns the curve parameter ranges that the path covers, in order and without overlap.
    ///
    /// - Returns: An empty list if the path misses the stroke. `0...maxParameter` if it covers the
    ///   whole stroke.
    public static func coveredRanges(
        of stroke: Stroke,
        by path: EraserPath
    ) -> [ClosedRange<Double>] {
        guard let probe = Probe(stroke: stroke, path: path) else { return [] }
        let near = probe.spline.segments(
            near: probe.nearBounds.expanded(by: probe.reach - path.radius)
        )
        var ranges: [ClosedRange<Double>] = []
        var start: Double?
        var next = 0
        for segment in near {
            // A covered point lies in the hull of each segment that holds it, so an open range
            // never ends at a far segment.
            assert(segment == next || start == nil, "Range open across far segment \(next)")
            probe.scan(segment: segment, start: &start, ranges: &ranges)
            next = segment + 1
        }
        if let start {
            assert(next == probe.spline.segmentCount, "Range open after far segment \(next)")
            ranges.append(start...probe.spline.maxParameter)
        }
        assert(
            zip(ranges, ranges.dropFirst()).allSatisfy { $0.upperBound < $1.lowerBound },
            "Covered ranges of stroke \(stroke.id) overlap"
        )
        return ranges
    }
}

/// The state of one hit test: one stroke and the eraser bands near it.
private struct Probe {
    /// The curve of the stroke.
    let spline: StrokeSpline
    /// The path of the eraser.
    let path: EraserPath
    /// The bands of the path near the stroke.
    let bands: [Int]
    /// The eraser radius plus half the stroke width.
    let reach: Double
    /// The union of the bounds of `bands`. Most segments miss it, so they need no other test.
    let nearBounds: Rect

    /// Makes the probe, or returns `nil` if no band of the path comes near the stroke.
    init?(stroke: Stroke, path: EraserPath) {
        let pathBounds = path.bounds
        let strokeBounds = stroke.bounds.expanded(by: path.radius)
        guard strokeBounds.intersects(pathBounds) else { return nil }
        // The query covers only the overlap, so a long stroke reads few cells of the grid.
        let bands = path.bands(
            touching: Rect(
                minX: max(strokeBounds.minX, pathBounds.minX),
                minY: max(strokeBounds.minY, pathBounds.minY),
                maxX: min(strokeBounds.maxX, pathBounds.maxX),
                maxY: min(strokeBounds.maxY, pathBounds.maxY)
            )
        )
        guard !bands.isEmpty else { return nil }
        spline = StrokeSpline(stroke: stroke)
        self.path = path
        self.bands = bands
        reach = path.radius + Double(stroke.width) / 2
        // One loop, without the 4 arrays of a `map` per side (P-05).
        var near = path.bandBounds[bands[0]]
        for band in bands.dropFirst() {
            let bounds = path.bandBounds[band]
            near = Rect(
                minX: min(near.minX, bounds.minX),
                minY: min(near.minY, bounds.minY),
                maxX: max(near.maxX, bounds.maxX),
                maxY: max(near.maxY, bounds.maxY)
            )
        }
        nearBounds = near
        assert(reach > path.radius, "The reach includes half the stroke width")
    }

    /// Adds the covered ranges of one segment. `start` holds the start of an open range.
    func scan(segment: Int, start: inout Double?, ranges: inout [ClosedRange<Double>]) {
        let hull = spline.hullBounds(ofSegment: segment).expanded(by: reach - path.radius)
        let low = Double(segment)
        // The segment stays inside the convex hull of its 4 points, and a band is convex. If one
        // band holds all 4 points, it holds the whole segment, which then needs no samples.
        if isHullCovered(segment: segment, hull: hull) {
            if start == nil { start = Self.open(at: low, after: &ranges) }
            return
        }
        // An open range ends at a covered point, which lies in this hull, so it has bands. The
        // bands of the segment are the ones whose bounds touch the hull, without an array (P-05).
        guard hull.intersects(nearBounds), hasBand(touching: hull) else {
            assert(start == nil, "Range open at segment \(segment) without bands")
            return
        }
        let steps = sampleCount(segment: segment)
        var previous = low
        var wasCovered = isCovered(low, hull: hull)
        assert(start == nil || wasCovered, "Range open at a free start of segment \(segment)")
        if wasCovered, start == nil { start = Self.open(at: low, after: &ranges) }
        for step in 1...steps {
            let parameter = low + Double(step) / Double(steps)
            let covered = isCovered(parameter, hull: hull)
            if covered != wasCovered {
                let cut = refine(
                    from: previous,
                    to: parameter,
                    hull: hull,
                    startCovered: wasCovered
                )
                if covered {
                    start = Self.open(at: cut, after: &ranges)
                } else if let open = start {
                    ranges.append(open...cut)
                    start = nil
                }
            }
            previous = parameter
            wasCovered = covered
        }
    }

    /// Returns the start of a range that opens at `parameter`. If the last range ends there, the
    /// free point between them has no length, so the last range opens again and the ranges stay
    /// apart, as the split needs.
    private static func open(
        at parameter: Double,
        after ranges: inout [ClosedRange<Double>]
    ) -> Double {
        guard let last = ranges.last, last.upperBound >= parameter else { return parameter }
        ranges.removeLast()
        assert(last.lowerBound <= parameter, "A range opens before the last one")
        return last.lowerBound
    }

    /// Returns `true` if one band holds the 4 points that shape the segment.
    private func isHullCovered(segment: Int, hull: Rect) -> Bool {
        precondition(segment >= 0 && segment < spline.segmentCount, "Segment \(segment) unknown")
        guard hull.intersects(nearBounds) else { return false }
        let origin = spline.stroke.origin
        for band in bands where path.bandBounds[band].intersects(hull) {
            var holdsAll = true
            for index in (segment - 1)...(segment + 2) where holdsAll {
                let value = spline.point(at: index)
                let point = Point(x: origin.x + Double(value.x), y: origin.y + Double(value.y))
                holdsAll = path.distance(from: point, toBand: band) < reach
            }
            if holdsAll { return true }
        }
        return false
    }

    private func sampleCount(segment: Int) -> Int {
        let spacing = reach / StrokeHitTest.samplesPerCoveredDistance
        let count = (spline.hullLength(ofSegment: segment) / spacing).rounded(.up)
        assert(spacing > 0, "Sample spacing must be positive")
        guard count.isFinite else { return StrokeHitTest.maxSamplesPerSegment }
        return min(max(Int(count), 1), StrokeHitTest.maxSamplesPerSegment)
    }

    /// Returns `true` if the bounds of a band touch the hull of a segment.
    private func hasBand(touching hull: Rect) -> Bool {
        bands.contains { path.bandBounds[$0].intersects(hull) }
    }

    /// Returns `true` if a band whose bounds touch the hull of the segment covers the point.
    private func isCovered(_ parameter: Double, hull: Rect) -> Bool {
        let point = spline.position(at: parameter)
        return bands.contains {
            path.bandBounds[$0].intersects(hull) && path.distance(from: point, toBand: $0) < reach
        }
    }

    /// Returns the parameter of the change between covered and free inside `low...high`, with
    /// the bands of the segment hull.
    private func refine(
        from low: Double,
        to high: Double,
        hull: Rect,
        startCovered: Bool
    ) -> Double {
        precondition(low < high, "Refinement range \(low)...\(high) is empty")
        var lower = low
        var upper = high
        for _ in 0..<StrokeHitTest.refinementSteps {
            let middle = (lower + upper) / 2
            if isCovered(middle, hull: hull) == startCovered {
                lower = middle
            } else {
                upper = middle
            }
        }
        return startCovered ? upper : lower
    }
}
