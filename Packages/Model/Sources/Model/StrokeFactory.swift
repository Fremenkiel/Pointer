import Geometry

/// Turns a finished pen path into strokes of the model (architecture.md 4.2).
///
/// An affine transform of the control points gives the same transform of the curve, so the
/// conversion does not change the shape. A path above `Limits.maxPointsPerStroke` control points
/// becomes several strokes. Each one starts with the last `Limits.strokeOverlapPoints` control
/// points of the stroke before it, so the curve continues without a gap or a kink.
public struct StrokeFactory {
    /// The source of the stroke IDs.
    public var identifiers: IdentifierFactory
    /// The source of the creation times.
    public var clock: HybridClock

    /// Makes a factory.
    public init(identifiers: IdentifierFactory, clock: HybridClock) {
        self.identifiers = identifiers
        self.clock = clock
    }

    /// Converts a path into one or more strokes on `canvasID`.
    ///
    /// - Throws: `ModelError.emptyPath` without samples, `ModelError.invalidPath` for a value
    ///   that is not finite or a width that is not positive.
    /// - Returns: The strokes in drawing order. A path with one sample gives a dot of two points.
    public mutating func makeStrokes(
        from path: PenPath,
        canvasID: CanvasID
    ) throws(ModelError) -> [Stroke] {
        guard !path.samples.isEmpty else { throw .emptyPath }
        let scale = abs(path.toCanvas.determinant).squareRoot()
        let width = path.width * scale
        guard width > 0, width.isFinite, width <= Double(Float.greatestFiniteMagnitude) else {
            throw .invalidPath(reason: "width \(path.width) at scale \(scale)")
        }
        var samples = try Self.canvasSamples(path)
        if samples.count == 1 {
            samples.append(samples[0])
        }
        let runs = Self.runs(count: samples.count, limit: Limits.maxPointsPerStroke)
        let strokes = runs.map { run in
            makeStroke(Array(samples[run]), width: Float(width), canvasID: canvasID)
        }
        return strokes
    }

    /// Returns the index ranges of the strokes of a path with `count` control points.
    ///
    /// - Precondition: `count >= 2`, and `limit` is greater than the overlap.
    /// - Returns: Ranges of at most `limit` points. Neighbor ranges share the overlap points.
    public static func runs(count: Int, limit: Int) -> [Range<Int>] {
        precondition(count >= 2, "A path needs 2 points, got \(count)")
        precondition(limit > Limits.strokeOverlapPoints, "Run limit \(limit) is too small")
        let step = limit - Limits.strokeOverlapPoints
        let runCount = count <= limit ? 1 : 1 + (count - limit + step - 1) / step
        let runs = (0..<runCount).map { index in
            let start = index * step
            return start..<min(start + limit, count)
        }
        assert(runs.last?.upperBound == count, "The runs must end at the last point")
        return runs
    }

    private static func canvasSamples(_ path: PenPath) throws(ModelError) -> [ControlPointSample] {
        var result: [ControlPointSample] = []
        result.reserveCapacity(path.samples.count)
        for sample in path.samples {
            let location = path.toCanvas.apply(to: sample.location)
            guard location.isFinite, sample.timeOffset.isFinite, sample.force.isFinite else {
                throw .invalidPath(reason: "sample \(result.count) is not finite")
            }
            result.append(
                ControlPointSample(
                    location: location,
                    force: sample.force,
                    timeOffset: sample.timeOffset
                )
            )
        }
        return result
    }

    private mutating func makeStroke(
        _ samples: [ControlPointSample],
        width: Float,
        canvasID: CanvasID
    ) -> Stroke {
        precondition(samples.count >= 2, "A stroke needs 2 samples, got \(samples.count)")
        let origin = samples[0].location
        let startTime = samples[0].timeOffset
        let points = samples.map { sample in
            InkPoint(
                x: Float(sample.location.x - origin.x),
                y: Float(sample.location.y - origin.y),
                force: Float(sample.force),
                time: Float(sample.timeOffset - startTime)
            )
        }
        return Stroke(
            id: identifiers.make(StrokeID.self),
            canvasID: canvasID,
            created: clock.now(),
            origin: origin,
            width: width,
            points: InkPoints(points)
        )
    }
}
