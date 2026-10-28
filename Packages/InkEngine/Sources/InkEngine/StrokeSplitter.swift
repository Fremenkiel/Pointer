import Geometry
import Model

/// Makes the parts of a stroke outside the ranges that an eraser covers (architecture.md 4.4).
///
/// A part keeps the control points of the old stroke between its two cuts. At each cut, the point
/// of the curve at the cut becomes the new end point (D-65). The end rule of the curve then makes
/// the part end exactly at the cut. The new end point gets the force and the time of the curve at
/// the cut. A part whose curve is shorter than the stroke width is dropped (D-71).
enum StrokeSplitter {
    /// The samples per segment for the length of a part. The length only decides the drop of a
    /// short part, so a few samples are enough.
    static let lengthSamplesPerSegment = 4

    /// Returns the parts of a stroke outside the covered ranges.
    ///
    /// Each part gets a new ID and a new creation time from `factory`, and the width and the
    /// canvas of the old stroke.
    ///
    /// - Precondition: The ranges lie in the parameter range of the stroke, in order, without
    ///   overlap.
    /// - Returns: The parts in curve order. Empty if the ranges cover the whole stroke or leave
    ///   only parts shorter than the width.
    public static func parts(
        of stroke: Stroke,
        outside covered: [ClosedRange<Double>],
        factory: inout StrokeFactory
    ) -> [Stroke] {
        let shapes = shapes(of: stroke, outside: covered)
        let parts = shapes.map { finish($0, factory: &factory) }
        return parts
    }

    /// Returns the parts of a stroke outside the covered ranges, with the ID and the creation
    /// time of the old stroke. `finish(_:factory:)` gives them their own. Without a factory, the
    /// split can run on several threads.
    ///
    /// - Precondition: The ranges lie in the parameter range of the stroke, in order, without
    ///   overlap.
    static func shapes(of stroke: Stroke, outside covered: [ClosedRange<Double>]) -> [Stroke] {
        let spline = StrokeSpline(stroke: stroke)
        precondition(
            covered.allSatisfy { $0.lowerBound >= 0 && $0.upperBound <= spline.maxParameter },
            "A covered range lies outside stroke \(stroke.id)"
        )
        precondition(
            zip(covered, covered.dropFirst()).allSatisfy { $0.upperBound < $1.lowerBound },
            "Covered ranges of stroke \(stroke.id) overlap"
        )
        var parts: [Stroke] = []
        for range in freeRanges(outside: covered, upTo: spline.maxParameter) {
            let points = partPoints(of: spline, from: range.lowerBound, to: range.upperBound)
            guard let part = makePart(points, of: stroke) else { continue }
            parts.append(part)
        }
        assert(parts.count <= covered.count + 1, "More parts than free ranges")
        return parts
    }

    /// Gives a shape of `shapes(of:outside:)` a new ID and a new creation time.
    static func finish(_ shape: Stroke, factory: inout StrokeFactory) -> Stroke {
        precondition(shape.points.count >= 2, "A shape needs 2 points")
        // The shape has its bounds already, so the part keeps them (P-04).
        return shape.renamed(
            id: factory.identifiers.make(StrokeID.self),
            created: factory.clock.now()
        )
    }

    /// Returns the ranges of `0...upper` outside the covered ranges, without empty ranges.
    static func freeRanges(
        outside covered: [ClosedRange<Double>],
        upTo upper: Double
    ) -> [ClosedRange<Double>] {
        precondition(upper > 0, "A curve has a positive parameter range, got \(upper)")
        var result: [ClosedRange<Double>] = []
        var start = 0.0
        for range in covered {
            if range.lowerBound > start { result.append(start...range.lowerBound) }
            start = range.upperBound
        }
        if start < upper { result.append(start...upper) }
        return result
    }

    /// Returns the control points of the part from `start` to `end`, as offsets from the first.
    private static func partPoints(
        of spline: StrokeSpline,
        from start: Double,
        to end: Double
    ) -> (origin: Point, points: [InkPoint]) {
        precondition(start < end, "A part needs a range, got \(start)...\(end)")
        let stroke = spline.stroke
        let first = cutPoint(of: spline, at: start)
        let shift = SIMD2<Double>(
            stroke.origin.x - first.position.x,
            stroke.origin.y - first.position.y
        )
        let interior = (Int(start.rounded(.down)) + 1)..<Int(end.rounded(.up))
        var result: [InkPoint] = []
        result.reserveCapacity(interior.count + 2)
        result.append(InkPoint(x: 0, y: 0, force: first.force, time: 0))
        // The time of a cut is a blend of the four stored times around it. After a pause of the
        // pencil, the blend can pass the next stored time, so each time is at least the time
        // before it (review of 2026-10-28). The times then stay seconds since the first point.
        var time: Float = 0
        for index in interior {
            let value = spline.values[index]
            time = max(time, value.time - first.time)
            result.append(
                InkPoint(
                    x: Float(Double(value.x) + shift.x),
                    y: Float(Double(value.y) + shift.y),
                    force: value.force,
                    time: time
                )
            )
        }
        let last = cutPoint(of: spline, at: end)
        result.append(
            InkPoint(
                x: Float(last.position.x - first.position.x),
                y: Float(last.position.y - first.position.y),
                force: last.force,
                time: max(time, last.time - first.time)
            )
        )
        return (first.position, result)
    }

    /// Returns the point of the curve at a cut. At an end of the stroke, the curve passes through
    /// the end point, so the stored point is kept as it is.
    private static func cutPoint(
        of spline: StrokeSpline,
        at parameter: Double
    ) -> CutPoint {
        precondition(
            (0...spline.maxParameter).contains(parameter),
            "Cut at \(parameter), outside 0...\(spline.maxParameter)"
        )
        let stroke = spline.stroke
        if parameter == 0 || parameter == spline.maxParameter {
            let index = Int(parameter)
            let value = spline.values[index]
            return CutPoint(
                position: stroke.canvasPoint(at: index),
                force: value.force,
                time: value.time
            )
        }
        let (force, time) = spline.forceAndTime(at: parameter)
        return CutPoint(position: spline.position(at: parameter), force: force, time: time)
    }

    /// Makes a part with the ID of its stroke, or returns `nil` if its curve is shorter than the
    /// width (D-71).
    private static func makePart(
        _ part: (origin: Point, points: [InkPoint]),
        of stroke: Stroke
    ) -> Stroke? {
        precondition(part.points.count >= 2, "A part needs 2 points, got \(part.points.count)")
        let made = Stroke(
            id: stroke.id,
            canvasID: stroke.canvasID,
            created: stroke.created,
            origin: part.origin,
            width: stroke.width,
            points: InkPoints(part.points)
        )
        guard isAtLeast(Double(stroke.width), long: StrokeSpline(stroke: made)) else { return nil }
        assert(made.points.count <= stroke.points.count, "A part has more points than its stroke")
        return made
    }

    /// Returns true if the curve is at least `length` long. It stops at that length.
    private static func isAtLeast(_ length: Double, long spline: StrokeSpline) -> Bool {
        precondition(length > 0, "A length must be positive, got \(length)")
        let steps = spline.segmentCount * lengthSamplesPerSegment
        var total = 0.0
        var previous = spline.position(at: 0)
        for step in 1...steps {
            let parameter = spline.maxParameter * Double(step) / Double(steps)
            let point = spline.position(at: parameter)
            total += previous.distance(to: point)
            if total >= length { return true }
            previous = point
        }
        assert(total < length, "The loop returns once the length is reached")
        return false
    }
}

/// The point of a curve at a cut, with the force and the time of the curve there.
private struct CutPoint {
    /// The position of the curve at the cut.
    let position: Point
    /// The force of the curve at the cut.
    let force: Float
    /// The time of the curve at the cut.
    let time: Float
}
